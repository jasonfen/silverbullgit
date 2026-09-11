# silverbullgit

Git-backed version history for a [SilverBullet](https://silverbullet.md) 2.10
space. Two commit engines plus per-page browsing, all Space Lua and one shell
script, no plugs.

- **`LIBRARY.md`**: the SilverBullet library, installed to
  `Library/jasonfen/SilverbullGit`. Commits the whole space on a timer while a
  browser tab is open, exposes `Git: Commit now` / `Git: Commit with message`,
  and renders version history as read-only virtual pages.
- **`vault-snapshot.sh`**: a host-side script, run from a systemd timer, that
  commits the space on a fixed interval regardless of whether a tab is open.
- **`REPO.md`**: a library repository page, so the library can be found and
  updated through `Library: Add Repository`. History is read straight out of
  git: `history:<page>` for a version list, `history:<page>/<hash>` for that
  commit.

## This is temporary

SilverBullet is building git-backed revision history into core. It has not
shipped yet.

- [`docs/Features/Revisions.md`](https://github.com/silverbulletmd/silverbullet/blob/main/docs/Features/Revisions.md)
  exists on `main`.
- [`server/src/revisions/`](https://github.com/silverbulletmd/silverbullet/tree/main/server/src/revisions)
  exists on `main`.
- Both paths 404 at the [`2.10.0` tag](https://github.com/silverbulletmd/silverbullet/tree/2.10.0/docs/Features),
  the newest release as of this writing. The feature is unreleased.

The native version has three modes (Managed, Unmanaged, Disabled) and is
maintained server-side, so it will not have the open-tab limitation described
below. When it ships, switch to it. Its Unmanaged mode reads an existing git
repo without committing to it, which is exactly the shape a space using this
project already has: point Unmanaged at the repo `vault-snapshot.sh` has been
committing to, and it picks up the same history. At that point, delete
the library and stop the systemd timer, or keep the timer as
your committer under Unmanaged if you prefer a host-side cadence to the
server's own.

Re-read the actual feature docs before migrating. This README was written
against `main` before release; details may have changed by the time it ships.

## Install (SilverBullet 2.10)

### 1. Make the space a git repository

The library commits into an existing repo. It does not create one.

```bash
cd /path/to/your/space
git init
git config user.name "Your Name"
git config user.email "you@example.com"
```

### 2. Install the library

Two options. Both install to `Library/jasonfen/SilverbullGit`.

**Via Library Manager** (preferred). Run `Library: Install` and give it:

```
https://github.com/jasonfen/silverbullgit/blob/master/LIBRARY.md
```

To get updates and see other libraries from the same author, run
`Library: Add Repository` with:

```
https://github.com/jasonfen/silverbullgit/blob/master/REPO.md
```

**By hand.** Copy `LIBRARY.md` into your space as
`Library/jasonfen/SilverbullGit.md`. The path must match the `name` key in the
file's frontmatter.

### 3. Set the snapshot interval

Add to `CONFIG`:

```lua
config.set("git.autoCommitMinutes", 5)
```

Leave it unset to disable automatic snapshots and keep only the commands and
history browsing. Do that if you commit by other means.

### 4. Install the host timer

Automatic snapshots only run while a browser tab is open, because
`cron:secondPassed` is a client-side event. This timer covers the rest.

```bash
sudo install -m 755 vault-snapshot.sh /usr/local/bin/silverbullgit-snapshot
sudo cp systemd/silverbullgit.service systemd/silverbullgit.timer /etc/systemd/system/
sudoedit /etc/systemd/system/silverbullgit.service   # set User, Group and SPACE_DIR
sudo systemctl daemon-reload
sudo systemctl enable --now silverbullgit.timer
systemctl list-timers silverbullgit.timer
```

The script takes the space path as `$1` or via `SPACE_DIR`. It exits silently on
a clean tree and treats a lost `index.lock` as expected, since the Space Lua
engine may be committing at the same time.

### 5. Use it

* `Git: Commit now` and `Git: Commit with message` commit on demand.
* `history:<page>` lists every commit that touched a page.
* `history:<page>/<hash>` renders the page as it stood at that commit.

## The Docker uid gotcha

If SilverBullet runs as root inside its container while the space directory on
the host is owned by another user, commits made through the Space Lua engine
create root-owned objects inside `.git`. The space owner cannot delete them
without root access.

`PUID`/`PGID` are documented at the `2.10.0` tag but are not honoured by that
release: containers set with and without those variables both ran as root.
The fix is a Docker-level `user:` override matching the space owner's uid/gid.

```yaml
services:
  silverbullet:
    image: ghcr.io/silverbulletmd/silverbullet:2.10.0
    user: "1000:1000"  # match the uid:gid that owns the space directory
    volumes:
      - /path/to/your/space:/space
    ports:
      - "3000:3000"
```

## The .gitignore gotcha

SilverBullet filters its space file listing through `.gitignore`, and that
listing governs both page visibility and plug loading. Ignoring a file in git
hides it from SilverBullet too, not only from the repo.

`SB_SPACE_IGNORE` is a separate, `.gitignore`-style environment variable that
hides a path from SilverBullet without ignoring it in git. There is no
equivalent in the other direction: a path kept visible to SilverBullet cannot
be excluded from git while still loading. If you want a plug or page loaded,
it has to be tracked.

## Known limitations

- **`cron:secondPassed` is a client-side event.** The Space Lua engine only
  commits while a SilverBullet tab is open in a browser. This is
  why `vault-snapshot.sh` and its timer exist: they are the only engine that
  runs with no tab open.
- **Both engines can race for `index.lock`.** Multiple open tabs, or the timer
  firing while a tab is mid-commit, can collide on git's lock file. Both
  the library and `vault-snapshot.sh` treat a lost `index.lock` as expected and
  stay silent about it; the next commit cycle picks up the change.
- **Timestamps come from two different clocks.** The Space Lua engine builds
  its commit message client-side, so the message text uses the browser's
  local time. Git's own commit metadata (author/committer date) is recorded by
  the container, using the container's timezone. Timer commits are
  self-consistent, since both the message and the metadata come from the host.

## Credit

Adapted from
[the upstream Space Lua Git library](https://github.com/silverbulletmd/silverbullet-libraries/blob/main/Git.md).
Three changes from upstream:

1. **No `pull`/`push`.** This project assumes a local-only repo with no
   remote, so upstream's `git.sync()` step is removed; it would fail on every
   cycle without one.
2. **Exit codes instead of `pcall`.** `shell.run` returns
   `{stdout, stderr, code}` and does not raise on a non-zero exit
   ([`plug-api/syscalls/shell.ts`](https://github.com/silverbulletmd/silverbullet/blob/main/plug-api/syscalls/shell.ts)),
   so upstream's `pcall` around it never actually caught a failing git. This
   version checks `.code` directly.
3. **Tolerates a lost `index.lock`.** Concurrent commits from multiple tabs
   (or the tab and the host timer) can collide on git's lock file. That
   failure is treated as expected and does not surface as an error.
