# Makefile — Pipeline de distribución MDTranslator v3.1
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
VERSION      := 3.1
BUILD_NUM    := 2
SCHEME       := MDTranslator
PROJECT      := macos/MDTranslator/MDTranslator.xcodeproj
ARCHIVE      := build/$(APP_NAME).xcarchive
APP          := build/$(APP_NAME).app
ZIP          := build/$(APP_NAME)-$(VERSION).zip
DMG          := build/$(APP_NAME)-$(VERSION).dmg
APPCAST      := docs/appcast.xml
SPARKLE_BIN  := /tmp/sparkle/bin
# ~/Applications/ está en el volumen del sistema (no en un volumen externo),
# por lo que pbs sí registra sus servicios. /Volumes/ESSAGER/ (externo) es el
# que pbs ignora, no ~/Applications/.
# El build via xcodebuild CLI no incluye el python-bundle (el Run Script de
# Xcode no se ejecuta igual desde CLI). Por eso dev-install registra la app
# que Xcode ya construyó en ~/Applications/, en lugar de copiar desde build/.
INSTALL_DIR  := $(HOME)/Applications
INSTALL_APP  := $(INSTALL_DIR)/$(APP_NAME).app
LSREGISTER   := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# ---------------------------------------------------------------------------

.PHONY: all build sign zip dmg appcast dev-install dev-patch register-service clean smoke-test

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
	@# Exportar .app desde el archive — borrar antes el destino: si existe,
	@# cp -R anida la app nueva DENTRO de la vieja y se distribuye la rancia
	@rm -rf "$(APP)"
	cp -R "$(ARCHIVE)/Products/Applications/$(APP_NAME).app" "$(APP)"
	@echo "OK App: $(APP)"
	@# Verificación: la versión del bundle debe coincidir con VERSION
	@PLIST_V=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$(APP)/Contents/Info.plist" 2>/dev/null || plutil -extract CFBundleShortVersionString raw "$(APP)/Contents/Info.plist"); \
	if [ "$$PLIST_V" != "$(VERSION)" ]; then \
		echo "ERROR: el bundle exportado es v$$PLIST_V, se esperaba v$(VERSION)"; exit 1; \
	fi; \
	echo "OK Versión del bundle: $$PLIST_V"

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
	@# hdiutil falla con "Recurso ocupado" si escribe directamente en un volumen
	@# externo (ESSAGER): crear el DMG en /tmp y copiarlo después
	hdiutil create \
		-volname "$(APP_NAME) $(VERSION)" \
		-srcfolder "build/dmg_stage" \
		-ov \
		-format UDZO \
		"/tmp/$(APP_NAME)-$(VERSION).dmg"
	@cp "/tmp/$(APP_NAME)-$(VERSION).dmg" "$(DMG)" && rm -f "/tmp/$(APP_NAME)-$(VERSION).dmg"
	@rm -rf build/dmg_stage
	@echo ""
	@echo "OK DMG listo: $(DMG)"
	@shasum -a 256 "$(DMG)" | tee build/$(APP_NAME)-$(VERSION).dmg.sha256
	@echo "   Siguiente: make appcast"

## 5. Firmar con Sparkle y mostrar edSignature para appcast.xml
appcast: zip
	@echo "-> Firmando ZIP con Sparkle EdDSA..."
	@if [ ! -f "$(SPARKLE_BIN)/sign_update" ]; then \
		echo "ERROR: sign_update no encontrado en $(SPARKLE_BIN)"; \
		echo "Ejecuta: curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.9.3/Sparkle-2.9.3.tar.xz | tar xJ -C /tmp/"; \
		exit 1; \
	fi
	@SIGNATURE=$$($(SPARKLE_BIN)/sign_update "$(ZIP)"); \
	echo ""; \
	echo "Pega estos valores en $(APPCAST) -> <enclosure>:"; \
	echo ""; \
	echo "  $$SIGNATURE"; \
	echo "  url=\"https://github.com/edfrutos/auto-trans-markdown/releases/download/v$(VERSION)/$(APP_NAME)-$(VERSION).zip\""

