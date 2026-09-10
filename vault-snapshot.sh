#!/usr/bin/env bash
# Host-side backstop for the SilverBullet Space Lua snapshot engine (see Git.md).
#
# The Lua engine listens on cron:secondPassed, which is a *client-side* event, so
# it only commits while a browser tab is open. Anything written to the space
# while no tab is open (by a script, an agent, or a sync process) sits
# uncommitted until someone opens the space. This timer closes that gap.
#
# Deliberately the same shape as git.commit() in Git.md: commit only, no remote.
set -uo pipefail

SPACE_DIR="${1:-${SPACE_DIR:-}}"

if [ -z "$SPACE_DIR" ]; then
  echo "vault-snapshot: set SPACE_DIR or pass the space path as \$1" >&2
  exit 1
fi

cd "$SPACE_DIR" || exit 1

# Clean tree: nothing to do, and nothing worth logging.
[ -n "$(git status --porcelain)" ] || exit 0

git add -A || exit 0

# The Lua engine can be mid-commit in an open tab. Losing the index lock is
# expected, not an error: the next tick picks the changes up.
if ! err=$(git commit -m "Space snapshot (timer) $(date '+%Y-%m-%d %H:%M:%S')" 2>&1); then
  case "$err" in
    *index.lock*|*"nothing to commit"*) exit 0 ;;
    *) echo "vault-snapshot: $err" >&2; exit 1 ;;
  esac
fi
