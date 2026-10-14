-- loom/init.lua
local M = {}

local verbs = {
  bind    = require("loom.verbs.bind"),
  thread  = require("loom.verbs.thread"),
  spin    = require("loom.verbs.spin"),
  test    = require("loom.verbs.test"),
  unravel = require("loom.verbs.unravel"),
  set     = require("loom.verbs.set"),
  search  = require("loom.verbs.search")
}

function M.run(argv)
  local verb_name = argv[1]

  if not verb_name then
    print("Usage: loom <bind|thread|spin|test|unravel|set> [args...]")
    os.exit(1)
  end

  local handler = verbs[verb_name]
  if not handler then
    print(("loom: unknown verb '%s'"):format(verb_name))
    os.exit(1)
  end

  local rest = {}
  for i = 2, #argv do
    rest[#rest + 1] = argv[i]
  end

  handler.run(rest)
end

return M
