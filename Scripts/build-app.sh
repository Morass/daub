#!/usr/bin/env bash
# Assemble Daub.app from the SwiftPM build. No Xcode project, no xcodegen:
# an .app is a directory with a plist, and keeping it that way keeps the repo readable.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG" --product Daub
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Daub"

APP="$ROOT/build/Daub.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Daub"
cp "$ROOT/Sources/Daub/Support/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature: without it macOS refuses the hardened-runtime-less bundle on first run.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
