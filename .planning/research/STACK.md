# Technology Stack — v3.0 macOS Native App

**Project:** MarkDown Auto Translator — macOS Native App (SwiftUI + Python embedded)
**Researched:** 2026-06-02
**Mode:** Feasibility + Ecosystem (greenfield Swift layer sobre Python existente)
**Confidence:** HIGH para todas las secciones principales (fuentes verificadas con GitHub API y Context7)

---

## Executive Recommendation

Construir la capa Swift como un **Xcode project separado** (`macos/`) dentro del repo mono-repo.
El backend Python existente se embebe **sin modificar** usando `python-build-standalone`
(`install_only_stripped` flavor) como intérprete auto-contenido dentro del `.app` bundle.
La comunicación SwiftUI ↔ FastAPI se hace vía HTTP local (`URLSession`) — sin bindings Python/Swift.

| Layer | Tecnología | Versión verificada |
|-------|------------|-------------------|
| UI nativa | SwiftUI (macOS 14+) | Xcode 26.5 / Swift 6.3.2 |
| Backend embed | python-build-standalone | release `20260510`, CPython 3.11.15 |
| Deps Python | uv pip sync | uv 0.11.4 |
| Auto-update | Sparkle | 2.9.2 (2026-05-17) |
| Keychain | KeychainAccess (SPM) | v4.2.2 (SPM compatible, Swift 5.0+) |
| DMG | create-dmg | v1.2.3 (2025-11-18) |
| Build orchestration | Makefile + xcodebuild | stdlib macOS |

---

## 1. Swift / Xcode / SwiftUI

### Versiones requeridas

| Componente | Versión mínima | Verificado en dev machine |
|------------|---------------|--------------------------|
| Xcode | 15.0+ | Xcode 26.5 (Build 17F42) instalado |
| Swift | 5.9+ | Swift 6.3.2 instalado |
| macOS deployment target | 14.0 (Sonoma) | macOS 26.5 en dev |
| SwiftUI features críticos | macOS 13–14+ | Ver tabla abajo |

### SwiftUI APIs necesarias y su disponibilidad mínima

| API | Disponible desde | Uso en el proyecto |
|-----|-----------------|-------------------|
| `NavigationSplitView` | macOS 13.0 | Layout principal sidebar + detalle |
| `MenuBarExtra` | macOS 13.0 | Icono menubar acceso rápido |
| `MenuBarExtra` (con binding `isInserted`) | macOS 14.0 | Control show/hide del icono |
| `@Observable` macro | macOS 14.0 | State management moderno |
| Structured Concurrency (`async/await`) | macOS 12.0 | Llamadas HTTP a FastAPI local |

**Conclusión:** Target `macOS 14.0 (Sonoma)` es el mínimo que desbloquea todas las APIs
necesarias sin fallbacks. Con Xcode 26.5 y Swift 6.3 se compila sin problemas.

### Proceso Swift para subprocess Python

La comunicación Swift → Python usa `Foundation.Process` (stdlib, sin deps adicionales):

```swift
// Iniciar el servidor FastAPI como subprocess
let process = Process()
process.executableURL = Bundle.main.url(
    forAuxiliaryExecutable: "python/bin/python3"
)
process.arguments = ["-m", "uvicorn", "src.main:app", "--port", "8765", "--no-access-log"]
process.currentDirectoryURL = Bundle.main.url(forResource: "backend", withExtension: nil)
try process.run()
```

No se necesita ninguna librería de interop Python/Swift — la arquitectura preserve-then-translate
ya está encapsulada en la API HTTP existente.

---

## 2. Python Embedded — python-build-standalone

### Qué es y por qué

`python-build-standalone` (mantenido por Astral, los autores de `uv`) produce distribuciones
CPython **portables, auto-contenidas y relocalizables** listas para empaquetar dentro de un
`.app` bundle sin depender del Python del sistema ni de Homebrew.

- **Alternativas descartadas:**
  - **PyInstaller:** Congela bytecode en un ejecutable; no preserva la estructura de paquetes
    necesaria para que FastAPI/Uvicorn funcionen como servidor real. Difícil de debugear en macOS.
  - **Briefcase:** Orientado a apps Python-nativas, no a embedder Python dentro de una app Swift.
    Genera `.app` con Python como UI, no como backend subprocess.
  - **Python del sistema / Homebrew:** No redistribuible; dependencia del entorno del usuario.

### Release y artefactos verificados

