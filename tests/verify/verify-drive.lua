-- tests/verify/verify-drive.lua
-- Thin driver for weave/util/verify.lua, used by verify-test.sh.
-- usage: lua verify-drive.lua <dir> <url> <trusted_signers_file>
local v = require("weave.util.verify")
local ok, a, b = pcall(v.sync_signed_repo, { dir = arg[1], url = arg[2], trusted_signers = arg[3] })
if not ok then
  print("RESULT: error: " .. tostring(a))
elseif type(b) == "table" then
  local names = {}
  for _, s in ipairs(b.skipped or {}) do names[#names + 1] = s.tag end
  print(string.format("RESULT: %s tag=%s commit=%s changed=%s skipped=%d[%s]",
    a, b.tag, b.commit:sub(1, 8), tostring(b.changed), #names, table.concat(names, ",")))
else
  print("RESULT: " .. a .. ": " .. tostring(b))
end
