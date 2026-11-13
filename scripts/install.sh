#!/bin/bash
# Installs the build from scripts/release.sh into ~/Applications (or the folder given) and starts it.
#
#   scripts/install.sh                 # ~/Applications
#   scripts/install.sh /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

BUILT="build/release/Build/Products/Release/IP Calc.app"
DEST="${1:-$HOME/Applications}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[[ -d "$BUILT" ]] || { echo "No build found, run scripts/release.sh first"; exit 1; }

pkill -x "IP Calc" || true
mkdir -p "$DEST"
rm -rf "$DEST/IP Calc.app"
ditto "$BUILT" "$DEST/IP Calc.app"
# Forget the copy in build/, so Spotlight and launches use the installed one.
"$LSREGISTER" -u "$PWD/$BUILT"
"$LSREGISTER" -f "$DEST/IP Calc.app"
open "$DEST/IP Calc.app"
echo "Installed $DEST/IP Calc.app"
