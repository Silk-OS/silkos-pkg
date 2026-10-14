-- loom/verbs/search.lua
local spr = require("weave.sources.spr")

local M = {}

function M.run(args)
  local query = args[1]
  if not query then
    print("loom search: usage: loom search <query>")
    os.exit(1)
  end

  local results = spr.search(query)

  if #results == 0 then
    print("loom search: no packages found matching '" .. query .. "'")
    return
  end

  for _, entry in ipairs(results) do
    print(("  %-30s [%s]"):format(entry.name, entry.tier))
  end
end

return M
