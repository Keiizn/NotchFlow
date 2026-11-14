#!/usr/bin/env bash
# Compile NotchFlow et assemble un bundle .app signé ad hoc.
# Usage : ./scripts/build-app.sh [release|debug]
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/NotchFlow.app"

echo "▸ Compilation (${CONFIG})…"
swift build -c "$CONFIG" --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"

echo "▸ Assemblage de ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "$BIN_DIR/NotchFlow" "${APP}/Contents/MacOS/NotchFlow"
cp Support/Info.plist "${APP}/Contents/Info.plist"
if [ -f Support/AppIcon.icns ]; then
  cp Support/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP}/Contents/Info.plist" || true
fi

echo "▸ Signature ad hoc…"
codesign --force --deep --options runtime \
  --entitlements Support/NotchFlow.entitlements \
  --sign - "${APP}"

lipo -info "${APP}/Contents/MacOS/NotchFlow"
echo "✓ Terminé : ${APP}"
echo "  Lancer : open \"${APP}\""