- **Repositorio:** `https://github.com/astral-sh/python-build-standalone` (migrado de indygreg/)
- **Último release:** `20260510` (2026-05-10)
- **URL base:** `https://github.com/astral-sh/python-build-standalone/releases/download/20260510/`
- **JSON de último release:** `https://raw.githubusercontent.com/astral-sh/python-build-standalone/latest-release/latest-release.json`

### Builds macOS disponibles (release 20260510)

| Artefacto | Arquitectura | Tamaño | Uso |
|-----------|-------------|--------|-----|
| `cpython-3.11.15+20260510-aarch64-apple-darwin-install_only_stripped.tar.gz` | Apple Silicon | ~45 MB | **Recomendado embed** |
| `cpython-3.11.15+20260510-x86_64-apple-darwin-install_only_stripped.tar.gz` | Intel | ~50 MB | Para universal binary |
| `cpython-3.12.13+20260510-aarch64-apple-darwin-install_only_stripped.tar.gz` | Apple Silicon | ~46 MB | Alternativa Python 3.12 |

**Flavor `install_only_stripped`** es el correcto para embedding:
- Sin artefactos de build, sin debug symbols
- Contiene `bin/python3`, `lib/python3.x/`, `lib/libpython3.x.dylib`
- Es relocatable: los paths internos son relativos (sin hardcoded `/usr/local`)
- Menor footprint en disco (~45 MB vs ~150 MB del `full`)

### Versión de Python a empaquetar

Usar **Python 3.11.15** (no 3.12 ni 3.13) porque:
1. El proyecto declara `requires-python = ">=3.11"` en `pyproject.toml`
2. Compatibilidad garantizada con todas las dependencias actuales (FastAPI, OpenAI SDK, DeepL SDK)
3. 3.11 tiene soporte hasta Octubre 2027 — suficiente para v3.0

### Estructura dentro del .app bundle

```
MarkDownAutoTranslator.app/
  Contents/
    MacOS/
      MarkDownAutoTranslator          ← binario Swift
    Resources/
      backend/                        ← código Python del proyecto
        src/
        pyproject.toml
        uv.lock
      python/                         ← python-build-standalone extraído
        bin/
          python3
        lib/
          python3.11/
          libpython3.11.dylib
        .venv/                        ← virtualenv con dependencias
    Info.plist
    Frameworks/
      Sparkle.framework               ← inyectado por SPM
```

### Instalación de dependencias Python en el bundle

Usar `uv pip sync` para instalar en el virtualenv embebido durante el paso de build:

```bash
# En el Makefile/script de build, después de extraer python-build-standalone:
PYTHON="$APP_BUNDLE/Contents/Resources/python/bin/python3"
$PYTHON -m venv "$APP_BUNDLE/Contents/Resources/python/.venv"
uv pip sync requirements.txt \
  --python "$APP_BUNDLE/Contents/Resources/python/.venv/bin/python"
```

Esto garantiza reproducibilidad (lockfile `uv.lock` incluido en el bundle como referencia).

---

## 3. Sparkle — Auto-update

### Versión y release

- **Versión:** `2.9.2` (lanzado 2026-05-17)
- **Repo:** `https://github.com/sparkle-project/Sparkle`
- **SPM URL:** `https://github.com/sparkle-project/Sparkle` (v2.9.2)
- **SPM checksum:** `b83e37436774556ed055e0244b297ef2c790e0737393bf65bf495fcbba6eed65`
- **macOS mínimo:** 10.13 (el package.swift declara `.macOS(.v10_13)`)

### Por qué Sparkle (no Mac App Store updates)

La distribución es DMG ad-hoc sin Apple Developer account ($99/año). Sparkle es el estándar
de facto para auto-update en apps macOS fuera del App Store, utilizado en apps como
Homebrew Cask, Bear, Sketch (versiones legacy), etc.

Sparkle 2.x (vs 1.x) usa **EdDSA (ed25519)** en lugar de DSA obsoleto — más seguro y
sin dependencia de OpenSSL.

### Integración SPM en Package.swift

```swift
// Package.swift (macos/Package.swift)
dependencies: [
    .package(
        url: "https://github.com/sparkle-project/Sparkle",
        from: "2.9.2"
    ),
    .package(
        url: "https://github.com/kishikawakatsumi/KeychainAccess",
        from: "4.2.2"
    )
],
targets: [
    .executableTarget(
        name: "MarkDownAutoTranslator",
        dependencies: [
            .product(name: "Sparkle", package: "Sparkle"),
            .product(name: "KeychainAccess", package: "KeychainAccess"),
        ]
    )
]
```

