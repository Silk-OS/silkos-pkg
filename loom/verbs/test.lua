-- loom/verbs/test.lua
local manifest = require("loom.manifest")
local resolver = require("weave.resolver")
local executor = require("weave.executor")

local M = {}

function M.run(args)
  local config = manifest.load()

  local ok, result = pcall(resolver.resolve_all, config.packages)
  if not ok then
    print("loom test: resolution failed: " .. tostring(result))
    os.exit(1)
  end

  local failures = {}

  for _, name in ipairs(result.order) do
    local recipe = result.recipes[name]

    print(("loom test: building %s %s..."):format(recipe.name, recipe.version or "?"))

    local ok2, build_err = pcall(executor.run, recipe, { yes = true })

    if ok2 then
      print(("loom test: %s OK"):format(recipe.name))
    else
      print(("loom test: %s FAILED: %s"):format(recipe.name, tostring(build_err)))
      failures[#failures + 1] = recipe.name
    end
  end

  if #failures > 0 then
    print(("loom test: %d package(s) failed: %s"):format(#failures, table.concat(failures, ", ")))
    os.exit(1)
  end

  print("loom test: all packages built successfully")
end

return M
