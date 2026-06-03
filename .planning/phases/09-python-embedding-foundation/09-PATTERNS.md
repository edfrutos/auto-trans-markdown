# Phase 9: Python Embedding Foundation - Pattern Map

**Mapped:** 2026-06-03
**Files analyzed:** 7 (5 nuevos Swift/shell, 1 modificado, 1 nuevo Xcode)
**Analogs found:** 4 / 7 (los 3 Swift no tienen análogo Swift — stack nuevo)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/build-python-bundle.sh` | utility (build script) | batch / file-I/O | `scripts/md-translate` | role-match (mismo idioma, distinto propósito) |
| `macos/MDTranslator.xcodeproj/project.pbxproj` | config | — | `pyproject.toml` | partial (metadata de proyecto, diferente formato) |
| `macos/MDTranslator/MDTranslatorApp.swift` | provider / entry-point | event-driven | `src/main.py` (`run()` + `app`) | cross-lang conceptual |
| `macos/MDTranslator/ServerManager.swift` | service | request-response + event-driven | `src/main.py` (`run()`, startup, shutdown) | cross-lang conceptual |
| `macos/MDTranslator/SplashView.swift` | component | event-driven | `static/index.html` (startup feedback) | cross-lang conceptual |
| `macos/MDTranslator/Info.plist` | config | — | `pyproject.toml` (metadata, entry points) | partial |
| `.gitignore` | config | — | `.gitignore` (existing) | exact |

---

## Pattern Assignments

### `scripts/build-python-bundle.sh` (utility, batch/file-I/O)

**Analog:** `scripts/md-translate` (lines 1–16)

**Shell script header pattern** (lines 1–5 de `scripts/md-translate`):
```bash
#!/usr/bin/env bash
# Wrapper: usa el CLI instalado en .venv sin activar el entorno virtual.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```
Copiar: shebang `#!/usr/bin/env bash`, `set -euo pipefail`, y cálculo de `ROOT` con `BASH_SOURCE[0]`. El comentario de cabecera describe el propósito del script en español.

**Error guard pattern** (lines 8–13 de `scripts/md-translate`):
```bash
if [[ ! -x "$CLI" ]]; then
  echo "md-translate: no encontrado en .venv/bin/" >&2
  echo "Desde la raíz del proyecto, con el venv activo, ejecuta:" >&2
  echo "  pip install -e ." >&2
  exit 2
fi
```
Copiar: guardia con `[[ ! -x "$PATH" ]]`, mensajes de error a stderr con `>&2`, `exit` con código no-cero. Para el build script: sustituir por smoke test (`exit 1` si `import fastapi` falla) con mensaje en español orientado al usuario.

**Analog adicional — Dockerfile** (lines 1–34, `Dockerfile`): patrón de instalación Python en target dir y health check HTTP.

**Health check HTTP pattern** (line 32 de `Dockerfile`):
```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5400/api/languages', timeout=3)"
```
El build script no hace health check HTTP, pero el endpoint `/api/languages` confirmado aquí es el mismo que usará `ServerManager.swift` en el health check (BUNDLE-04).

**uvicorn CLI invocation** (line 34 de `Dockerfile`):
```dockerfile
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "5400"]
```
En Swift: reemplazar `0.0.0.0` por `127.0.0.1` y `5400` por el puerto dinámico. Añadir `--no-access-log`. Patrón de argumentos `-m uvicorn src.main:app --host ... --port ...` es el canónico del proyecto.

**run() entry point** (lines 857–866 de `src/main.py`):
```python
def run():
    import uvicorn
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "5400"))
    uvicorn.run("src.main:app", host=host, port=port, reload=True)
```
El build script no toca este código, pero el valor por defecto de HOST (`127.0.0.1`) y PORT (`5400`) confirma que Swift debe sobreescribir PORT con el puerto dinámico y mantener HOST fijo a `127.0.0.1`.

