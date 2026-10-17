-- weave/sources/spr.lua
-- Resolves packages against the Silk Packages Repo's three tiers, in
-- trust order: official -> community -> open. Called by native.lua
-- only after a local weave/recipes/ lookup misses.

local shell = require("weave.util.shell")

local verify = require("weave.util.verify")

local TRUSTED_SIGNERS = "/etc/silk/trusted-signers"

local SPR_CACHE_PATH = "/silk/weave/cache/spr"

local TIER_REPOS = {
  official  = "https://github.com/silk-os/spr-official.git",
  community = "https://github.com/silk-os/spr-community.git",
}

local TIER_ORDER = { "official", "community" }

local synced_this_run = {} -- avoids re-pulling the same tier repo for every package in one run
local sync_info = {}       -- last verified-sync result per tier

local function path_exists(path)
  return os.execute("test -e '" .. path:gsub("'", "'\\''") .. "'") == true
end

local function sync_monorepo(tier)
  if synced_this_run[tier] then
    return
  end

  local status, info = verify.sync_signed_repo({
    url = TIER_REPOS[tier],
    dir = SPR_CACHE_PATH .. "/" .. tier,
    trusted_signers = TRUSTED_SIGNERS,
  })

  if status ~= "ok" then
    io.stderr:write(("spr: %s tier unavailable (%s), skipping\n"):format(tier, tostring(info)))
  else
    sync_info[tier] = info
    for _, s in ipairs(info.skipped or {}) do
      io.stderr:write(("spr: %s tier: newer tag '%s' ignored (%s)\n"):format(tier, s.tag, s.reason))
    end
  end

  synced_this_run[tier] = true
end

local function load_recipe_file(path, label)
  local chunk, err = loadfile(path)
  if not chunk then
    error("spr: failed to load " .. label .. ": " .. tostring(err))
  end

  local ok, recipe = pcall(chunk)
  if not ok then
    error("spr: error running " .. label .. ": " .. tostring(recipe))
  end

  return recipe
end

local function resolve_from_monorepo(tier, name)
  sync_monorepo(tier)

  local recipe_path = SPR_CACHE_PATH .. "/" .. tier .. "/recipes/" .. name .. ".lua"
  if not path_exists(recipe_path) then
    return nil
  end

  local recipe = load_recipe_file(recipe_path, "'" .. name .. "' from " .. tier)
  recipe.source = recipe.source or {}
  recipe.source.tier = tier
  return recipe
end

local function resolve_from_open(name)
  local repo_url = "https://github.com/silkos-packages/" .. name .. ".git"
  local cache_dir = SPR_CACHE_PATH .. "/open/" .. name

  if path_exists(cache_dir) then
    shell.run("cd " .. cache_dir .. " && git pull --quiet")
  else
    local ok = shell.run("git clone --quiet " .. repo_url .. " " .. cache_dir)
    if not ok then
      return nil -- no such repo -- not found here, not a hard error
    end
  end

  local recipe_path = cache_dir .. "/recipe.lua"
  if not path_exists(recipe_path) then
    error("spr: open-tier repo for '" .. name .. "' has no recipe.lua")
  end

  local recipe = load_recipe_file(recipe_path, "open-tier recipe '" .. name .. "'")
  recipe.source = recipe.source or {}
  recipe.source.tier = "open"
  return recipe
end

local M = {}

local LOCAL_RECIPES_PATH = "/usr/lib/weave/recipes" -- same location native.lua's require() resolves against

function M.sync_info(tier)
  return sync_info[tier]
end

function M.search(query)
  local results = {}

  -- local recipes first, per the same "local always wins" precedent as resolve()
  local handle = io.popen("ls " .. LOCAL_RECIPES_PATH .. " 2>/dev/null")
  for filename in handle:lines() do
    local name = filename:match("^(.+)%.lua$")
    if name and name ~= "recipe" and name:find(query, 1, true) then
      results[#results + 1] = { name = name, tier = "local" }
    end
  end
  handle:close()

  for _, tier in ipairs(TIER_ORDER) do
    sync_monorepo(tier)

    local recipes_dir = SPR_CACHE_PATH .. "/" .. tier .. "/recipes"
    local tier_handle = io.popen("ls " .. recipes_dir .. " 2>/dev/null")

    for filename in tier_handle:lines() do
      local name = filename:match("^(.+)%.lua$")
      if name and name:find(query, 1, true) then
        results[#results + 1] = { name = name, tier = tier }
      end
    end
    tier_handle:close()
  end

  return results
end

function M.resolve(name)
  for _, tier in ipairs(TIER_ORDER) do
    local recipe = resolve_from_monorepo(tier, name)
    if recipe then
      return recipe
    end
  end

  local recipe = resolve_from_open(name)
  if recipe then
    return recipe
  end

  return nil, "package '" .. name .. "' not found in any SPR tier (official/community/open)"
end

return M
