#!/usr/bin/env bash
# Install the existing WireGuard tunnel as a user service. Never embeds keys.
set -euo pipefail
LABEL=com.ahmedlawal.alpool.tunnel
CONFIG="${ALPOOL_TUNNEL_CONFIG:-$HOME/.config/maxpool-wg/wireproxy.conf}"
BIN="${WIREPROXY_BIN:-$HOME/.local/bin/wireproxy}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/alPool"
[[ -x "$BIN" ]] || { echo 'Install wireproxy or set WIREPROXY_BIN.' >&2; exit 1; }
[[ -r "$CONFIG" ]] || { echo 'The WireGuard tunnel configuration is missing.' >&2; exit 1; }
render() {
cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$BIN</string><string>-c</string><string>$CONFIG</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>StandardOutPath</key><string>$LOG_DIR/tunnel.log</string>
<key>StandardErrorPath</key><string>$LOG_DIR/tunnel.log</string>
</dict></plist>
EOF
}
if [[ "${1:-}" == --print ]]; then render; exit 0; fi
mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"
TMP="$(mktemp "$PLIST.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
render > "$TMP"
plutil -lint "$TMP" >/dev/null
chmod 600 "$TMP" "$CONFIG"
launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
mv "$TMP" "$PLIST"
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl enable "gui/$UID/$LABEL"
launchctl kickstart "gui/$UID/$LABEL"
echo "Installed $LABEL; tunnel configuration and keys remain outside the repository."
