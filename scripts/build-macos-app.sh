#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/macos"
OUTPUT="$ROOT/dist/alPool.app"
CONTENTS="$OUTPUT/Contents"

# The macOS 27 command-line SDK may lack the SwiftUI macro plugin. The 26.5
# SDK builds the same macOS 14+ app; allow an explicit SDK for other toolchains.
SDK="${ALPOOL_MACOS_SDK:-}"
if [[ -z "$SDK" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
BUILD_ARGS=(--package-path "$PACKAGE" -c release)
if [[ -n "$SDK" ]]; then BUILD_ARGS+=(--sdk "$SDK"); fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

rm -rf "$OUTPUT"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
install -m 755 "$BIN_DIR/alPool" "$CONTENTS/MacOS/alPool"
install -m 644 "$PACKAGE/Resources/Info.plist" "$CONTENTS/Info.plist"
VERSION="$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1])).version' "$ROOT/package.json")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$OUTPUT"

echo "Built $OUTPUT"
