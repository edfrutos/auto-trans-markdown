# Makefile — Pipeline de distribución MDTranslator v3.0
# Uso:
#   make dmg          → build Release + firma ad-hoc + DMG listo para distribuir
#   make appcast      → firma el ZIP con Sparkle y muestra la edSignature
#   make clean        → elimina build/
#
# Requisitos:
#   - Xcode (xcodebuild en PATH)
#   - /tmp/bin/sign_update  (Sparkle release: curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.9.3/Sparkle-2.9.3.tar.xz | tar xJ -C /tmp/)

APP_NAME    := MDTranslator
VERSION     := 3.0
BUILD_NUM   := 1
SCHEME      := MDTranslator
PROJECT     := macos/MDTranslator/MDTranslator.xcodeproj
ARCHIVE     := build/$(APP_NAME).xcarchive
APP         := build/$(APP_NAME).app
ZIP         := build/$(APP_NAME)-$(VERSION).zip
DMG         := build/$(APP_NAME)-$(VERSION).dmg
APPCAST     := docs/appcast.xml
SPARKLE_BIN := /tmp/sparkle/bin

# ---------------------------------------------------------------------------

.PHONY: all build sign zip dmg appcast dev-install register-service clean

all: dmg

## 1. Compilar archivo Release con xcodebuild
build:
	@echo "→ Compilando $(APP_NAME) $(VERSION) (Release)..."
	@mkdir -p build
	xcodebuild archive \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-destination 'platform=macOS,arch=arm64' \
		-archivePath "$(ARCHIVE)" \
		MARKETING_VERSION="$(VERSION)" \
		CURRENT_PROJECT_VERSION="$(BUILD_NUM)" \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO
	@# Exportar .app desde el archive
	cp -R "$(ARCHIVE)/Products/Applications/$(APP_NAME).app" "$(APP)"
	@echo "✓ App: $(APP)"

## 2. Firma ad-hoc (permite ejecutar con clic derecho → Abrir en macOS 14+/15+)
sign: build
	@echo "→ Limpiando ficheros sueltos en raíz del bundle..."
	@find "$(APP)" -maxdepth 1 -mindepth 1 ! -name "Contents" -exec rm -rf {} +
	@echo "→ Firmando ad-hoc..."
	codesign --force --sign - "$(APP)"
	codesign --verify "$(APP)"
	@echo "✓ Firma ad-hoc OK"

## 3. ZIP para Sparkle sign_update
zip: sign
	@echo "→ Creando ZIP para Sparkle..."
	@cd build && ditto -c -k --keepParent "$(APP_NAME).app" "$(APP_NAME)-$(VERSION).zip"
	@echo "✓ ZIP: $(ZIP)"

## 4. DMG instalable con alias a /Applications
dmg: zip
	@echo "→ Creando DMG..."
	@mkdir -p build/dmg_stage
	@cp -R "$(APP)" "build/dmg_stage/"
	@ln -sf /Applications "build/dmg_stage/Applications"
	@cp docs/INSTALL.txt "build/dmg_stage/" 2>/dev/null || true
	hdiutil create \
		-volname "$(APP_NAME) $(VERSION)" \
		-srcfolder "build/dmg_stage" \
		-ov \
		-format UDZO \
		"$(DMG)"
	@rm -rf build/dmg_stage
	@echo ""
	@echo "╔══════════════════════════════════════════════════════╗"
	@echo "║  ✓ DMG listo: $(DMG)"
	@echo "║  Siguiente:   make appcast"
	@echo "╚══════════════════════════════════════════════════════╝"

## 5. Firmar con Sparkle y mostrar edSignature para appcast.xml
appcast: zip
	@echo "→ Firmando ZIP con Sparkle EdDSA..."
	@if [ ! -f "$(SPARKLE_BIN)/sign_update" ]; then \
		echo "ERROR: sign_update no encontrado en $(SPARKLE_BIN)"; \
		echo "Ejecuta: curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.9.3/Sparkle-2.9.3.tar.xz | tar xJ -C /tmp/"; \
		exit 1; \
	fi
	@ZIP_SIZE=$$(wc -c < "$(ZIP)" | tr -d ' '); \
	SIGNATURE=$$($(SPARKLE_BIN)/sign_update "$(ZIP)"); \
	echo ""; \
	echo "Pega estos valores en $(APPCAST) → <enclosure>:"; \
	echo ""; \
	echo "  sparkle:edSignature=\"$$SIGNATURE\""; \
	echo "  length=\"$$ZIP_SIZE\""; \
	echo "  url=\"https://github.com/edefrutos/auto-trans-markdown/releases/download/v$(VERSION)/$(APP_NAME)-$(VERSION).zip\""

## Instalar build Debug en ~/Applications/ y registrar el servicio del sistema
## Necesario para que "Traducir con MDTranslator" aparezca en el menú Services de otras apps.
## Después de ejecutar: reinicia TextEdit (o la app donde quieras usar el servicio).
dev-install:
	@echo "→ Compilando Debug..."
	@mkdir -p build/debug
	xcodebuild build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-destination 'platform=macOS,arch=arm64' \
		CONFIGURATION_BUILD_DIR="$(PWD)/build/debug" \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO | tail -5
	@echo "→ Instalando en ~/Applications/..."
	@mkdir -p ~/Applications
	@rm -rf ~/Applications/MDTranslator.app
	@cp -R build/debug/MDTranslator.app ~/Applications/MDTranslator.app
	@$(MAKE) register-service APP_PATH=~/Applications/MDTranslator.app

## Registrar/actualizar el servicio del sistema para una .app ya instalada.
## APP_PATH: ruta a la .app (por defecto ~/Applications/MDTranslator.app).
APP_PATH ?= ~/Applications/MDTranslator.app
register-service:
	@echo "→ Registrando $(APP_PATH) en Launch Services..."
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f -R -trusted "$(APP_PATH)"
	@echo "→ Flushing pbs (Services menu daemon)..."
	@/System/Library/CoreServices/pbs -flush 2>/dev/null || true
	@echo ""
	@echo "✓ Servicio registrado."
	@echo "  Reinicia TextEdit (u otra app) para ver 'Traducir con MDTranslator' en Services."
	@echo "  Arranca MDTranslator desde ~/Applications/ (no desde Xcode) para probar el servicio."

## Limpiar artefactos de build
clean:
	@rm -rf build/
	@echo "✓ build/ eliminado"