**Patron completo del build script** (del RESEARCH.md, verificado en local):
```bash
#!/usr/bin/env bash
# build-python-bundle.sh — descarga CPython standalone e instala dependencias del bundle.
# Ejecutar una vez antes del primer build de Xcode: ./scripts/build-python-bundle.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/python-bundle"
PBS_RELEASE="20260510"
PBS_VERSION="3.11.15"
PBS_ARCH="aarch64-apple-darwin"
PBS_FLAVOR="install_only_stripped"
PBS_ARTIFACT="cpython-${PBS_VERSION}+${PBS_RELEASE}-${PBS_ARCH}-${PBS_FLAVOR}.tar.gz"
PBS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/${PBS_ARTIFACT}"

echo "→ Descargando CPython ${PBS_VERSION} standalone..."
curl -L --progress-bar "$PBS_URL" -o /tmp/cpython-standalone.tar.gz

# Verificar estructura del tarball antes de extraer (A1: asunción subdirectorio python/)
echo "→ Verificando estructura del tarball..."
FIRST_DIR=$(tar tzf /tmp/cpython-standalone.tar.gz 2>/dev/null | head -1)
if [[ "$FIRST_DIR" != "python/" ]]; then
  echo "ERROR: estructura inesperada del tarball (primer entry: $FIRST_DIR)" >&2
  exit 1
fi

echo "→ Extrayendo en ${BUNDLE_DIR}..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"
tar xzf /tmp/cpython-standalone.tar.gz -C "$BUNDLE_DIR" --strip-components=1

PYTHON="$BUNDLE_DIR/bin/python3"

echo "→ Exportando requirements desde uv.lock..."
uv export \
  --format requirements-txt \
  --no-dev \
  --no-editable \
  --no-emit-project \
  --no-hashes \
  > /tmp/bundle-requirements.txt

echo "→ Instalando dependencias en site-packages del bundle..."
uv pip install \
  -r /tmp/bundle-requirements.txt \
  --target "$BUNDLE_DIR/lib/python${PBS_VERSION}/site-packages/" \
  --python "$PYTHON"

echo "→ Smoke test: import fastapi..."
"$PYTHON" -c "import fastapi; print('OK — fastapi', fastapi.__version__)" || {
  echo "ERROR: smoke test falló. El bundle no está correctamente instalado." >&2
  exit 1
}

echo "✓ python-bundle listo en ${BUNDLE_DIR}"
```

---

### `macos/MDTranslator/MDTranslatorApp.swift` (provider/entry-point, event-driven)

**No hay análogo Swift en el repositorio.** Stack nuevo. Usar patrones de RESEARCH.md.

**Conceptual analog — `src/main.py`** (arranque de la app, registro de lifecycle hooks):

El patrón `src/main.py` que corresponde conceptualmente es:
- `app = FastAPI(...)` → `@main struct MDTranslatorApp: App`
- `@app.on_event("startup")` → `.task { await serverManager.start() }` en SplashView
- `run()` con `uvicorn.run(...)` → `WindowGroup { ... }` con `@NSApplicationDelegateAdaptor`

**Patrón Swift extraído de RESEARCH.md** (patrón 5 + 6, verificado):
```swift
import SwiftUI

@main
struct MDTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var serverManager = ServerManager()

    var body: some Scene {
        WindowGroup {
            if serverManager.state == .running {
                Text("Main UI — Phase 10")  // Placeholder hasta Phase 10
            } else {
                SplashView(serverManager: serverManager)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 220)  // macOS 13+
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var serverManager: ServerManager?

    func applicationWillTerminate(_ notification: Notification) {
        serverManager?.stop()
        Thread.sleep(forTimeInterval: 1.0)  // Dar tiempo al SIGINT antes de que el OS mate el proceso
    }
}
```

**Nota de implementación:** `delegate.serverManager` debe conectarse al mismo `ServerManager` que usa el `App` struct. Patrón canónico: inyectar via `@EnvironmentObject` o guardar referencia en `AppDelegate` desde `MDTranslatorApp.init`.

---

