#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/macos"
OUTPUT="$ROOT/dist/alPool.app"
CONTENTS="$OUTPUT/Contents"

swift build --package-path "$PACKAGE" -c release
BIN_DIR="$(swift build --package-path "$PACKAGE" -c release --show-bin-path)"

rm -rf "$OUTPUT"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
install -m 755 "$BIN_DIR/alPool" "$CONTENTS/MacOS/alPool"
install -m 644 "$PACKAGE/Resources/Info.plist" "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$OUTPUT"

echo "Built $OUTPUT"