### Patrón SwiftUI (verificado en Context7)

```swift
import SwiftUI
import Sparkle

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

@main
struct MarkDownAutoTranslatorApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup { ContentView() }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
```

### Configuración Info.plist requerida

```xml
<!-- Info.plist en el target macOS -->
<key>SUFeedURL</key>
<string>https://tu-servidor.com/appcast.xml</string>

<key>SUPublicEDKey</key>
<string><!-- clave pública generada con ./bin/generate_keys --></string>

<key>CFBundleVersion</key>
<string>1</string>  <!-- entero, incrementar en cada release -->

<key>CFBundleShortVersionString</key>
<string>3.0.0</string>
```

### Flujo de release con Sparkle

1. Compilar y firmar app con ad-hoc (`codesign -s -`)
2. Crear DMG con `create-dmg`
3. Firmar el DMG con EdDSA: `./Sparkle.framework/bin/sign_update dist/App.dmg`
4. Publicar DMG en GitHub Releases
5. Actualizar `appcast.xml` en rama `gh-pages` o servidor estático

**Sin Apple Developer account:** La firma EdDSA de Sparkle garantiza integridad del update
aunque la app no esté notarizada por Apple. El usuario bypasea Gatekeeper manualmente en
la instalación inicial (clic derecho → Abrir).

---

## 4. Keychain — API Keys sin .env

### Librería

- **KeychainAccess** v4.2.2 por kishikawa katsumi
- **Repo:** `https://github.com/kishikawakatsumi/KeychainAccess`
- **SPM compatible:** Sí (Package.swift swift-tools-version:5.0)
- **Última release:** 2021-03-01 (estable, sin cambios necesarios — wrapper sobre Security.framework)

### Por qué KeychainAccess en lugar de Security.framework directo

- La API nativa `SecItemAdd`/`SecItemCopyMatching` requiere 30+ líneas de boilerplate Swift/CFType
- KeychainAccess expone una API subscript simple compatible con SwiftUI
- No sandboxed app no necesita el flag `-Xlinker -no_application_extension` de su Package.swift

```swift
import KeychainAccess

let keychain = Keychain(service: "com.tuempresa.markdown-auto-translator")

// Guardar API key
keychain["openai_api_key"] = apiKey

// Leer (usada como env var antes de lanzar el subprocess Python)
let key = keychain["openai_api_key"]
```

La app Swift inyecta las keys como variables de entorno al proceso Python antes de `process.run()`:

```swift
process.environment = [
    "OPENAI_API_KEY": keychain["openai_api_key"] ?? "",
    "TRANSLATION_PROVIDER": preferences.provider,
    "PORT": "8765"
]
```

Esto mantiene el código Python sin cambios — sigue leyendo `os.getenv("OPENAI_API_KEY")`.

---

## 5. DMG — Distribución ad-hoc

### Herramienta

- **create-dmg** v1.2.3 (2025-11-18)
- **Repo:** `https://github.com/create-dmg/create-dmg`
- **Instalación:** `brew install create-dmg` (ya instalado en dev machine)

### Por qué create-dmg sobre appdmg y hdiutil directo

| Herramienta | Ventajas | Inconvenientes |
|-------------|----------|----------------|
| **create-dmg** | Shell script, sin deps Node.js, soporte `--codesign`, Homebrew | AppleScript para UI (lento) |
| appdmg | Config JSON declarativa, programable en Node.js | Requiere Node.js en build machine |
| hdiutil directo | Sin deps, máximo control | 20+ líneas de scripting para fondo/iconos |

create-dmg es la opción más limpia para un Makefile sin Node.js.

### Firma ad-hoc (sin Apple Developer)

```bash
# Firmar la app con identidad ad-hoc ("-")
codesign --force --deep --sign "-" \
  --options runtime \
  "dist/MarkDownAutoTranslator.app"

# Crear DMG firmado ad-hoc
create-dmg \
  --volname "MarkDown Auto Translator" \
  --volicon "assets/VolumeIcon.icns" \
  --background "assets/dmg-background.png" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "MarkDownAutoTranslator.app" 175 190 \
  --hide-extension "MarkDownAutoTranslator.app" \
  --app-drop-link 425 190 \
  --codesign "-" \
  "dist/MarkDownAutoTranslator-3.0.0.dmg" \
  "dist/MarkDownAutoTranslator.app"
```

