-- loom/verbs/spin.lua
local manifest = require("loom.manifest")
local resolver = require("weave.resolver")
local executor = require("weave.executor")
local staging = require("loom.state.staging")
local reboot_checklist = require("loom.state.reboot_checklist")
local hash = require("weave.util.hash")

local CURRENT_LINK = "/silk/ostree/deployments/current"

local function atomic_symlink(target, link_path)
  local tmp_link = link_path .. ".tmp"
  os.execute("ln -sfn " .. hash.shell_quote(target) .. " " .. hash.shell_quote(tmp_link))
  local ok, err = os.rename(tmp_link, link_path)
  if not ok then
    error("spin: atomic symlink swap failed: " .. tostring(err))
  end
end

local M = {}

function M.run(args)
  local config = manifest.load()

  local ok, result = pcall(resolver.resolve_all, config.packages)
  if not ok then
    print("loom spin: resolution failed: " .. tostring(result))
    os.exit(1)
  end

  local recipes_list = {}
  for _, name in ipairs(result.order) do
    recipes_list[#recipes_list + 1] = result.recipes[name]
  end

  local requires_reboot, reason = reboot_checklist.check(recipes_list, config.system.init)
  if requires_reboot then
    print("loom spin: cannot live-preview this generation — " .. reason)
    print("loom spin: use 'loom thread' or 'loom bind' instead, then reboot.")
    os.exit(1)
  end

  local staged_entries = {}

  for _, name in ipairs(result.order) do
    local recipe = result.recipes[name]

    local input_hash, cached_destdir = staging.check_cache(recipe)

    if cached_destdir then
      print(("loom spin: %s %s — cached, skipping build"):format(recipe.name, recipe.version))
      staged_entries[#staged_entries + 1] = {
        recipe = recipe, input_hash = input_hash, destdir = cached_destdir, cached = true,
      }
    else
      print(("loom spin: %s %s — building..."):format(recipe.name, recipe.version))
      local ok2, result2 = pcall(executor.run, recipe, { yes = args.yes })
      if not ok2 then
        print(("loom spin: %s FAILED: %s"):format(recipe.name, tostring(result2)))
        os.exit(1)
      end
      staged_entries[#staged_entries + 1] = {
        recipe = recipe, input_hash = input_hash, destdir = result2.destdir, cached = false,
      }
    end
  end

  print("loom spin: staging preview...")
  local ok3, stage_result = pcall(staging.stage, staged_entries)
  if not ok3 then
    print("loom spin: staging failed: " .. tostring(stage_result))
    os.exit(1)
  end

  local deployment_dir = staging.checkout(stage_result.ostree_commit, "spin")
  staging.validate_symlinks(deployment_dir)

  atomic_symlink(deployment_dir, CURRENT_LINK)

  print("loom spin: live preview active. This is TEMPORARY — reboot to revert to the last real generation.")
end

return M
