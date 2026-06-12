#!/usr/bin/env bash
# build-app.sh — Construye MDTranslator.app, firma ad-hoc y genera MDTranslator.dmg
# Uso: ./scripts/build-app.sh
# Prerequisitos:
#   - Xcode instalado (xcodebuild en PATH)
#   - create-dmg instalado: brew install create-dmg
#   - python-bundle/ generado: ./scripts/build-python-bundle.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
PROJECT="$ROOT/macos/MDTranslator/MDTranslator.xcodeproj"
SCHEME="MDTranslator"
CONFIG="Release"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/MDTranslator.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/MDTranslator.app"
DMG="$BUILD_DIR/MDTranslator.dmg"
EXPORT_OPTIONS="$SCRIPT_DIR/exportOptions.plist"

echo "==> Limpiando build anterior..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archivando (esto puede tardar 1-2 min)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" \
  archive \
  | grep -E "^(error:|warning:|Build succeeded|FAILED)" || true

echo "==> Exportando .app..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  | grep -E "^(error:|Export succeeded|FAILED)" || true

if [ ! -d "$APP" ]; then
  echo "ERROR: No se encontró $APP después del export."
  exit 1
fi

echo "==> Firmando ad-hoc (codesign --sign -)..."
codesign \
  --deep \
  --force \
  --sign - \
  "$APP"

echo "==> Verificando firma..."
codesign --verify --deep --strict "$APP" && echo "    Firma válida ✓"

echo "==> Generando DMG con create-dmg..."
# Eliminar DMG anterior si existe (create-dmg falla si el archivo ya existe)
rm -f "$DMG"

create-dmg \
  --volname "MD Translator" \
  --window-size 660 400 \
  --background "" \
  --icon-size 128 \
  --icon "MDTranslator.app" 180 185 \
  --hide-extension "MDTranslator.app" \
  --app-drop-link 480 185 \
  "$DMG" \
  "$EXPORT_DIR/"

echo ""
echo "==> ✅ Build completo"
echo "    App:  $APP"
echo "    DMG:  $DMG"
echo ""

# SHA-256 para appcast.xml de Sparkle
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
SIZE=$(stat -f%z "$DMG")
echo "    SHA-256 del DMG: $SHA"
echo "    Tamaño:          $SIZE bytes"
echo ""
echo "    Para firmar con Sparkle EdDSA:"
echo "    ./bin/sign_update \"$DMG\""
echo ""
echo "    Instrucciones Gatekeeper para el usuario final:"
echo "    Clic derecho en MDTranslator.app → Abrir → confirmar"
echo "    O: xattr -dr com.apple.quarantine MDTranslator.app"