**Gatekeeper sin notarización:** Con firma ad-hoc `-` el usuario verá la advertencia
"Apple no puede comprobar que esta app no contiene software malicioso". Solución documentada
en el README: clic derecho → Abrir la primera vez. Esto es el comportamiento estándar para
distribución indie sin cuenta de desarrollador.

**Ventaja sobre sin firmar:** La firma ad-hoc evita el error "app dañada" de Gatekeeper
en macOS 13+ que bloquea apps sin firmar completamente.

---

## 6. Build System — Makefile + xcodebuild

### Por qué Makefile sobre CMake o solo Xcode

- El proyecto tiene un backend Python con su propio sistema de build (`uv`, `pytest`)
- Makefile orquesta ambos mundos (Python build + Swift build + empaquetado)
- Xcode build settings se configuran una vez; Makefile llama a `xcodebuild` en CI

```makefile
# Makefile (fragmento representativo)
PYTHON_VERSION    := 3.11.15
PBS_RELEASE       := 20260510
PBS_ARCH          := aarch64-apple-darwin
PBS_URL           := https://github.com/astral-sh/python-build-standalone/releases/download/$(PBS_RELEASE)
PBS_ARTIFACT      := cpython-$(PYTHON_VERSION)+$(PBS_RELEASE)-$(PBS_ARCH)-install_only_stripped.tar.gz

.PHONY: build clean dmg

fetch-python:
	curl -L "$(PBS_URL)/$(PBS_ARTIFACT)" -o /tmp/python-standalone.tar.gz
	tar xzf /tmp/python-standalone.tar.gz -C macos/Resources/python --strip-components=1

install-deps: fetch-python
	uv pip sync requirements.txt \
	  --python macos/Resources/python/bin/python3 \
	  --target macos/Resources/python/lib/python$(PYTHON_VERSION)/site-packages

build-swift:
	xcodebuild -project macos/MarkDownAutoTranslator.xcodeproj \
	  -scheme MarkDownAutoTranslator \
	  -configuration Release \
	  -derivedDataPath build/

bundle: install-deps build-swift
	cp -r build/.../MarkDownAutoTranslator.app dist/
	codesign --force --deep --sign "-" dist/MarkDownAutoTranslator.app

dmg: bundle
	create-dmg --volname "MarkDown Auto Translator" \
	  --app-drop-link 425 190 \
	  --codesign "-" \
	  dist/MarkDownAutoTranslator-$(VERSION).dmg \
	  dist/MarkDownAutoTranslator.app
```

### Estructura del repo

```
auto-trans-markdown/
  src/                    ← Python backend (sin cambios)
  tests/                  ← Tests Python (sin cambios)
  static/                 ← Web UI (sin cambios)
  macos/                  ← NUEVO: capa Swift
    MarkDownAutoTranslator.xcodeproj/
    Package.swift
    Sources/
      MarkDownAutoTranslator/
        App.swift
        Views/
        Services/
          PythonBackend.swift   ← Process management
          TranslatorAPI.swift   ← URLSession calls
          KeychainService.swift
    Resources/
      backend/             ← symlink o copia de src/ en build time
      python/              ← python-build-standalone (gitignored, descargado en build)
  Makefile                 ← NUEVO: orchestración build completo
  .gitignore               ← añadir macos/Resources/python/
```

---

## 7. Comunicación SwiftUI ↔ FastAPI

No se necesitan bindings Python/Swift. SwiftUI usa `URLSession` estándar contra el
servidor local. El puerto se elige en runtime (evitar conflictos con el puerto 8000 del servidor web):

```swift
// TranslatorAPI.swift
struct TranslatorAPI {
    let baseURL: URL

    func translate(text: String, targetLang: String) async throws -> String {
        let url = baseURL.appendingPathComponent("/api/translate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = TranslateTextRequest(text: text, target_lang: targetLang)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TranslateResponse.self, from: data).translated_text
    }
}
```

Puerto recomendado: **8765** (libre, no conflicta con puerto 8000 del servidor web ni con
puertos comunes de desarrollo).

---

## 8. Alternativas descartadas