## Actualiza el binario e Info.plist en ~/Applications/ con la build CLI (sin python-bundle),
## preservando el python-bundle que Xcode ya instaló ahi.
## Flujo: xcodebuild -> patch binario+plist en ~/Applications/ -> firma -> registra.
## Requiere que ~/Applications/MDTranslator.app exista con python-bundle (build de Xcode).
dev-install:
	@if [ ! -d "$(INSTALL_APP)" ]; then \
		echo "ERROR: $(INSTALL_APP) no existe."; \
		echo "Construye primero desde Xcode (cmd+B) y ejecuta la app una vez."; \
		exit 1; \
	fi
	@echo "-> Compilando Swift (Debug) para obtener binario e Info.plist actualizados..."
	@mkdir -p build/debug
	@set -o pipefail; \
	xcodebuild build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-destination 'platform=macOS,arch=arm64' \
		CONFIGURATION_BUILD_DIR="$(PWD)/build/debug" \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		ENABLE_DEBUG_DYLIB=NO 2>&1 | tee /tmp/xcodebuild-dev.log | tail -10; \
	if grep -q "BUILD FAILED" /tmp/xcodebuild-dev.log; then \
		echo ""; \
		echo "ERROR: xcodebuild falló. Errores Swift:"; \
		grep "error:" /tmp/xcodebuild-dev.log | head -20; \
		echo ""; \
		echo "ALTERNATIVA: abre Xcode → ⌘B → luego ejecuta make dev-patch"; \
		exit 1; \
	fi
	@echo "-> Parcheando binario e Info.plist en $(INSTALL_APP)..."
	cp "build/debug/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" \
	   "$(INSTALL_APP)/Contents/MacOS/$(APP_NAME)"
	cp "build/debug/$(APP_NAME).app/Contents/Info.plist" \
	   "$(INSTALL_APP)/Contents/Info.plist"
	@echo "-> Sincronizando backend Python y estáticos (src/ + static/)..."
	rsync -a --delete src/    "$(INSTALL_APP)/Contents/Resources/backend/src/"
	rsync -a --delete static/ "$(INSTALL_APP)/Contents/Resources/backend/static/"
	@echo "-> Firmando ad-hoc..."
	codesign --force --deep --sign - "$(INSTALL_APP)"
	@$(MAKE) register-service

## Parchea ~/Applications/ sincronizando el Contents/ completo del Debug build de Xcode,
## excluyendo python/ y backend/ (pesados, ya correctos). Soporta ENABLE_DEBUG_DYLIB
## (stub 58 KB + *.debug.dylib) y builds monolíticos clásicos.
## Flujo: abrir Xcode → ⌘B → make dev-patch
dev-patch:
	@DERIVED_APP=$$(find ~/Library/Developer/Xcode/DerivedData -name "$(APP_NAME).app" \
		-path "*/Debug/$(APP_NAME).app" \
		-not -path "*/Intermediates*" \
		-not -path "*/Index.noindex*" \
		-print0 2>/dev/null \
		| xargs -0 ls -dt 2>/dev/null | head -1); \
	if [ -z "$$DERIVED_APP" ]; then \
		echo "ERROR: $(APP_NAME).app no encontrada en DerivedData. Ejecuta ⌘B en Xcode primero."; \
		exit 1; \
	fi; \
	echo "-> Usando app: $$DERIVED_APP"; \
	mkdir -p "$(INSTALL_DIR)"; \
	if [ ! -d "$(INSTALL_APP)" ]; then \
		echo "-> Instalación inicial: copiando app completa desde DerivedData..."; \
		cp -R "$$DERIVED_APP" "$(INSTALL_APP)"; \
	else \
		echo "-> Actualizando Contents/ (excluyendo python y backend)..."; \
		rsync -a --delete \
			--exclude 'Resources/python/' \
			--exclude 'Resources/backend/' \
			"$$DERIVED_APP/Contents/" \
			"$(INSTALL_APP)/Contents/"; \
	fi
	@echo "-> Sincronizando backend Python y estáticos (src/ + static/)..."
	rsync -a --delete src/    "$(INSTALL_APP)/Contents/Resources/backend/src/"
	rsync -a --delete static/ "$(INSTALL_APP)/Contents/Resources/backend/static/"
	@echo "-> Firmando ad-hoc..."
	codesign --force --deep --sign - "$(INSTALL_APP)"
	@$(MAKE) register-service

