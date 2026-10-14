-- loom/verbs/thread.lua
local manifest = require("loom.manifest")
local resolver = require("weave.resolver")
local executor = require("weave.executor")
local staging = require("loom.state.staging")
local generations = require("loom.state.generations")
local hash = require("weave.util.hash")

local M = {}

function M.run(args)
  local config = manifest.load()

  local ok, result = pcall(resolver.resolve_all, config.packages)
  if not ok then
    print("loom thread: resolution failed: " .. tostring(result))
    os.exit(1)
  end

  local staged_entries = {}

  for _, name in ipairs(result.order) do
    local recipe = result.recipes[name]

    local input_hash, cached_destdir = staging.check_cache(recipe)

    if cached_destdir then
      print(("loom thread: %s %s — cached, skipping build"):format(recipe.name, recipe.version))
      staged_entries[#staged_entries + 1] = {
        recipe = recipe,
        input_hash = input_hash,
        destdir = cached_destdir,
        cached = true,
      }
    else
      print(("loom thread: %s %s — building..."):format(recipe.name, recipe.version))
      local ok2, result2 = pcall(executor.run, recipe, { yes = args.yes })

      if not ok2 then
        print(("loom thread: %s FAILED: %s"):format(recipe.name, tostring(result2)))
        os.exit(1)
      end

      staged_entries[#staged_entries + 1] = {
        recipe = recipe,
        input_hash = input_hash,
        destdir = result2.destdir,
        cached = false,
      }
    end
  end

  print("loom thread: staging generation...")
  local ok3, stage_result = pcall(staging.stage, staged_entries)
  if not ok3 then
    print("loom thread: staging failed: " .. tostring(stage_result))
    os.exit(1)
  end

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

  print(("loom thread: generation %d created and marked active. Reboot to apply."):format(next_gen_num))
end

return M
