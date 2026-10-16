-- weave/util/verify.lua
-- Syncs a git repo, but only ever moves it to a tag signed by a trusted key.
local shell = require("weave.util.shell")
local hash = require("weave.util.hash")

local q = hash.shell_quote
local M = {}

local function git(dir, args, signers)
  local cmd = "GIT_TERMINAL_PROMPT=0 git -C " .. q(dir)
  if signers then
    cmd = cmd .. " -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=" .. q(signers)
  end
  return shell.run(cmd .. " " .. args)
end

-- newest first; only names matching a strict allow-list are returned
local function list_tags(dir)
  local ok, out = git(dir, "for-each-ref --sort=-creatordate --format='%(refname:lstrip=2)' refs/tags")
  local tags = {}
  if not ok then return tags end
  for name in out:gmatch("[^\n]+") do
    if name:match("^%w[%w%._%-]*$") then
      tags[#tags + 1] = name
    end
  end
  return tags
end

-- Returns "ok", {tag=, commit=, changed=, skipped=}  or  "unavailable", reason.
-- skipped lists the newer tags that were rejected, newest first, as
-- { tag = "v4", reason = "..." } entries, so callers can tell the user that
-- newer releases exist but could not be verified.
-- Raises an error on anything that looks like tampering.
function M.sync_signed_repo(opts)
  local dir, url, signers = opts.dir, opts.url, opts.trusted_signers

  local f = io.open(signers, "r")
  if not f then
    return "unavailable", "trusted signers file missing: " .. signers
  end
  f:close()

  -- never clone/checkout before verifying: start from an empty repo and fetch
  if not shell.run("test -d " .. q(dir .. "/.git")) then
    local ok, out = shell.run("mkdir -p " .. q(dir) .. " && git init -q " .. q(dir))
    if not ok then error("verify: git init failed: " .. out) end
    git(dir, "remote add origin " .. q(url))
  end

  local fetched, fetch_out = git(dir, "fetch --quiet --tags origin")
  if not fetched then
    return "unavailable", fetch_out
  end

  local tags = list_tags(dir)
  if #tags == 0 then
    return "unavailable", "no tags published yet"
  end

  local has_held, held = git(dir, "rev-parse -q --verify " .. q("HEAD^{commit}"))
  local skipped = {}

  for _, name in ipairs(tags) do
    local _, tag_id = git(dir, "rev-parse -q --verify " .. q("refs/tags/" .. name))

    local verified, vout = false, ""
    if tag_id:match("^%x+$") then
      -- verify the tag OBJECT by id, so the ref can't be swapped underneath us
      verified, vout = git(dir, "verify-tag " .. q(tag_id), signers)
    end

    if verified and not vout:find("No principal matched", 1, true) then
      local _, commit = git(dir, "rev-parse -q --verify " .. q(tag_id .. "^{commit}"))
      if not commit:match("^%x+$") then
        error("verify: could not resolve a commit for tag " .. name)
      end

      if has_held and held == commit then
        return "ok", { tag = name, commit = commit, changed = false, skipped = skipped }
      end

      local descends = (not has_held)
          or git(dir, "merge-base --is-ancestor " .. q(held) .. " " .. q(commit))

      if descends then
        local ok, out = git(dir, "checkout -q --detach " .. q(commit))
        if not ok then error("verify: checkout failed: " .. out) end
        return "ok", { tag = name, commit = commit, changed = true, skipped = skipped }
      end

      skipped[#skipped + 1] = {
        tag = name,
        reason = "validly signed but does not descend from the commit already held",
      }
      io.stderr:write("verify: REFUSING tag '" .. name .. "': validly signed but does not descend from "
        .. "the commit already held (possible rollback or rewritten history). Keeping the current "
        .. "checkout. If this rewrite is legitimate, delete " .. dir .. " and re-sync.\n")
    else
      skipped[#skipped + 1] = { tag = name, reason = "no valid signature from a trusted key" }
      io.stderr:write("verify: skipping tag '" .. name .. "' (no valid signature from a trusted key)\n")
    end
  end

  error("verify: no usable tag at " .. url .. " (" .. #tags
    .. " found, none both validly signed and descended from the held commit)")
end

return M