### `macos/MDTranslator/ServerManager.swift` (service, request-response + event-driven)

**No hay análogo Swift en el repositorio.** Stack nuevo.

**Conceptual analog — `src/main.py`** — el ciclo `run()` → startup → health check → shutdown es el espejo Python de `ServerManager`.

Correspondencia directa de responsabilidades:
| Python (`src/main.py`) | Swift (`ServerManager.swift`) |
|------------------------|-------------------------------|
| `run()` lines 857–866 | `start() async` |
| `os.getenv("HOST", "127.0.0.1")` | `p.environment = ["HOST": "127.0.0.1"]` |
| `os.getenv("PORT", "5400")` | `findFreePort()` → `p.arguments = ["--port", "\(port)"]` |
| `@app.on_event("startup") async def startup_sweep_output()` | `p.terminationHandler` |
| Dockerfile `HEALTHCHECK` (line 32) | `waitForHealthCheck(port:)` |

**Patrón Foundation.Process** (RESEARCH.md patrón 2, confirmado contra Apple Docs):
```swift
import Foundation
import AppKit

@MainActor
class ServerManager: ObservableObject {
    enum State { case idle, starting, running, failed }

    @Published private(set) var state: State = .idle
    private var process: Process?
    private var serverPort: Int = 0

    func start() async {
        guard state == .idle || state == .failed else { return }
        state = .starting

        let port = findFreePort()
        guard port > 0 else { state = .failed; return }
        serverPort = port

        let pythonURL = Bundle.main.resourceURL!
            .appendingPathComponent("python/bin/python3")
        let backendURL = Bundle.main.resourceURL!
            .appendingPathComponent("backend")

        let p = Process()
        p.executableURL = pythonURL
        p.arguments = [
            "-m", "uvicorn", "src.main:app",
            "--port", "\(port)",
            "--host", "127.0.0.1",
            "--no-access-log"
        ]
        p.currentDirectoryURL = backendURL
        p.environment = [
            "HOST": "127.0.0.1",
            "PORT": "\(port)",
            "PYTHONDONTWRITEBYTECODE": "1"   // Evitar PermissionError en /Applications
        ]

        // Swift 6: terminationHandler es @Sendable — usar Task { @MainActor in }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.state == .running { self?.state = .failed }
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            state = .failed
            return
        }

        await waitForHealthCheck(port: port)
    }

    func stop() {
        guard let p = process, p.isRunning else { return }
        p.interrupt()  // SIGINT → uvicorn graceful shutdown (igual que SIGTERM)
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if p.isRunning { p.terminate() }  // SIGKILL si no terminó en 5 s
        }
        process = nil
    }
}
```

**Patrón findFreePort** (RESEARCH.md patrón 3 — BSD sockets Darwin):
```swift
import Darwin

func findFreePort() -> Int {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    addr.sin_port = 0

    let sock = socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { return 0 }
    defer { Darwin.close(sock) }

    let bindResult = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else { return 0 }

    var boundAddr = sockaddr_in()
    var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    withUnsafeMutablePointer(to: &boundAddr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(sock, $0, &addrLen)
        }
    }
    return Int(CFSwapInt16BigToHost(boundAddr.sin_port))
}
```

**Patrón health check** (RESEARCH.md patrón 4 — URLSession async/await):
```swift
private func waitForHealthCheck(port: Int) async {
    let deadline = Date().addingTimeInterval(15)
    let url = URL(string: "http://127.0.0.1:\(port)/api/languages")!
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 1.0   // Falla rápido, no 60 s por defecto
    let session = URLSession(configuration: config)

    while Date() < deadline {
        do {
            let (_, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                state = .running
                return
            }
        } catch { /* servidor aún no listo — reintentar */ }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    stop()
    state = .failed
}
```

**Endpoint confirmado:** `/api/languages` responde HTTP 200 con `list[LanguageItem]` — ver `src/main.py` line 402–410. Sin auth (`_require_api_token` no aplica a este endpoint). Seguro usar como health check.

