-- loom/util/hash.lua
local M = {}

function M.shell_quote(str)
  return "'" .. str:gsub("'", "'\\''") .. "'"
end

function M.sha256(input_str)
  local handle = io.popen("printf '%s' " .. M.shell_quote(input_str) .. " | sha256sum")
  local output = handle:read("*a")
  handle:close()
  return output:match("^(%x+)")
end

function M.hash_file(path)
  local handle = io.popen("sha256sum " .. M.shell_quote(path))
  local output = handle:read("*a")
  handle:close()
  return output:match("^(%x+)")
end

return M
