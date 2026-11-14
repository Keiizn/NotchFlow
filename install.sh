#!/usr/bin/env bash
# Installe (ou met à jour) NotchFlow depuis la dernière Release GitHub.
# Usage : curl -fsSL https://raw.githubusercontent.com/Keiizn/NotchFlow/main/install.sh | bash
#
# Un fichier téléchargé avec curl n'est pas mis en quarantaine par macOS :
# l'app s'ouvre donc sans le message « Impossible d'ouvrir l'application ».
set -euo pipefail

REPO="Keiizn/NotchFlow"
URL="https://github.com/${REPO}/releases/latest/download/NotchFlow.zip"
DEST="/Applications"
[ -w "${DEST}" ] || DEST="${HOME}/Applications"
mkdir -p "${DEST}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "▸ Téléchargement de NotchFlow…"
curl -fL --progress-bar "${URL}" -o "${TMP}/NotchFlow.zip"

echo "▸ Fermeture de l'ancienne version…"
osascript -e 'tell application id "app.notchflow.NotchFlow" to quit' >/dev/null 2>&1 || true
pkill -x NotchFlow >/dev/null 2>&1 || true
sleep 1

echo "▸ Installation dans ${DEST}…"
rm -rf "${DEST}/NotchFlow.app"
ditto -x -k "${TMP}/NotchFlow.zip" "${DEST}"
xattr -dr com.apple.quarantine "${DEST}/NotchFlow.app" 2>/dev/null || true
codesign --force --deep --sign - "${DEST}/NotchFlow.app" >/dev/null 2>&1 || true

echo "▸ Lancement…"
open "${DEST}/NotchFlow.app"
echo "✓ NotchFlow est installé dans ${DEST}. Cherchez l'icône ✨ dans la barre des menus."
