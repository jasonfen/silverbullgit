# silverbullgit

Git-backed version history for a [SilverBullet](https://silverbullet.md) 2.10
space. Two commit engines plus per-page browsing, all Space Lua and one shell
script, no plugs.

- **`Git.md`**: a Space Lua page that commits the whole space on a timer while
  a browser tab is open, and exposes `Git: Commit now` / `Git: Commit with
  message` commands.
- **`vault-snapshot.sh`**: a host-side script, run from a systemd timer, that
  commits the space on a fixed interval regardless of whether a tab is open.
- **`History.md`**: a Space Lua page that reads commit history straight out
  of git and renders it as read-only virtual pages: `history:<page>` for a
  version list, `history:<page>/<hash>` for the page as it stood at that
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
`Git.md` and `History.md` and stop the systemd timer, or keep the timer as
your committer under Unmanaged if you prefer a host-side cadence to the
server's own.

Re-read the actual feature docs before migrating. This README was written
against `main` before release; details may have changed by the time it ships.

## Install (SilverBullet 2.10)

1. Initialize git in the space folder if it is not already a repo, and set a
   repo-local identity:

   ```bash
   cd /path/to/your/space
   git init
   git config user.name "Your Name"
   git config user.email "you@example.com"
   ```

2. Copy `Git.md` and `History.md` into the space root:

   ```bash
   cp Git.md History.md /path/to/your/space/
   ```

3. Add the auto-commit interval to `CONFIG.md` in the space:

   ```space-lua
   config.set("git.autoCommitMinutes", 5)
   ```

4. Install the systemd timer for unattended commits (covers the time no
   browser tab is open):

   ```bash
   sudo cp systemd/silverbullgit.service /etc/systemd/system/
   sudo cp systemd/silverbullgit.timer /etc/systemd/system/
   sudo cp vault-snapshot.sh /path/to/silverbullgit/vault-snapshot.sh
   sudo chmod +x /path/to/silverbullgit/vault-snapshot.sh
   ```

   Edit `silverbullgit.service`: set `User`, `Group`, `WorkingDirectory`, the
   `SPACE_DIR` environment variable, and `ExecStart` to point at your copy of
   `vault-snapshot.sh`. `User`/`Group` must match the uid/gid that owns the
   space directory (see the Docker uid section below).

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now silverbullgit.timer
   ```

`vault-snapshot.sh` also accepts the space path as its first argument instead
of `SPACE_DIR`, for running it by hand: `./vault-snapshot.sh /path/to/space`.

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

- **`cron:secondPassed` is a client-side event.** The Space Lua engine in
  `Git.md` only commits while a SilverBullet tab is open in a browser. This is
  why `vault-snapshot.sh` and its timer exist: they are the only engine that
  runs with no tab open.
- **Both engines can race for `index.lock`.** Multiple open tabs, or the timer
  firing while a tab is mid-commit, can collide on git's lock file. Both
  `Git.md` and `vault-snapshot.sh` treat a lost `index.lock` as expected and
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
