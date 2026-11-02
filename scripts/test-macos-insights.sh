#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/alpool-insights.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
SDK="${ALPOOL_MACOS_SDK:-}"
if [[ -z "$SDK" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
ARGS=()
if [[ -n "$SDK" ]]; then ARGS+=( -sdk "$SDK" ); fi
swiftc "${ARGS[@]}" -parse-as-library "$ROOT"/macos/Sources/alPoolCore/*.swift "$ROOT/macos/scripts/check-insights.swift" -o "$TEMP/check-insights"
"$TEMP/check-insights"