## Registrar el servicio del sistema para la app en ~/Applications/.
## Desregistra explícitamente paths de build (volumen externo ESSAGER)
## para que macOS use solo la copia en el volumen del sistema.
register-service:
	@echo "-> Desregistrando paths de build anteriores..."
	-$(LSREGISTER) -u "$(PWD)/build/debug/$(APP_NAME).app" 2>/dev/null || true
	-$(LSREGISTER) -u "$(PWD)/build/$(APP_NAME).app" 2>/dev/null || true
	@echo "-> Registrando $(INSTALL_APP) en Launch Services..."
	$(LSREGISTER) -f -trusted $(INSTALL_APP)
	@echo "-> Flushing pbs..."
	@/System/Library/CoreServices/pbs -flush 2>/dev/null || true
	@echo ""
	@echo "OK Servicio registrado."
	@echo "   Reinicia TextEdit para ver Traducir con MDTranslator en Services."
	@echo "   Abre MDTranslator desde $(INSTALL_APP) para probar."

## smoke-test (TEST-01): arranca el servidor, verifica health check y el endpoint estimate.
## No requiere API key real — /api/translate/estimate devuelve 200 (con key) o 503 (sin key).
## Uso: make smoke-test
## Requiere .venv activo: source .venv/bin/activate && make smoke-test
smoke-test:
	@echo "-> smoke-test Phase 15 — TEST-01"
	@PYTHON="$$([ -f .venv/bin/python ] && echo .venv/bin/python || echo python3)"; \
	TEST_PORT=15499; \
	LOGFILE=/tmp/md-translate-smoke.log; \
	echo "   python: $$PYTHON | puerto: $$TEST_PORT | log: $$LOGFILE"; \
	\
	echo "-> Arrancando servidor Python..."; \
	$$PYTHON -m uvicorn src.main:app \
	    --port $$TEST_PORT --host 127.0.0.1 \
	    --no-access-log --log-level warning > "$$LOGFILE" 2>&1 & \
	SERVER_PID=$$!; \
	trap "echo '   cleanup PID $$SERVER_PID'; kill $$SERVER_PID 2>/dev/null; wait $$SERVER_PID 2>/dev/null || true" EXIT INT TERM; \
	\
	echo "-> Health check /api/languages (máx 15 s, poll 500 ms)..."; \
	READY=0; i=0; \
	while [ $$i -lt 30 ]; do \
	    sleep 0.5; \
	    HTTP=$$(curl -sf -o /dev/null -w "%{http_code}" \
	        http://127.0.0.1:$$TEST_PORT/api/languages 2>/dev/null || echo 0); \
	    if [ "$$HTTP" = "200" ]; then READY=1; break; fi; \
	    i=$$((i+1)); \
	done; \
	\
	if [ $$READY -eq 0 ]; then \
	    echo "FAIL: servidor no respondió en 15 s"; \
	    echo "--- log ---"; tail -20 "$$LOGFILE" 2>/dev/null || true; \
	    exit 1; \
	fi; \
	echo "   PASS  GET /api/languages  → 200"; \
	\
	echo "-> POST /api/translate/estimate (no requiere API key real)..."; \
	EST=$$(curl -sf -o /tmp/md-smoke-est.json -w "%{http_code}" \
	    -X POST http://127.0.0.1:$$TEST_PORT/api/translate/estimate \
	    -H "Content-Type: application/json" \
	    -d '{"content":"# Hola mundo\n\nEsto es una prueba de smoke test.","target_lang":"en"}' \
	    2>/dev/null || echo 0); \
	if [ "$$EST" = "200" ]; then \
	    echo "   PASS  POST /api/translate/estimate  → 200"; \
	    cat /tmp/md-smoke-est.json; printf "\n"; \
	elif [ "$$EST" = "503" ]; then \
	    echo "   SKIP  POST /api/translate/estimate  → 503 (API key no configurada — normal en CI)"; \
	else \
	    echo "FAIL: /api/translate/estimate → $$EST (esperado 200 o 503)"; \
	    cat /tmp/md-smoke-est.json 2>/dev/null || true; \
	    exit 1; \
	fi; \
	\
	echo ""; \
	echo "smoke-test OK"

## Limpiar artefactos de build
clean:
	@chmod -R u+w build/ 2>/dev/null || true
	@rm -rf build/
	@echo "OK build/ eliminado"