| Categoría | Recomendado | Alternativa | Razón descarte |
|-----------|-------------|-------------|----------------|
| Python embed | **python-build-standalone** | PyInstaller | Congela bytecode; no sirve como servidor real; difícil debug |
| Python embed | **python-build-standalone** | Briefcase | Orientado a UI Python, no a subprocess backend |
| Python embed | **python-build-standalone** | Python Homebrew | No redistribuible; dependencia del sistema |
| Auto-update | **Sparkle 2.9.2** | Squirrel | No mantenido en macOS; para Electron principalmente |
| Auto-update | **Sparkle 2.9.2** | Manual GitHub Releases check | Sin delta updates, sin UI nativa de update |
| DMG | **create-dmg** | appdmg | Requiere Node.js en build machine |
| DMG | **create-dmg** | hdiutil directo | Sin soporte fondo/iconos sin AppleScript manual |
| Keychain | **KeychainAccess** | Security.framework directo | 30+ líneas de CFType boilerplate para lo mismo |
| Build | **Makefile + xcodebuild** | CMake | Overhead innecesario; xcodebuild es suficiente |
| Comm Swift↔Python | **URLSession HTTP** | Python-Swift bindings (PythonKit) | PythonKit no soporta async/await bien; añade 10+ MB |
| Comm Swift↔Python | **URLSession HTTP** | XPC service | Demasiada complejidad para un proceso local |

---

## 9. Dependencias adicionales Swift (SPM)

Ninguna otra dependencia Swift es necesaria en v3.0. El stack mínimo es:

- **Sparkle 2.9.2** — auto-update
- **KeychainAccess 4.2.2** — API keys
- **Foundation** (stdlib) — `Process`, `URLSession`, `UserDefaults`
- **AppKit + SwiftUI** (stdlib macOS) — UI nativa

Para el drag & drop de archivos `.md`, `NSOpenPanel` y el modifier `.onDrop(of:)` de SwiftUI
son suficientes — sin librerías adicionales.

---

## 10. Resumen de versiones verificadas

| Componente | Versión | Fuente | Confianza |
|------------|---------|--------|-----------|
| Xcode | 26.5 (17F42) | `xcodebuild -version` en dev machine | HIGH |
| Swift | 6.3.2 | `swift --version` en dev machine | HIGH |
| macOS deployment target | 14.0 (Sonoma) | SwiftUI API research (Context7) | HIGH |
| python-build-standalone | release 20260510 | GitHub API `indygreg/python-build-standalone` | HIGH |
| CPython embebido | 3.11.15 | GitHub API releases assets | HIGH |
| Sparkle | 2.9.2 | GitHub API `sparkle-project/Sparkle` | HIGH |
| Sparkle SPM checksum | `b83e374...` | `Package.swift` del repo oficial | HIGH |
| KeychainAccess | 4.2.2 | GitHub API `kishikawakatsumi/KeychainAccess` | HIGH |
| create-dmg | 1.2.3 | GitHub API + `create-dmg --version` local | HIGH |
| uv | 0.11.4 | `uv --version` en dev machine | HIGH |

---

## Sources

| Fuente | URL | Confianza | Usado para |
|--------|-----|-----------|------------|
| python-build-standalone docs | `github.com/astral-sh/python-build-standalone` | HIGH | Flavors, relocatability, macOS builds |
| python-build-standalone releases | GitHub API releases | HIGH | Versión 20260510, assets macOS |
| Sparkle documentation | Context7 `/websites/sparkle-project` | HIGH | SPM, EdDSA, SwiftUI integration |
| Sparkle Package.swift | `github.com/sparkle-project/Sparkle/blob/main/Package.swift` | HIGH | Checksum, SPM URL, macOS mínimo |
| Sparkle latest release | GitHub API | HIGH | v2.9.2, fecha 2026-05-17 |
| SwiftUI MenuBarExtra | Context7 `/websites/developer_apple_swiftui` | HIGH | macOS 13.0+ availability |
| SwiftUI NavigationSplitView | Context7 `/websites/developer_apple_swiftui` | HIGH | macOS 13.0+ availability |
| KeychainAccess | Context7 `/kishikawakatsumi/keychainaccess` | HIGH | API, SPM, macOS compat |
| create-dmg README | GitHub API `create-dmg/create-dmg` | HIGH | `--codesign`, ad-hoc signing |
| create-dmg version | `create-dmg --version` local | HIGH | v1.2.3 confirmado |
| uv pip sync | Context7 `/astral-sh/uv` | HIGH | Embedded venv install |

---

*Stack research para milestone v3.0 macOS Native App — sobreescribe el STACK.md del milestone NOTEBOOK v1.0.*
*Investigado: 2026-06-02. Próxima revisión: al inicio de Phase 9 (Python embed)*
