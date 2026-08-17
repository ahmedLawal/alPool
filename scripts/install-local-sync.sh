#!/usr/bin/env bash
# Install the local upstream synchronizer as a per-user macOS LaunchAgent.
set -euo pipefail

LABEL="com.ahmedlawal.alpool-upstream-sync"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/scripts/sync-upstream.sh"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/alPool"
LOG_PATH="$LOG_DIR/upstream-sync.log"
NODE_BIN_DIR="$(dirname "$(command -v node)")"

if [[ ! -x "$SYNC_SCRIPT" ]]; then
  echo "Sync script is not executable: $SYNC_SCRIPT" >&2
  exit 1
fi
case "$REPO_ROOT$LOG_PATH" in
  *'&'*|*'<'*|*'>'*|*'"'*)
    echo "Install paths contain characters that cannot be written safely to the plist." >&2
    exit 1
    ;;
esac

render_plist() {
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$SYNC_SCRIPT</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$REPO_ROOT</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$NODE_BIN_DIR:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>21600</integer>
  <key>StandardOutPath</key>
  <string>$LOG_PATH</string>
  <key>StandardErrorPath</key>
  <string>$LOG_PATH</string>
</dict>
</plist>
EOF
}

if [[ "${1:-}" == "--print" ]]; then
  render_plist
  exit 0
fi

mkdir -p "$PLIST_DIR" "$LOG_DIR"
TMP_PLIST="$(mktemp "$PLIST_DIR/$LABEL.XXXXXX")"
trap 'rm -f "$TMP_PLIST"' EXIT
render_plist > "$TMP_PLIST"
plutil -lint "$TMP_PLIST" >/dev/null
chmod 600 "$TMP_PLIST"
mv "$TMP_PLIST" "$PLIST_PATH"

launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
for _ in {1..40}; do
  if ! launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
  echo "Could not stop the existing $LABEL job." >&2
  exit 1
fi
launchctl bootstrap "gui/$UID" "$PLIST_PATH"
launchctl enable "gui/$UID/$LABEL"

echo "Installed $LABEL"
echo "Schedule: at login and every 6 hours"
echo "Log: $LOG_PATH"
