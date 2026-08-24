#!/usr/bin/env bash
# Install the headless alPool backend without silently replacing a live service.
set -euo pipefail

LABEL="com.ahmedlawal.alpool.backend"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NODE_BIN="$(command -v node)"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/alPool"
LOG_PATH="$LOG_DIR/backend.log"
MODE="${1:-}"
GCLOUD_CREDENTIAL_FILE="${CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE:-$HOME/.config/gcloud/application_default_credentials.json}"
CONNECTION="$(node "$REPO_ROOT/src/index.js" app-connection)"
PORT="$(printf '%s' "$CONNECTION" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(new URL(JSON.parse(s).baseURL).port||80))')"

render_gcloud_environment() {
  # Finder/launchd does not inherit interactive shell variables. Give the
  # headless backend the same non-interactive ADC file used by the installer
  # shell so GCP-backed provider keys can resolve after login and reboot.
  # The path is not a credential, and the plist remains user-readable only.
  if [[ -r "$GCLOUD_CREDENTIAL_FILE" ]]; then
    cat <<EOF
    <key>CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE</key>
    <string>$GCLOUD_CREDENTIAL_FILE</string>
EOF
  fi
}

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
    <string>$NODE_BIN</string>
    <string>$REPO_ROOT/src/index.js</string>
    <string>server</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$REPO_ROOT</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$(dirname "$NODE_BIN"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>MAXPOOL_FORCE_SUPERVISOR</key>
    <string>1</string>
$(render_gcloud_environment)
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardOutPath</key>
  <string>$LOG_PATH</string>
  <key>StandardErrorPath</key>
  <string>$LOG_PATH</string>
</dict>
</plist>
EOF
}

if [[ "$MODE" == "--print" ]]; then
  render_plist
  exit 0
fi

listener_pid="$(lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
if [[ -n "$listener_pid" && "$MODE" != "--replace" ]]; then
  echo "alPool is already listening on port $PORT (pid $listener_pid)." >&2
  echo "No process was changed. Use --replace only during the approved one-time cutover." >&2
  exit 2
fi

if [[ -n "$listener_pid" && "$MODE" == "--replace" ]]; then
  # Pass the connection document over stdin so the control key never appears
  # in a process argument or environment variable during cutover.
  printf '%s' "$CONNECTION" | node -e '
    let input = "";
    process.stdin.on("data", chunk => input += chunk).on("end", async () => {
      try {
        const connection = JSON.parse(input);
        const response = await fetch(new URL("/maxpool/control", connection.baseURL), {
          method: "POST",
          headers: { "content-type": "application/json", "x-api-key": connection.apiKey },
          body: JSON.stringify({ type: "stop", payload: {} }),
        });
        if (!response.ok) throw new Error(`control endpoint returned ${response.status}`);
      } catch (error) {
        console.error(`Could not stop the existing backend: ${error.message}`);
        process.exitCode = 1;
      }
    });
  '
  for _ in {1..120}; do
    lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || break
    sleep 0.25
  done
  if lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "The existing backend did not stop; the LaunchAgent was not installed." >&2
    exit 1
  fi
fi

mkdir -p "$PLIST_DIR" "$LOG_DIR"
tmp_plist="$(mktemp "$PLIST_DIR/$LABEL.XXXXXX")"
trap 'rm -f "$tmp_plist"' EXIT
render_plist > "$tmp_plist"
plutil -lint "$tmp_plist" >/dev/null
chmod 600 "$tmp_plist"
mv "$tmp_plist" "$PLIST_PATH"
launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST_PATH"
launchctl enable "gui/$UID/$LABEL"

echo "Installed $LABEL"
echo "Backend log: $LOG_PATH"
if [[ -r "$GCLOUD_CREDENTIAL_FILE" ]]; then
  echo "GCP credential file configured for non-interactive provider secret resolution."
fi
