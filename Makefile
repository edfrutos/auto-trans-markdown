# Makefile — Pipeline de distribución MDTranslator v3.0
# Uso:
#   make dmg              -> build Release + firma ad-hoc + DMG listo para distribuir
#   make appcast          -> firma el ZIP con Sparkle y muestra la edSignature
#   make dev-install      -> build Debug + instala en ~/Applications/ + registra servicio
#   make register-service -> solo re-registra la app ya instalada en ~/Applications/
#   make clean            -> elimina build/
#
# Requisitos:
#   - Xcode (xcodebuild en PATH)
#   - /tmp/sparkle/bin/sign_update  (ver target appcast)

APP_NAME     := MDTranslator
VERSION      := 3.0
BUILD_NUM    := 1
SCHEME       := MDTranslator
PROJECT      := macos/MDTranslator/MDTranslator.xcodeproj
ARCHIVE      := build/$(APP_NAME).xcarchive
APP          := build/$(APP_NAME).app
ZIP          := build/$(APP_NAME)-$(VERSION).zip
DMG          := build/$(APP_NAME)-$(VERSION).dmg
APPCAST      := docs/appcast.xml
SPARKLE_BIN  := /tmp/sparkle/bin
INSTALL_DIR  := $(HOME)/Applications
INSTALL_APP  := $(INSTALL_DIR)/$(APP_NAME).app
LSREGISTER   := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# ---------------------------------------------------------------------------

.PHONY: all build sign zip dmg appcast dev-install register-service clean

all: dmg

## 1. Compilar archivo Release con xcodebuild
build:
	@echo "-> Compilando $(APP_NAME) $(VERSION) (Release)..."
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
	@echo "OK App: $(APP)"

## 2. Firma ad-hoc
sign: build
	@echo "-> Limpiando ficheros sueltos en raiz del bundle..."
	@find "$(APP)" -maxdepth 1 -mindepth 1 ! -name "Contents" -exec rm -rf {} +
	@echo "-> Firmando ad-hoc..."
	codesign --force --sign - "$(APP)"
	codesign --verify "$(APP)"
	@echo "OK Firma ad-hoc"

## 3. ZIP para Sparkle sign_update
zip: sign
	@echo "-> Creando ZIP para Sparkle..."
	@cd build && ditto -c -k --keepParent "$(APP_NAME).app" "$(APP_NAME)-$(VERSION).zip"
	@echo "OK ZIP: $(ZIP)"

## 4. DMG instalable con alias a /Applications
dmg: zip
	@echo "-> Creando DMG..."
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
	@echo "OK DMG listo: $(DMG)"
	@echo "   Siguiente: make appcast"

## 5. Firmar con Sparkle y mostrar edSignature para appcast.xml
appcast: zip
	@echo "-> Firmando ZIP con Sparkle EdDSA..."
	@if [ ! -f "$(SPARKLE_BIN)/sign_update" ]; then \
		echo "ERROR: sign_update no encontrado en $(SPARKLE_BIN)"; \
		echo "Ejecuta: curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.9.3/Sparkle-2.9.3.tar.xz | tar xJ -C /tmp/"; \
		exit 1; \
	fi
	@ZIP_SIZE=$$(wc -c < "$(ZIP)" | tr -d ' '); \
	SIGNATURE=$$($(SPARKLE_BIN)/sign_update "$(ZIP)"); \
	echo ""; \
	echo "Pega estos valores en $(APPCAST) -> <enclosure>:"; \
	echo ""; \
	echo "  sparkle:edSignature=\"$$SIGNATURE\""; \
	echo "  length=\"$$ZIP_SIZE\""; \
	echo "  url=\"https://github.com/edefrutos/auto-trans-markdown/releases/download/v$(VERSION)/$(APP_NAME)-$(VERSION).zip\""

## Instalar build Debug en ~/Applications/ y registrar el servicio del sistema.
## Necesario para que "Traducir con MDTranslator" aparezca en Services de otras apps.
## Despues de ejecutar: reinicia TextEdit u otra app para ver el item.
dev-install:
	@echo "-> Compilando Debug..."
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
	@echo "-> Firmando ad-hoc (necesario para Services en macOS 14+)..."
	codesign --force --deep --sign - build/debug/$(APP_NAME).app
	@echo "-> Instalando en $(INSTALL_DIR)/..."
	@mkdir -p $(INSTALL_DIR)
	@rm -rf $(INSTALL_APP)
	@cp -R build/debug/$(APP_NAME).app $(INSTALL_APP)
	@$(MAKE) register-service

## Registrar el servicio del sistema para la app en ~/Applications/.
register-service:
	@echo "-> Registrando $(INSTALL_APP) en Launch Services..."
	$(LSREGISTER) -f -R -trusted $(INSTALL_APP)
	@echo "-> Flushing pbs..."
	@/System/Library/CoreServices/pbs -flush 2>/dev/null || true
	@echo ""
	@echo "OK Servicio registrado."
	@echo "   Reinicia TextEdit para ver Traducir con MDTranslator en Services."
	@echo "   Abre MDTranslator desde $(INSTALL_APP) para probar."

## Limpiar artefactos de build
clean:
	@rm -rf build/
	@echo "OK build/ eliminado"
