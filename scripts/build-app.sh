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

# Icône : génère l'.icns à partir de Support/AppIcon.png (1024×1024)
if [ -f Support/AppIcon.png ]; then
  echo "▸ Génération de l'icône…"
  ICONSET="build/AppIcon.iconset"
  rm -rf "${ICONSET}" && mkdir -p "${ICONSET}"
  for size in 16 32 128 256 512; do
    sips -z ${size} ${size} Support/AppIcon.png --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z ${double} ${double} Support/AppIcon.png --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "${ICONSET}" -o "${APP}/Contents/Resources/AppIcon.icns"
  rm -rf "${ICONSET}"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP}/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${APP}/Contents/Info.plist"
fi

echo "▸ Signature ad hoc…"
codesign --force --deep --options runtime \
  --entitlements Support/NotchFlow.entitlements \
  --sign - "${APP}"

lipo -info "${APP}/Contents/MacOS/NotchFlow"
echo "✓ Terminé : ${APP}"
echo "  Lancer : open \"${APP}\""
