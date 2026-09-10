Per-page version history, read straight out of git.

Replaces [`ivanalejandro0/silverbullet-history`](https://github.com/ivanalejandro0/silverbullet-history),
which cannot work on SilverBullet 2.x: it renders its version pages through the
`pageNamespace` plug hook, and 2.x replaced that with
[[^Library/Std/APIs/Virtual Page]]. Its `readFile` handler was never called, so
every version page came out blank. Upstream has been dormant since 2025-05-02
and the Deno `plug:compile` toolchain no longer ships with the Rust server, so
there was nothing to patch or rebuild against.

${widgets.commandButton("History: view page history")}

Navigate to `history:<page>` for the list of versions, or
`history:<page>/<hash>` for the page as it stood at that commit. Both are
read-only virtual pages: nothing is written to the space.

```space-lua
-- priority: 10
local SPACE = "/space"

local function git(...)
  return shell.run("git", {"-C", SPACE, ...})
end

-- Every commit that touched a page, newest first.
local function versionsOf(page)
  local r = git("log", "--format=%h %ct %s", "--", page .. ".md")
  if r.code != 0 then
    return nil, r.stderr
  end
  local versions = {}
  for line in r.stdout:gmatch("[^\n]+") do
    local hash, ts, subject = line:match("^(%S+) (%d+) (.*)$")
    if hash then
      table.insert(versions, {hash = hash, ts = tonumber(ts), subject = subject})
    end
  end
  return versions
end

local function renderIndex(page)
  local versions, err = versionsOf(page)
  if versions == nil then
    return "# History unavailable\n\n```\n" .. (err or "unknown error") .. "\n```"
  end
  local out = {"# History of [[" .. page .. "]]", ""}
  if #versions == 0 then
    table.insert(out,
      "No committed versions: this page is not tracked in git yet. A snapshot "
      .. "lands within a few minutes while a tab is open, or on the next host "
      .. "timer run. See the silverbullgit README for details.")
  else
    for _, v in ipairs(versions) do
      table.insert(out, string.format("- [[history:%s/%s|%s]] · %s",
        page, v.hash, os.date("%Y-%m-%d %H:%M", v.ts), v.subject))
    end
  end
  return table.concat(out, "\n")
end

local function renderVersion(page, hash)
  local r = git("show", hash .. ":" .. page .. ".md")
  if r.code != 0 then
    return "# Not in this version\n\n`" .. page .. ".md` does not exist at `"
      .. hash .. "`.\n\n```\n" .. r.stderr .. "\n```"
  end
  return table.concat({
    "> `" .. hash .. "` of [[" .. page .. "]] · [[history:" .. page .. "|all versions]]",
    "", "---", "",
    r.stdout,
  }, "\n")
end

virtualPage.define {
  pattern = "history:(.+)",
  run = function(rest)
    -- A trailing short hash means "show that version"; anything else is a page
    -- name and gets the version list.
    local page, hash = rest:match("^(.+)/(%x%x%x%x%x%x%x+)$")
    if page != nil then
      return renderVersion(page, hash)
    end
    return renderIndex(rest)
  end
}

command.define {
  name = "History: view page history",
  run = function()
    editor.navigate("history:" .. editor.getCurrentPage())
  end
}
```