---

### `macos/MDTranslator/SplashView.swift` (component, event-driven)

**No hay análogo Swift en el repositorio.** Stack nuevo.

**Conceptual analog — `static/index.html`** (feedback visual de startup). En la web, el estado de carga se gestiona con JS en `static/js/app.js`; aquí SwiftUI observa `serverManager.state`.

**Patrón SplashView** (RESEARCH.md patrón 5):
```swift
import SwiftUI
import AppKit

struct SplashView: View {
    @ObservedObject var serverManager: ServerManager

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(.circular)
            Text("Iniciando servidor...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(width: 400, height: 220)
        // El .task arranca el servidor al aparecer la vista — no después
        .task {
            await serverManager.start()
        }
        // .constant(condition) para binding derivado de estado — evitar @State extra
        .alert("Error al iniciar el servidor",
               isPresented: .constant(serverManager.state == .failed)) {
            Button("Reintentar") {
                Task { await serverManager.start() }
            }
            Button("Salir", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
    }
}
```

**Nota de diseño (Claude's Discretion — D-06):** Sin barra de título via `.windowStyle(.hiddenTitleBar)` en el App struct (no en la View). La View solo define contenido y tamaño frame. El fondo usa el color del sistema por defecto (sin `.background()` explícito).

---

### `macos/MDTranslator/Info.plist` (config)

**Analog parcial — `pyproject.toml`** (metadata del proyecto: nombre, versión, entry point).

Correspondencia:
| `pyproject.toml` | `Info.plist` |
|------------------|--------------|
| `name = "auto-trans-markdown"` | `CFBundleName = "MD Translator"` |
| `version = "2.0.0"` | `CFBundleShortVersionString = "3.0.0"` |
| `requires-python = ">=3.11"` | `LSMinimumSystemVersion = "14.0"` |
| `md-translate = "src.cli:app"` | `NSPrincipalClass = "NSApplication"` |

**Patrón Info.plist** (RESEARCH.md, Code Examples):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MD Translator</string>
    <key>CFBundleIdentifier</key>
    <string>com.edefrutos.md-translator</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>3.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

**Nota:** Xcode suele generar `Info.plist` al crear el proyecto. Si el proyecto se genera via Xcode GUI, verificar que `CFBundleIdentifier` sea `com.edefrutos.md-translator` y `LSMinimumSystemVersion` sea `14.0` (puede quedar como `13.0` por defecto en Xcode 26.5).

---

### `macos/MDTranslator.xcodeproj/project.pbxproj` (config)

**No hay análogo en el repositorio.** Fichero generado por Xcode al crear el proyecto.

Este fichero no debe escribirse manualmente. Se genera al crear el proyecto en Xcode con:
- Product Name: `MDTranslator`
- Bundle Identifier: `com.edefrutos.md-translator`
- Interface: SwiftUI
- Language: Swift
- macOS Deployment Target: 14.0

**Analog conceptual — `pyproject.toml`** (declaración de build system, target, dependencias). No se extrae patrón de código: el fichero `.pbxproj` es XML binario-ascii generado.

---

### `.gitignore` (config, exact match)

**Analog:** `.gitignore` existente (el mismo fichero — modificación).

**Patrón existente de secciones** (líneas 1–49 de `.gitignore`):
```gitignore
# --- Secretos y configuración local ---
.env
.env.*

# --- Python ---
.venv/
venv/
__pycache__/

# --- Salida de traducciones (puede contener docs privados) ---
output/
data/
*.zip
```

**Entrada a añadir** — siguiendo el patrón de secciones con comentario descriptivo:
```gitignore
# --- macOS app bundle (generado por build-python-bundle.sh) ---
python-bundle/
macos/MDTranslator.xcodeproj/xcuserdata/
macos/MDTranslator.xcodeproj/project.xcworkspace/xcuserdata/
*.xcuserstate
```

La entrada `python-bundle/` va en una sección nueva `# --- macOS app bundle ---`, coherente con el estilo de comentarios `# --- Categoría ---` ya establecido. Se añaden también los directorios de estado de usuario de Xcode (`xcuserdata/`, `*.xcuserstate`) que son equivalentes a `.venv/` — artefactos locales que no se versionan.

---

## Shared Patterns

### Patrón de arranque del servidor (Python → Swift)

**Fuente Python:** `src/main.py` lines 857–866 + `Dockerfile` line 34
**Aplica a:** `ServerManager.swift`, `build-python-bundle.sh`

El comando canónico del proyecto para arrancar uvicorn es:
```bash
python -m uvicorn src.main:app --host 127.0.0.1 --port PORT
```
- `src.main:app` es el módulo de entrada — no cambiar
- `--host` siempre `127.0.0.1` (loopback) — el Dockerfile usa `0.0.0.0` pero eso es para Docker; en el bundle macOS debe ser loopback
- `--port` dinámico vía `findFreePort()`
- `--no-access-log` para reducir ruido en los logs del bundle
- `currentDirectoryURL` = `Resources/backend/` (el `ROOT` de `src/main.py` se calcula como `Path(__file__).resolve().parent.parent`)

### Patrón de error handling orientado al usuario

**Fuente:** `src/main.py` (HTTPException con mensajes en español), `scripts/md-translate` (mensajes `>&2`)
**Aplica a:** `build-python-bundle.sh`

En el build script, los mensajes de error van a stderr y el script sale con código no-cero:
```bash
echo "ERROR: descripción accionable en español" >&2
exit 1
```
Los mensajes de progreso (no error) van a stdout con prefijo `→` (convención del RESEARCH.md).

### Patrón de env vars para configuración

**Fuente:** `src/main.py` lines 862–865 + `Dockerfile` lines 23–25
```python
host = os.getenv("HOST", "127.0.0.1")
port = int(os.getenv("PORT", "5400"))
```
```dockerfile
ENV HOST=0.0.0.0 PORT=5400 PYTHONUNBUFFERED=1
```
**Aplica a:** `ServerManager.swift` — Swift inyecta HOST y PORT como env vars en `Process.environment`. También inyectar `PYTHONDONTWRITEBYTECODE=1` (pitfall 2) y `PYTHONUNBUFFERED=1` (equivalente al Dockerfile).

### Patrón de health check en `/api/languages`

**Fuente:** `Dockerfile` line 32 + `src/main.py` lines 402–410
```python
@app.get("/api/languages", response_model=list[LanguageItem])
async def list_languages():
    return [LanguageItem(code="auto", name="Detectar automáticamente"), ...]
```
**Aplica a:** `ServerManager.swift` — `waitForHealthCheck` usa `GET /api/languages`. No requiere autenticación (sin `Depends(_require_api_token)`). Respuesta 200 con JSON array — suficiente verificar `statusCode == 200`.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `macos/MDTranslator.xcodeproj/project.pbxproj` | config | — | Fichero generado por Xcode; no existe ningún proyecto Swift en el repo |
| `macos/MDTranslator/MDTranslatorApp.swift` | provider | event-driven | No hay código Swift en el repo; análogo conceptual en `src/main.py` |
| `macos/MDTranslator/ServerManager.swift` | service | request-response | No hay código Swift en el repo; análogo conceptual en `src/main.py:run()` |
| `macos/MDTranslator/SplashView.swift` | component | event-driven | No hay código Swift/SwiftUI en el repo; análogo conceptual en startup feedback de `static/index.html` |

Para estos ficheros, el planner debe usar los patrones de RESEARCH.md directamente (patrones 2–6 verificados contra Apple Developer Documentation).

---

## Metadata

**Analog search scope:** `scripts/`, `src/`, `static/`, `Dockerfile`, `.gitignore`, `pyproject.toml`
**Files scanned:** 6 ficheros existentes leídos completos
**No Swift files found** en el repositorio — stack enteramente nuevo para la capa macOS
**Pattern extraction date:** 2026-06-03
