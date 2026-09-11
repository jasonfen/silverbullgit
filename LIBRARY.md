---
name: Library/jasonfen/SilverbullGit
tags: meta/library
---
Git-backed version history for a SilverBullet space, in Space Lua. Snapshots the
space on a timer and adds per-page version browsing.

This is a stopgap. SilverBullet is bringing git-backed revision history into
core, maintained server-side. See the
[README](https://github.com/jasonfen/silverbullgit) for the evidence and for the
host-side timer that covers what this library cannot.

${widgets.commandButton("Git: Commit now")}

# Setup
The space folder must already be a git repository with `user.name` and
`user.email` set. Then add to `CONFIG`:

```lua
config.set("git.autoCommitMinutes", 5)
```

Leave `git.autoCommitMinutes` unset to disable automatic snapshots and keep only
the commands and history browsing. Do that if you commit by other means, such as
the host timer or your own cron job.

# Configuration
* `git.autoCommitMinutes`: snapshot every _x_ minutes. Unset disables it.
* `git.spacePath`: optional. `shell.run` executes with the space folder as its
  working directory, so this is normally unnecessary. Set it only if your
  deployment needs an explicit path.

# Browsing history
* `history:<page>` lists every commit that touched a page.
* `history:<page>/<hash>` renders the page as it stood at that commit.

Both are read-only virtual pages. Nothing is written to your space.

# Limitation
`cron:secondPassed` fires in the browser, so automatic snapshots only run while a
SilverBullet tab is open. Edits made by scripts while no tab is open are captured
at the next snapshot after one opens. The README covers a systemd timer that
closes this gap.

```space-lua
-- priority: 100
config.define("git", {
  type = "object",
  properties = {
    autoCommitMinutes = schema.number(),
    spacePath = schema.string()
  }
})
```

```space-lua
-- priority: 50
git = {}

-- shell.run executes with the space folder as its working directory, so plain
-- git calls already resolve against the space. git.spacePath is an escape hatch
-- for deployments where that does not hold.
function git.run(...)
  local spacePath = config.get("git.spacePath")
  if spacePath then
    return shell.run("git", {"-C", spacePath, ...})
  end
  return shell.run("git", {...})
end

-- Commit the whole space. Returns true only if a commit was actually created.
function git.commit(message)
  local status = git.run("status", "--porcelain")
  if status.code != 0 then
    print("git status failed: " .. status.stderr)
    return false
  end
  if status.stdout == "" then
    return false -- nothing changed; stay quiet
  end

  message = message or ("SilverBullet snapshot " .. os.date("%Y-%m-%d %H:%M:%S"))

  local added = git.run("add", "-A")
  if added.code != 0 then
    print("git add failed: " .. added.stderr)
    return false
  end

  local committed = git.run("commit", "-m", message)
  if committed.code != 0 then
    -- Several clients can fire the timer at once; losing the index lock is
    -- expected and harmless, so it is not worth surfacing.
    if not string.find(committed.stderr, "index.lock", 1, true) then
      print("git commit failed: " .. committed.stderr)
    end
    return false
  end
  return true
end

command.define {
  name = "Git: Commit now",
  run = function()
    if git.commit() then
      editor.flashNotification "Snapshot committed"
    else
      editor.flashNotification "Nothing to commit"
    end
  end
}

command.define {
  name = "Git: Commit with message",
  run = function()
    local message = editor.prompt "Commit message:"
    if message and git.commit(message) then
      editor.flashNotification "Committed"
    end
  end
}
```

```space-lua
-- priority: 10

-- Every commit that touched a page, newest first.
local function versionsOf(page)
  local r = git.run("log", "--format=%h %ct %s", "--", page .. ".md")
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
  local r = git.run("show", hash .. ":" .. page .. ".md")
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
```

```space-lua
-- priority: -1
local minutes = config.get("git.autoCommitMinutes")
if minutes then
  -- Zero means "snapshot as soon as a client connects", which is what we want:
  -- opening the space captures whatever wrote to it while nothing was watching.
  local lastCommit = 0
  event.listen {
    name = "cron:secondPassed",
    run = function()
      local now = os.time()
      if (now - lastCommit) / 60 >= minutes then
        lastCommit = now
        git.commit()
      end
    end
  }
end
```
