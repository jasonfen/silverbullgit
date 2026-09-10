Local git snapshots of this space, driven from SilverBullet.

Adapted from [the upstream Space Lua Git library](https://github.com/silverbulletmd/silverbullet-libraries/blob/main/Git.md),
with two deliberate changes:

1. **Commit only, no `pull`/`push`.** This assumes no remote, so the upstream
   `git.sync()` would fail on every cycle.
2. **Exit codes are checked instead of `pcall`.** `shell.run` returns
   `{stdout, stderr, code}` and does *not* raise on a non-zero exit, so the
   upstream `pcall` never actually caught a failing git.

${widgets.commandButton("Git: Commit now")}

# Configuration
`git.autoCommitMinutes`: snapshot every _x_ minutes. Set in [[CONFIG]].

> **Snapshots only run while a SilverBullet client is open.** `cron:secondPassed`
> fires in the browser, so edits made by agents or shell scripts while no tab is
> open are captured at the next snapshot after one opens, not when they happen.
> See the `silverbullgit` README for the host-side timer that covers this gap.

```space-lua
-- priority: 100
config.define("git", {
  type = "object",
  properties = {
    autoCommitMinutes = schema.number()
  }
})
```

```space-lua
git = {}

-- Absolute, because this assumes SB_FOLDER is pinned to /space. Adjust if
-- your deployment mounts the space somewhere else.
local SPACE = "/space"

local function run(...)
  return shell.run("git", {"-C", SPACE, ...})
end

-- Commit the whole space. Returns true only if a commit was actually created.
function git.commit(message)
  local status = run("status", "--porcelain")
  if status.code ~= 0 then
    print("git status failed: " .. status.stderr)
    return false
  end
  if status.stdout == "" then
    return false -- nothing changed; stay quiet
  end

  message = message or ("SilverBullet snapshot " .. os.date("%Y-%m-%d %H:%M:%S"))

  local added = run("add", "-A")
  if added.code ~= 0 then
    print("git add failed: " .. added.stderr)
    return false
  end

  local committed = run("commit", "-m", message)
  if committed.code ~= 0 then
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
