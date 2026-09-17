#!/usr/bin/env bash
# Build Daub and install it into /Applications, ready to launch.
#
# Daub is ad-hoc signed rather than notarized, so a bundle that arrives over a share or a
# download carries a quarantine flag and macOS refuses it. Building locally avoids that,
# and `xattr -cr` clears anything a copy picked up.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DAUB_INSTALL_DIR:-/Applications}/Daub.app"

"$ROOT/Scripts/build-app.sh" release

if [ ! -w "$(dirname "$DEST")" ]; then
    echo "note: $(dirname "$DEST") is not writable, installing to ~/Applications instead"
    DEST="$HOME/Applications/Daub.app"
fi

pkill -f "Daub.app/Contents/MacOS/Daub" 2>/dev/null || true
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -R "$ROOT/build/Daub.app" "$DEST"
xattr -cr "$DEST"

echo "installed: $DEST"
echo "run it with:  open '$DEST'"
