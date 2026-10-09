-- weave/util/shell.lua
-- Small shared helper for running shell commands from source modules and the executor.
-- Runs `cmd`, returns (ok, output). output is stdout+stderr combined with trailing whitespace trimmed. ok is false if the command's exit code was non-zero.
local function run(cmd)
  local handle = io.popen(cmd .. " 2>&1; echo EXIT:$?")
  local output = handle:read("*a")
  handle:close()

  local exit_code = output:match("EXIT:(%d+)%s*$")
  output = output:gsub("EXIT:%d+%s*$", ""):gsub("%s+$", "")

  return exit_code == "0", output
end

local M = {}
M.run = run
return M
