-- loom/verbs/bind.lua
local manifest = require("loom.manifest")
local resolver = require("weave.resolver")
local executor = require("weave.executor")
local staging = require("loom.state.staging")
local generations = require("loom.state.generations")
local reboot_checklist = require("loom.state.reboot_checklist")
local hash = require("weave.util.hash")

local CURRENT_LINK = "/silk/ostree/deployments/current"

local function atomic_symlink(target, link_path)
  local tmp_link = link_path .. ".tmp"
  os.execute("ln -sfn " .. hash.shell_quote(target) .. " " .. hash.shell_quote(tmp_link))
  local ok, err = os.rename(tmp_link, link_path)
  if not ok then
    error("bind: atomic symlink swap failed: " .. tostring(err))
  end
end

local M = {}

function M.run(args)
  local config = manifest.load()

  local ok, result = pcall(resolver.resolve_all, config.packages)
  if not ok then
    print("loom bind: resolution failed: " .. tostring(result))
    os.exit(1)
  end

  local recipes_list = {}
  for _, name in ipairs(result.order) do
    recipes_list[#recipes_list + 1] = result.recipes[name]
  end

  local staged_entries = {}

  for _, name in ipairs(result.order) do
    local recipe = result.recipes[name]

    local input_hash, cached_destdir = staging.check_cache(recipe)

    if cached_destdir then
      print(("loom bind: %s %s — cached, skipping build"):format(recipe.name, recipe.version))
      staged_entries[#staged_entries + 1] = {
        recipe = recipe, input_hash = input_hash, destdir = cached_destdir, cached = true,
      }
    else
      print(("loom bind: %s %s — building..."):format(recipe.name, recipe.version))
      local ok2, result2 = pcall(executor.run, recipe, { yes = args.yes })
      if not ok2 then
        print(("loom bind: %s FAILED: %s"):format(recipe.name, tostring(result2)))
        os.exit(1)
      end
      staged_entries[#staged_entries + 1] = {
        recipe = recipe, input_hash = input_hash, destdir = result2.destdir, cached = false,
      }
    end
  end

  print("loom bind: staging generation...")
  local ok3, stage_result = pcall(staging.stage, staged_entries)
  if not ok3 then
    print("loom bind: staging failed: " .. tostring(stage_result))
    os.exit(1)
  end

  local requires_reboot, reason = reboot_checklist.check(recipes_list, config.system.init)

  local next_gen_num = generations.next_number()

  generations.add({
    generation = next_gen_num,
    ostree_commit = stage_result.ostree_commit,
    fabric_hash = hash.hash_file("/etc/silk/fabric.lua"),
    init = config.system.init,
    created = os.time(),
    status = "stale",
  })

  generations.set_active(next_gen_num)

  if requires_reboot then
    print("loom bind: REBOOT REQUIRED — " .. reason)
    print(("loom bind: generation %d created. Reboot to apply."):format(next_gen_num))
  else
    print("loom bind: swapping live...")

    local deployment_dir = staging.checkout(stage_result.ostree_commit, next_gen_num)
    staging.validate_symlinks(deployment_dir)

    atomic_symlink(deployment_dir, CURRENT_LINK)

    print(("loom bind: generation %d created and live."):format(next_gen_num))
  end
end

return M
