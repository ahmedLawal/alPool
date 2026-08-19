#!/usr/bin/env bash
# Sync the personal alPool main branch with upstream from this Mac.
#
# The merge and validation happen in a disposable worktree. The live checkout is
# never modified by this script; it only receives the result later through
# alPool's normal clean-main, fast-forward-only updater.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${ALPOOL_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BRANCH="${ALPOOL_SYNC_BRANCH:-main}"
UPSTREAM_URL="${ALPOOL_UPSTREAM_URL:-https://github.com/2solarmax/maxpool.git}"
DRY_RUN="${ALPOOL_SYNC_DRY_RUN:-0}"
LOCK_DIR="${TMPDIR:-/tmp}/alpool-upstream-sync-${UID}.lock"
WORKTREE=""
WORKTREE_ADDED=0
STATUS_WRITER="$SCRIPT_DIR/record-upstream-sync-status.mjs"
STATUS_STATE="checking"
STATUS_PHASE="initialize"
INSTALLED_VERSION=""
INSTALLED_REVISION=""
AVAILABLE_VERSION=""
AVAILABLE_REVISION=""

log() {
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

record_status() {
  ALPOOL_STATUS_STATE="$STATUS_STATE" \
  ALPOOL_STATUS_PHASE="$STATUS_PHASE" \
  ALPOOL_STATUS_INSTALLED_VERSION="$INSTALLED_VERSION" \
  ALPOOL_STATUS_INSTALLED_REVISION="$INSTALLED_REVISION" \
  ALPOOL_STATUS_AVAILABLE_VERSION="$AVAILABLE_VERSION" \
  ALPOOL_STATUS_AVAILABLE_REVISION="$AVAILABLE_REVISION" \
    node "$STATUS_WRITER"
}

cleanup() {
  if [[ "$WORKTREE_ADDED" == "1" && -n "$WORKTREE" ]]; then
    git -C "$REPO_ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
  if [[ -d "$LOCK_DIR" ]]; then
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
  fi
}

finish() {
  local code="$?"
  trap - EXIT
  set +e
  if [[ "$code" != "0" ]]; then
    STATUS_STATE="failed"
    record_status
  fi
  cleanup
  exit "$code"
}
trap finish EXIT
trap 'exit 130' INT TERM

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    return
  fi

  local holder=""
  holder="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ "$holder" =~ ^[0-9]+$ ]] && kill -0 "$holder" 2>/dev/null; then
    log "Another upstream sync is already running (pid $holder); skipping."
    exit 0
  fi

  rm -f "$LOCK_DIR/pid"
  rmdir "$LOCK_DIR" 2>/dev/null || {
    log "Could not clear stale lock $LOCK_DIR"
    exit 1
  }
  mkdir "$LOCK_DIR"
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
}

configure_node_path() {
  if command -v npm >/dev/null 2>&1; then
    return
  fi

  local candidate=""
  local selected=""
  for candidate in "$HOME"/.nvm/versions/node/*/bin/npm; do
    [[ -x "$candidate" ]] && selected="$candidate"
  done
  if [[ -z "$selected" ]]; then
    log "npm was not found. Install Node.js 20.3+ or set PATH for the LaunchAgent."
    exit 1
  fi
  export PATH="$(dirname "$selected"):$PATH"
}

run_in_worktree() {
  local label="$1"
  shift
  local output="$WORKTREE/.alpool-sync-${label// /-}.log"
  log "$label"
  if (cd "$WORKTREE" && "$@") > "$output" 2>&1; then
    log "$label passed"
    return
  fi
  log "$label failed; showing the last 200 lines"
  tail -n 200 "$output" || true
  exit 1
}

read_package_version() {
  local revision="$1"
  git -C "$REPO_ROOT" show "$revision:package.json" 2>/dev/null \
    | node -e 'let input=""; process.stdin.on("data", chunk => input += chunk); process.stdin.on("end", () => { try { process.stdout.write(JSON.parse(input).version || ""); } catch {} });'
}

acquire_lock
configure_node_path
record_status

if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  log "Not a Git repository: $REPO_ROOT"
  exit 1
fi
if ! git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
  log "The alPool checkout has no origin remote."
  exit 1
fi
if ! git -C "$REPO_ROOT" remote get-url upstream >/dev/null 2>&1; then
  git -C "$REPO_ROOT" remote add upstream "$UPSTREAM_URL"
fi

STATUS_PHASE="fetch"
record_status
log "Fetching origin/$BRANCH and upstream/$BRANCH"
git -C "$REPO_ROOT" fetch --no-tags --prune origin "$BRANCH"
git -C "$REPO_ROOT" fetch --no-tags --prune upstream "$BRANCH"

AVAILABLE_REVISION="$(git -C "$REPO_ROOT" rev-parse "upstream/$BRANCH")"
AVAILABLE_VERSION="$(read_package_version "upstream/$BRANCH")"

if git -C "$REPO_ROOT" merge-base --is-ancestor "upstream/$BRANCH" "origin/$BRANCH"; then
  INSTALLED_REVISION="$AVAILABLE_REVISION"
  INSTALLED_VERSION="$AVAILABLE_VERSION"
  STATUS_STATE="up-to-date"
  STATUS_PHASE="complete"
  record_status
  log "Personal $BRANCH already contains the latest upstream commit."
  exit 0
fi

INSTALLED_REVISION="$(git -C "$REPO_ROOT" merge-base "upstream/$BRANCH" "origin/$BRANCH")"
INSTALLED_VERSION="$(read_package_version "$INSTALLED_REVISION")"
STATUS_STATE="update-available"
STATUS_PHASE="merge"
record_status

WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/alpool-sync.XXXXXX")"
rmdir "$WORKTREE"
git -C "$REPO_ROOT" worktree add --detach "$WORKTREE" "origin/$BRANCH" >/dev/null
WORKTREE_ADDED=1

log "Merging upstream/$BRANCH in temporary worktree"
git -C "$WORKTREE" \
  -c user.name="alPool local sync" \
  -c user.email="alpool-sync@localhost" \
  merge --no-edit "upstream/$BRANCH"

STATUS_PHASE="install"
record_status
run_in_worktree "Installing development dependencies" npm install --ignore-scripts --no-audit --no-fund
STATUS_PHASE="test"
record_status
run_in_worktree "Running full test suite" npm test
STATUS_PHASE="lint"
record_status
run_in_worktree "Running lint" npm run lint

if [[ "$DRY_RUN" == "1" ]]; then
  STATUS_STATE="update-available"
  STATUS_PHASE="complete"
  record_status
  log "Dry run complete; validated merge was not pushed."
  exit 0
fi

STATUS_PHASE="push"
record_status
log "Pushing verified merge to origin/$BRANCH"
git -C "$WORKTREE" push origin "HEAD:$BRANCH"
INSTALLED_REVISION="$AVAILABLE_REVISION"
INSTALLED_VERSION="$AVAILABLE_VERSION"
STATUS_STATE="up-to-date"
STATUS_PHASE="complete"
record_status
log "Upstream sync complete. Running alPool will pick it up automatically."
