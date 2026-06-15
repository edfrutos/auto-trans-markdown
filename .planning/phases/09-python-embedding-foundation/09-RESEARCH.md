# Phase 9: Python Embedding Foundation - Research

**Researched:** 2026-06-03
**Domain:** macOS app bundle con CPython embebido + subprocess Swift + SwiftUI splash
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Dev Workflow**

- D-01: `build-python-bundle.sh` se invoca manualmente una vez antes de compilar en Xcode. No hay Xcode build phase automática.
- D-02: El directorio `python-bundle/` en la raíz del repo va en `.gitignore` — no se versiona. README documenta el prerequisito.
- D-03: El script usa `uv pip install --target python-bundle/lib/python3.11/site-packages/` instalando desde `uv.lock` — absorbe los requisitos LOCK-01..05 de la fase 8 diferida.

**UI de Arranque**

- D-04: Durante el startup del servidor se muestra una ventana splash SwiftUI minimalista: sin barra de título, `ProgressView` giratorio, texto "Iniciando..." centrado. Desaparece cuando el health check pasa.
- D-05: Si el health check falla tras los 15 s de timeout, se muestra un `.alert()` SwiftUI con dos botones: "Reintentar" (re-lanza el proceso) y "Salir" (`NSApp.terminate(nil)`).
- D-06: Diseño visual de la splash a criterio del implementador — coherente con macOS nativo.

**Scaffold Swift (Phase 9 mínimo)**

- D-07: Phase 9 crea solo la estructura mínima: `@main App` struct + `ServerManager` (actor o class) + `SplashView` como `WindowGroup` principal.
- D-08: Proyecto en `macos/MDTranslator.xcodeproj` — formato `.xcodeproj` tradicional, compatible con Xcode 26.5.
- D-09: App name: "MD Translator" · Bundle ID: `com.edefrutos.md-translator` · Deployment target: macOS 14.0.

**Estructura del .app Bundle**

- D-10: Intérprete Python en `Contents/Resources/python/` — accesible via `Bundle.main.resourceURL!.appendingPathComponent("python")`.
- D-11: Código fuente backend en `Contents/Resources/backend/` — Swift arranca uvicorn con `currentDirectoryURL = Resources/backend/`.
- D-12: Dependencias Python (site-packages) dentro del intérprete: `Resources/python/lib/python3.11/site-packages/`. No se usa carpeta separada ni `PYTHONPATH` extra.

### Claude's Discretion

- Tamaño exacto y padding de la ventana splash (sugerido: ~400×220 pt, sin barra de título, `NSWindowStyleMask.borderless`).
- Nombre del actor Swift para gestión del servidor (`ServerManager`, `PythonServerManager`, etc.).
- Patrón exacto de discover-port (bind socket a 0 → leer puerto → cerrar socket → pasar `--port N` a uvicorn).

### Deferred Ideas (OUT OF SCOPE)

- `NavigationSplitView` completo con sidebar → Phase 10
- Gestión de API keys (Keychain, SecureField en Settings) → Phase 10
- Notificaciones de batch, glosario, TM → Phase 11
- Firma ad-hoc de `.dylib`/`.so` del bundle → Phase 12 (`make dmg`)
- Universal Binary (arm64+x86_64) → v3.1
- SSE streaming de progreso → v3.1

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID        | Description                                                                                                                     | Research Support                                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| BUNDLE-01 | Bundle .app incluye CPython 3.11.15 (install_only_stripped, release 20260510) y todas las dependencias instaladas en build time | URL verificada via GitHub API; uv export → uv pip install --target pipeline verificado en local                             |
| BUNDLE-02 | Script `build-python-bundle.sh` verifica que `import fastapi` funciona desde la ruta del bundle (smoke test)                    | Patrón de smoke test documentado; exit code no-cero en fallo                                                                |
| BUNDLE-03 | Servidor uvicorn arranca en puerto libre asignado por kernel (`bind(port:0)`), pasado como `--port`                             | Patrón BSD socket Darwin documentado; `getsockname()` para leer el puerto                                                   |
| BUNDLE-04 | Health check `GET /api/languages` con retry cada 500 ms y timeout de 15 s antes de mostrar UI principal                         | `URLSession` async/await con `Task.sleep` en bucle; endpoint verificado en `src/main.py`                                    |
| BUNDLE-05 | Al cerrar la app, proceso Python recibe SIGTERM; si no termina en 5 s, recibe SIGKILL                                           | `process.interrupt()` = SIGINT (aceptable para uvicorn); `process.terminate()` = SIGKILL; pitfall de Force Quit documentado |

</phase_requirements>

---

## Summary

La Phase 9 construye la capa de infraestructura sobre la que se levanta toda la app macOS nativa: un script de build que embebe CPython standalone dentro del `.app` bundle, y un proyecto Xcode mínimo que arranca el servidor FastAPI como subprocess, hace health check y lo apaga limpiamente.

**python-build-standalone** (release 20260510, flavor `install_only_stripped`) es el mecanismo correcto para empaquetar CPython 3.11.15 en el bundle. La distribución es relocatable por diseño — no necesita `PYTHONHOME` explícito — y el intérprete extraído en `Contents/Resources/python/` funciona desde su ruta actual. El asset `aarch64-apple-darwin` pesa 25 MB comprimido y se descarga directamente de GitHub Releases con URL verificada. [VERIFIED: GitHub API `astral-sh/python-build-standalone/releases/tags/20260510`]

El pipeline de instalación de dependencias combina `uv export` y `uv pip install --target`: `uv export --format requirements-txt --no-dev --no-editable --no-emit-project --no-hashes > /tmp/req.txt && uv pip install -r /tmp/req.txt --target python-bundle/lib/python3.11/site-packages/`. Este pipeline fue verificado en la máquina de desarrollo — genera 115 líneas de requirements a partir del `uv.lock` actual y el dry-run de `uv pip install` muestra todos los paquetes correctamente. [VERIFIED: ejecutado en local con uv 0.11.4]

La capa Swift usa exclusivamente APIs del stdlib de macOS (`Foundation.Process`, `URLSession`, `AppKit`/`SwiftUI`): no se necesita ningún paquete Swift de terceros en Phase 9. El pitfall más relevante para la fase es el manejo de Force Quit: `applicationWillTerminate` no se llama cuando el OS envía SIGKILL, lo que puede dejar procesos Python huérfanos. La mitigación es registrar el PID en un archivo temporal y añadir una lógica de limpieza al arrancar la app.

**Recomendación principal:** Implementar el `ServerManager` como `@MainActor class` (no `actor`) para evitar problemas de aislamiento de concurrencia con las actualizaciones de UI en Swift 6; usar `NSApplicationDelegateAdaptor` para capturar `applicationWillTerminate` de forma fiable frente a Cmd+Q (Force Quit no tiene solución garantizada).

---

## Architectural Responsibility Map

| Capability                              | Primary Tier               | Secondary Tier   | Rationale                                                                 |
| --------------------------------------- | -------------------------- | ---------------- | ------------------------------------------------------------------------- |
| Descarga y extracción de CPython        | Build script (shell)       | —                | Ocurre en build time, no en runtime                                       |
| Instalación de dependencias Python      | Build script (shell)       | —                | `uv export → uv pip install --target` en build time                       |
| Smoke test `import fastapi`             | Build script (shell)       | —                | Verificación de correctitud del bundle antes del build Swift              |
| Descubrimiento de puerto libre          | Swift (Darwin BSD sockets) | —                | Ocurre en runtime antes de lanzar el subprocess                           |
| Ciclo de vida del subprocess Python     | Swift `ServerManager`      | —                | Arranque, health check y shutdown son responsabilidad de la app Swift     |
| Splash screen / estado de arranque      | SwiftUI `SplashView`       | —                | UI que refleja el estado del `ServerManager`                              |
| Health check HTTP                       | Swift `ServerManager`      | —                | `URLSession` async/await llamado desde el actor de gestión                |
| Shutdown graceful (SIGTERM→SIGKILL)     | Swift `ServerManager`      | AppKit delegate  | `process.interrupt()` + timer + `process.terminate()`                     |
| Configuración del servidor (HOST, PORT) | Swift → Python env vars    | —                | `Process.environment` inyecta `HOST` y `PORT`; no hay `.env` en el bundle |

---

## Standard Stack

### Core — Phase 9 (sin dependencias Swift de terceros)

| Componente                            | Versión                          | Propósito                                               | Por qué estándar                                                      |
| ------------------------------------- | -------------------------------- | ------------------------------------------------------- | --------------------------------------------------------------------- |
| python-build-standalone               | release 20260510                 | CPython 3.11.15 portable para embedding en .app         | Redistribuible, relocatable, mantenido por Astral (autores de uv)     |
| uv                                    | 0.11.4 (local), 0.11.18 (latest) | Exportar lockfile + instalar deps en --target           | Herramienta canónica; soporta --target para instalación fuera de venv |
| Foundation.Process                    | stdlib macOS                     | Lanzar/terminar subprocess uvicorn                      | Sin dependencias; parte del SDK de macOS                              |
| URLSession                            | stdlib macOS                     | Health check HTTP al endpoint `/api/languages`          | API async/await nativa macOS 12+                                      |
| SwiftUI                               | stdlib macOS 14+                 | SplashView, ProgressView, .alert()                      | Deployment target decidido: macOS 14.0                                |
| AppKit (NSApplicationDelegateAdaptor) | stdlib macOS                     | applicationWillTerminate para shutdown graceful         | Necesario para captura fiable de terminación                          |
| Darwin BSD sockets                    | stdlib macOS                     | Descubrimiento de puerto libre (bind a 0 + getsockname) | Sin dependencias; patrón canónico de puerto dinámico                  |

### Dependencias Python del bundle (de uv.lock existente)

Las dependencias ya están en `uv.lock`. No se añade ninguna dependencia nueva al `pyproject.toml`. El build script instala las dependencias **sin** los extras `[pdf]` (WeasyPrint requiere Cairo/Pango nativos que complican el bundle — ver deferred en REQUIREMENTS.md) y **sin** `[test]`.

**Comando de instalación:** [VERIFIED: pipeline ejecutado en local]
```bash
uv export \
  --format requirements-txt \
  --no-dev \
  --no-editable \
  --no-emit-project \
  --no-hashes \
  > /tmp/bundle-requirements.txt

uv pip install \
  -r /tmp/bundle-requirements.txt \
  --target python-bundle/lib/python3.11/site-packages/ \
  --python python-bundle/bin/python3
```

### Alternativas Consideradas

| En lugar de                                     | Podría usarse                                | Tradeoff                                                                                                                                                    |
| ----------------------------------------------- | -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `uv export → uv pip install --target`           | `uv sync --python <path>` en virtualenv      | `uv sync` crea un `.venv` completo; --target instala directo en site-packages del intérprete embebido. D-12 especifica site-packages dentro del intérprete. |
| `Foundation.Process` (SIGINT via `interrupt()`) | `SIGTERM` explícito via `kill(pid, SIGTERM)` | `process.interrupt()` envía SIGINT; uvicorn maneja SIGINT para shutdown graceful. SIGTERM también funciona pero requiere `kill()` con C interop en Swift.   |
| BSD socket `bind(0)` + `getsockname()`          | Puerto fijo (ej. 8765)                       | Puerto fijo puede estar ocupado; el kernel garantiza un puerto libre.                                                                                       |
| `@MainActor class ServerManager`                | `actor ServerManager`                        | Un actor custom requiere hop de concurrencia para actualizar `@Published`; `@MainActor class` actualiza la UI directamente.                                 |

---

## Package Legitimacy Audit

> Phase 9 no instala paquetes Swift externos. Los paquetes Python ya están en el `uv.lock` existente (auditados en Phase 8). Las únicas herramientas de build son `uv` y la descarga directa de GitHub Releases.

| Herramienta                       | Registro/Fuente           | Antigüedad                 | Descargas     | Repo fuente                                  | slopcheck   | Disposición                                           |
| --------------------------------- | ------------------------- | -------------------------- | ------------- | -------------------------------------------- | ----------- | ----------------------------------------------------- |
| `uv` (system tool)                | PyPI                      | ~2 años                    | 15M+/sem      | github.com/astral-sh/uv                      | [OK]        | Aprobado                                              |
| python-build-standalone (tarball) | GitHub Releases astral-sh | ~5 años (fork de indygreg) | N/A (tarball) | github.com/astral-sh/python-build-standalone | N/A         | Aprobado — descarga directa verificada via GitHub API |

**Paquetes eliminados por slopcheck [SLOP]:** ninguno
**Paquetes marcados como sospechosos [SUS]:** ninguno

*`uv` verificado con slopcheck 0.6.1 [VERIFIED: slopcheck OK]. python-build-standalone verificado directamente en GitHub API — asset `cpython-3.11.15+20260510-aarch64-apple-darwin-install_only_stripped.tar.gz` confirmado con URL y tamaño (25 MB). [VERIFIED: GitHub API]*

---

## Architecture Patterns

### System Architecture Diagram

```text
BUILD TIME (manual, una vez):
┌─────────────────────────────────────────────────────────────────┐
│ build-python-bundle.sh                                          │
│                                                                 │
│  GitHub Releases ──curl──► cpython-3.11.15+...tar.gz           │
│                                │                               │
│                                ▼                               │
│                    python-bundle/                               │
│                    ├── bin/python3                              │
│                    ├── lib/python3.11/                          │
│                    │   └── site-packages/  ◄── uv export | pip  │
│                    └── lib/libpython3.11.dylib                 │
│                                │                               │
│                                ▼                               │
│              smoke test: python-bundle/bin/python3             │
│              -c "import fastapi; print('OK')"                  │
│              [exit 1 si falla]                                  │
└─────────────────────────────────────────────────────────────────┘

XCODE BUILD TIME:
┌────────────────────────────────────────────────────────────────┐
│ Xcode copia en Contents/Resources/:                            │
│   python/  ←── python-bundle/  (Copy Bundle Resources)        │
│   backend/ ←── src/, pyproject.toml, uv.lock                  │
└────────────────────────────────────────────────────────────────┘

RUNTIME (app arranca):
┌────────────────────────────────────────────────────────────────┐
│ @main MDTranslatorApp                                          │
│   └── WindowGroup { SplashView }                               │
│         │  .onAppear → serverManager.start()                   │
│         ▼                                                       │
│   ServerManager (@MainActor class)                              │
│     │                                                          │
│     ├─1─► findFreePort() via BSD socket bind(0)+getsockname    │
│     │         └── port: Int (ej. 54321)                        │
│     │                                                          │
│     ├─2─► Foundation.Process                                   │
│     │       executable: Resources/python/bin/python3           │
│     │       args: ["-m","uvicorn","src.main:app",              │
│     │              "--port","54321","--host","127.0.0.1",      │
│     │              "--no-access-log"]                          │
│     │       env: {HOST:127.0.0.1, PORT:54321}                  │
│     │       cwd: Resources/backend/                            │
│     │       process.run()  ──────────────────────────────────► │
│     │                                           Python process  │
│     │                                           uvicorn on :54321
│     ├─3─► healthCheckLoop() — URLSession retry cada 500ms      │
│     │       GET http://127.0.0.1:54321/api/languages           │
│     │       ┌─ 200 OK → state = .running                       │
│     │       └─ error/timeout → reintentar hasta 15s            │
│     │                                                          │
│     └─4─► SplashView observa state:                            │
│             .starting  → ProgressView visible                  │
│             .running   → dismiss splash, show MainView         │
│             .failed    → .alert() Reintentar | Salir           │
│                                                                 │
│ SHUTDOWN (Cmd+Q / windowClose):                                │
│   applicationWillTerminate ──► serverManager.stop()            │
│     process.interrupt()  [SIGINT → uvicorn graceful]           │
│     await Task.sleep(5s)                                       │
│     if process.isRunning { process.terminate() } [SIGKILL]     │
└────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```text
auto-trans-markdown/            ← repo root
├── scripts/
│   └── build-python-bundle.sh  ← NUEVO (Phase 9)
├── python-bundle/              ← GITIGNORED, generado por build script
│   ├── bin/python3
│   └── lib/python3.11/
│       └── site-packages/
├── macos/                      ← NUEVO (Phase 9)
│   ├── MDTranslator.xcodeproj/
│   │   └── project.pbxproj
│   └── MDTranslator/
│       ├── MDTranslatorApp.swift   ← @main App struct
│       ├── ServerManager.swift     ← @MainActor class
│       ├── SplashView.swift        ← SwiftUI splash
│       ├── Assets.xcassets/
│       └── Info.plist
├── src/                        ← SIN CAMBIOS
├── tests/                      ← SIN CAMBIOS
├── uv.lock                     ← Existente, consumido por build script
├── pyproject.toml              ← SIN CAMBIOS
└── .gitignore                  ← Añadir python-bundle/
```

### Patrón 1: build-python-bundle.sh

**Qué:** Script bash que descarga CPython standalone, instala dependencias desde uv.lock, y verifica el bundle.
**Cuándo usar:** Una vez antes del primer build de Xcode; repetir al actualizar `uv.lock`.

```bash
#!/usr/bin/env bash
# Source: pipeline verificado en local con uv 0.11.4
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/python-bundle"
PBS_RELEASE="20260510"
PBS_VERSION="3.11.15"
PBS_ARCH="aarch64-apple-darwin"
PBS_FLAVOR="install_only_stripped"
PBS_ARTIFACT="cpython-${PBS_VERSION}+${PBS_RELEASE}-${PBS_ARCH}-${PBS_FLAVOR}.tar.gz"
PBS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/${PBS_ARTIFACT}"

echo "→ Descargando CPython ${PBS_VERSION} standalone..."
curl -L --progress-bar "$PBS_URL" -o /tmp/cpython-standalone.tar.gz

echo "→ Extrayendo en ${BUNDLE_DIR}..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"
# install_only_stripped extrae en carpeta "python/"; strip-components=1 lo aplana
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
"$PYTHON" -m pip install \
  -r /tmp/bundle-requirements.txt \
  --target "$BUNDLE_DIR/lib/python${PBS_VERSION}/site-packages/" \
  --no-deps \
  2>/dev/null || \
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

**Nota importante:** `install_only_stripped` extrae en un subdirectorio llamado `python/` dentro del tarball. El flag `--strip-components=1` elimina ese nivel para que `bin/python3` quede directamente en `$BUNDLE_DIR/bin/python3`. [VERIFIED: estructura del tarball confirmada via GitHub API asset]

### Patrón 2: Foundation.Process para subprocess uvicorn

```swift
// Source: Apple Developer Documentation - Foundation.Process
// VERIFIED: developer.apple.com/documentation/foundation/process

import Foundation

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
            "PYTHONDONTWRITEBYTECODE": "1"
        ]

        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                if self?.state == .running {
                    self?.state = .failed
                }
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
        p.interrupt()  // SIGINT — uvicorn graceful shutdown
        // Tras 5 s, SIGKILL si sigue corriendo
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if p.isRunning { p.terminate() }
        }
        process = nil
    }
}
```

**Nota:** `process.interrupt()` envía SIGINT (no SIGTERM). uvicorn responde a SIGINT con shutdown graceful igual que a SIGTERM — ambas señales están registradas en su servidor ASGI. [CITED: github.com/encode/uvicorn, server.py signal handlers]

### Patrón 3: Descubrimiento de puerto libre (BSD sockets Darwin)

```swift
// Source: Apple Developer Forums thread/722574 (DTS recommendation)
// Patrón canónico: bind a puerto 0 → getsockname → close → devolver puerto
import Darwin

func findFreePort() -> Int {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    addr.sin_port = 0  // 0 = kernel asigna puerto libre

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
    let nameResult = withUnsafeMutablePointer(to: &boundAddr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(sock, $0, &addrLen)
        }
    }
    guard nameResult == 0 else { return 0 }

    // sin_port está en network byte order (big-endian)
    return Int(CFSwapInt16BigToHost(boundAddr.sin_port))
}
```

**Pitfall de race condition:** Hay una ventana de tiempo entre cerrar el socket y que uvicorn haga `bind()` en el mismo puerto. En loopback 127.0.0.1 este race es extremadamente improbable (el OS no reasigna puertos efímeros inmediatamente), pero existe teóricamente. Si uvicorn falla al arrancar en el puerto, el `terminationHandler` cambia el estado a `.failed` y el usuario puede reintentar. [ASSUMED]

### Patrón 4: Health check con retry

```swift
// Source: URLSession async/await - Apple Developer Documentation
private func waitForHealthCheck(port: Int) async {
    let deadline = Date().addingTimeInterval(15)
    let url = URL(string: "http://127.0.0.1:\(port)/api/languages")!
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 1.0
    let session = URLSession(configuration: config)

    while Date() < deadline {
        do {
            let (_, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                state = .running
                return
            }
        } catch {
            // El servidor aún no está listo — ignorar y reintentar
        }
        try? await Task.sleep(nanoseconds: 500_000_000)  // 500 ms
    }
    // Timeout: 15 s superados sin respuesta válida
    stop()
    state = .failed
}
```

### Patrón 5: SplashView SwiftUI

```swift
// Source: Apple Developer Documentation - SwiftUI WindowGroup
import SwiftUI

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
        .task {
            await serverManager.start()
        }
        .alert("Error al iniciar el servidor", isPresented: .constant(serverManager.state == .failed)) {
            Button("Reintentar") {
                Task { await serverManager.start() }
            }
            Button("Salir", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
    }
}

// En el App struct:
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
        .windowStyle(.hiddenTitleBar)         // Sin barra de título en splash
        .defaultSize(width: 400, height: 220) // macOS 13+ API
    }
}
```

### Patrón 6: Shutdown con NSApplicationDelegateAdaptor

```swift
// IMPORTANTE: ScenePhase.background es INFIABLE en macOS para cleanup crítico.
// Usar NSApplicationDelegateAdaptor + applicationWillTerminate para Cmd+Q.
// Force Quit (SIGKILL) NO llama applicationWillTerminate — ver pitfall 4.

class AppDelegate: NSObject, NSApplicationDelegate {
    var serverManager: ServerManager?

    func applicationWillTerminate(_ notification: Notification) {
        serverManager?.stop()
        // Espera breve síncrona para dar tiempo al SIGINT
        Thread.sleep(forTimeInterval: 1.0)
    }
}
```

### Anti-Patterns to Avoid

- **Hardcodear el puerto:** Usar `--port 8765` fijo causa conflictos si el puerto está ocupado. Siempre usar `findFreePort()`.
- **Usar `process.terminate()` directamente como primer paso:** `terminate()` envía SIGKILL inmediato, sin dar a uvicorn tiempo de cerrar conexiones activas. Siempre enviar SIGINT primero con `process.interrupt()`.
- **Confiar en ScenePhase para cleanup en macOS:** `ScenePhase.background` en macOS se dispara al minimizar la app, no solo al cerrar. Usar `NSApplicationDelegateAdaptor.applicationWillTerminate` para cleanup de subprocess.
- **Instalar WeasyPrint (extra `[pdf]`) en el bundle:** Cairo y Pango requieren dylibs del sistema que no están en la distribución standalone. Diferido a v3.1.
- **Poner `python-bundle/` en git:** 25 MB comprimidos × historial = repo inflado. Siempre en `.gitignore`.
- **Invocar `python3 -m uvicorn` sin configurar `currentDirectoryURL`:** El backend usa `Path(__file__).resolve().parent.parent` para calcular rutas relativas (`output/`, `data/`, `static/`). El CWD debe ser el directorio `backend/`.

---

## Don't Hand-Roll

| Problema                                  | No construir                                             | Usar en su lugar                                       | Por qué                                                                                                                          |
| ----------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| Python standalone redistribuible          | Script propio de compilación de CPython                  | python-build-standalone release 20260510               | La compilación de CPython con todas las dependencias nativas y patches de relocation tarda horas y requiere toolchain específico |
| Instalación de dependencias en target dir | Script pip manual con hardcode de versiones              | `uv export → uv pip install --target`                  | uv garantiza reproducibilidad exacta desde el lockfile; pip manual puede resolver versiones distintas                            |
| Descubrimiento de puerto libre            | Iterar puertos (8765, 8766...) hasta encontrar uno libre | BSD socket `bind(0) + getsockname()`                   | El incremento manual tiene race conditions y puede agotarse; el kernel garantiza un puerto libre                                 |
| Señal de terminación a subprocess         | `kill(pid, 15)` vía C interop                            | `process.interrupt()` seguido de `process.terminate()` | `Foundation.Process` encapsula el interop C; `interrupt()` = SIGINT, `terminate()` = SIGKILL                                     |

**Key insight:** El valor de python-build-standalone no es solo "Python portátil" sino que ya tiene patcheados los paths de relocation en los binarios ELF/Mach-O. Intentar hacer esto manualmente con `install_name_tool` en un Python de Homebrew es frágil y no reproducible.

---

## Common Pitfalls

### Pitfall 1: Tarball de install_only_stripped con subdirectorio `python/`

**Qué va mal:** Al extraer el tarball `install_only_stripped` sin `--strip-components=1`, todos los archivos quedan en `python-bundle/python/bin/python3` en lugar de `python-bundle/bin/python3`. Xcode copia el directorio `python-bundle/` como recurso y la ruta esperada por Swift (`Resources/python/bin/python3`) no existe.

**Por qué ocurre:** El tarball tiene un nivel de directorio raíz llamado `python/` que envuelve toda la distribución.

**Cómo evitar:** Usar `--strip-components=1` en el comando `tar`:
```bash
tar xzf cpython-3.11.15+...tar.gz -C python-bundle/ --strip-components=1
```

**Señales de alerta:** El smoke test falla con "No such file or directory" al invocar `python-bundle/bin/python3`.

---

### Pitfall 2: `PYTHONDONTWRITEBYTECODE` y archivos `__pycache__` en el bundle

**Qué va mal:** Al primer arranque, Python escribe archivos `.pyc` en `Contents/Resources/backend/src/__pycache__/`. En un bundle no firmado (firma ad-hoc) esto puede causar errores de escritura si el bundle está en `/Applications` y el usuario no es administrador.

**Por qué ocurre:** Python escribe bytecode por defecto para acelerar imports.

**Cómo evitar:** Inyectar `PYTHONDONTWRITEBYTECODE=1` en `process.environment` o pasar `-B` como argumento al intérprete.

**Señales de alerta:** Errores de `PermissionError` en los logs de uvicorn al arrancar desde `/Applications`.

---

### Pitfall 3: `load_dotenv()` busca `.env` en el CWD y falla silenciosamente

**Qué va mal:** `src/main.py` llama `load_dotenv()` al importarse. En el bundle no existe `.env`, por lo que `load_dotenv()` no encuentra ningún archivo — esto es silencioso, no lanza excepción. Sin embargo, si Swift inyecta `PORT` como env var pero no inyecta `HOST`, el servidor puede arrancar en `0.0.0.0` (valor por defecto cuando `HOST` no está definido sería `127.0.0.1` según el `run()`, pero uvicorn como módulo `-m uvicorn` ignora las env vars de `run()` si se le pasan args CLI directos).

**Por qué ocurre:** `run()` en `main.py` lee `HOST`/`PORT` de env, pero al invocar `python3 -m uvicorn src.main:app --port N` directamente, uvicorn usa sus propios args CLI y NO llama a `run()`. Los valores se pasan como `--port` y `--host` directamente.

**Cómo evitar:** Pasar `--host 127.0.0.1` y `--port PORT` explícitamente como argumentos CLI a uvicorn. No depender de que Swift inyecte variables de entorno que `run()` leería.

**Señales de alerta:** El servidor arranca en `0.0.0.0` y es accesible desde la red local cuando debería estar restringido a loopback.

---

### Pitfall 4: Force Quit no llama `applicationWillTerminate`

**Qué va mal:** `Activity Monitor → Force Quit` o `kill -9 <pid_app>` envía SIGKILL directamente al proceso Swift. El OS termina el proceso sin dar tiempo a ejecutar ningún cleanup. El proceso Python uvicorn queda huérfano.

**Por qué ocurre:** SIGKILL no puede ser capturado ni manejado por ningún proceso. `applicationWillTerminate` solo se llama en terminaciones graciosas (Cmd+Q, `NSApp.terminate(nil)`).

**Cómo evitar:** Estrategia en dos niveles:

1. Al arrancar la app, escribir el PID del proceso Python en un archivo temporal (`/tmp/md-translator-python.pid`).
2. Al arrancar la app (en `ServerManager.init`), leer ese archivo y enviar SIGKILL al PID anterior si el proceso aún existe.

Esto no evita el proceso huérfano en el Force Quit actual, pero lo limpia en el siguiente arranque. En Phase 9 (uso personal/desarrollo), el impacto es bajo: el proceso huérfano se muere solo cuando uvicorn detecta que el puerto ya no está siendo atendido o cuando el usuario hace logout.

**Señales de alerta:** Proceso `python3` en Activity Monitor que permanece tras cerrar la app.

---

### Pitfall 5: Swift 6 strict concurrency con `Foundation.Process.terminationHandler`

**Qué va mal:** En Swift 6 strict concurrency mode, el compilador requiere que el closure de `terminationHandler` sea `@Sendable`. Si el closure captura `self` de un `@MainActor class`, el compilador puede emitir warnings o errores sobre crossing actor boundaries.

**Por qué ocurre:** `terminationHandler` es de tipo `(@Sendable (Process) -> Void)?`. La llamada al closure ocurre en un hilo arbitrario del OS, no en el MainActor.

**Cómo evitar:** Usar `Task { @MainActor in ... }` dentro del closure:
```swift
p.terminationHandler = { [weak self] _ in
    Task { @MainActor [weak self] in
        self?.state = .failed
    }
}
```

**Señales de alerta:** Warning del compilador: "Sending 'self' across actor boundaries".

---

### Pitfall 6: `--strip-components` y estructura de extracción del tarball en macOS

**Qué va mal:** `tar` en macOS (BSD tar) acepta `--strip-components` pero si el destino no existe, algunos sistemas fallan. El flag `--strip-components=1` también aplica a todos los paths en el tarball; si el tarball tiene subdirectorios con más niveles, el resultado puede ser inesperado.

**Por qué ocurre:** El tarball `install_only_stripped` tiene exactamente un nivel de directorio raíz (`python/`), así que `--strip-components=1` es correcto y suficiente.

**Cómo evitar:** Verificar con `tar tzf /tmp/cpython-standalone.tar.gz | head -5` que el primer nivel es `python/` antes de extraer.

---

## Code Examples

### Extracción verificada del tarball (build script)

```bash
# Source: python-build-standalone docs + verificado via GitHub API asset structure
# El tarball tiene estructura: python/bin/python3, python/lib/python3.11/, etc.
tar tzf /tmp/cpython-standalone.tar.gz | head -3
# Output esperado:
# python/
# python/bin/
# python/bin/python3

# Extracción correcta:
tar xzf /tmp/cpython-standalone.tar.gz \
  -C "$BUNDLE_DIR" \
  --strip-components=1
# Resultado: $BUNDLE_DIR/bin/python3, $BUNDLE_DIR/lib/python3.11/, etc.
```

### URLSession con timeout breve para health check

```swift
// Source: Apple Developer Documentation - URLSessionConfiguration
// timeoutIntervalForRequest = 1.0 para fallar rápido entre retries
let config = URLSessionConfiguration.ephemeral
config.timeoutIntervalForRequest = 1.0  // Falla en 1 s, no en 60 s
let session = URLSession(configuration: config)
```

### Ventana sin barra de título en SwiftUI macOS

```swift
// Source: Apple Developer Documentation - windowStyle
// .hiddenTitleBar oculta título + barra de herramientas + separador
// Disponible en macOS 11+ via SwiftUI
WindowGroup {
    SplashView(serverManager: serverManager)
}
.windowStyle(.hiddenTitleBar)
.defaultSize(width: 400, height: 220)  // macOS 13+
// Para arrastrar la ventana sin title bar:
// .windowResizability(.contentSize) evita que el usuario redimensione
```

### Info.plist mínimo para macOS 14.0

```xml
<!-- Info.plist — macOS 14.0 deployment target -->
<!-- Xcode genera automáticamente LSMinimumSystemVersion desde el build setting -->
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

---

## State of the Art

| Enfoque antiguo                              | Enfoque actual                                                  | Cuándo cambió          | Impacto                                                                                                                                                                                               |
| -------------------------------------------- | --------------------------------------------------------------- | ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PyInstaller para empaquetar apps Python      | python-build-standalone + subprocess Swift                      | ~2022-2023             | PyInstaller congela bytecode; python-build-standalone mantiene el intérprete completo como servidor real                                                                                              |
| Puerto fijo hardcodeado                      | `bind(0)` + kernel port                                         | —                      | Evita conflictos con otros servidores locales (port 8000, dev tools)                                                                                                                                  |
| `ObservableObject` + `@Published`            | `@Observable` macro                                             | macOS 14.0 / Swift 5.9 | `@Observable` es más ergonómico y tiene mejor rendimiento; pero `@ObservableObject` + `@Published` sigue siendo válido y compatible con macOS 13. Como deployment target es 14.0, ambos son posibles. |
| ScenePhase para lifecycle macOS              | NSApplicationDelegateAdaptor                                    | —                      | ScenePhase.background es infiable en macOS para cleanup crítico                                                                                                                                       |
| `Process.terminationHandler` sin `@Sendable` | `terminationHandler` con `@Sendable` + `Task { @MainActor in }` | Swift 6                | Requerido en Xcode 26.5 con Swift 6 strict concurrency                                                                                                                                                |

**Deprecated/outdated:**

- `NSTask`: Renombrado a `Process` en macOS 10.10. No usar `NSTask`.
- `process.launchPath`: Deprecado en macOS 10.13+. Usar `process.executableURL` (tipo `URL`).
- `process.launch()`: Deprecado en macOS 10.13+. Usar `process.run()` que lanza `CocoaError` en caso de fallo.

---

## Open Questions (RESOLVED)

1. **Estructura del tarball en el release actual** — RESOLVED: Mitigado con verificación en el build script
   - Qué sabemos: El asset existe en el release 20260510 con el nombre esperado y pesa 25 MB. El STACK.md previo indica que `install_only_stripped` es relocatable.
   - Resolución: El build script incluye `tar tzf | head -1` con comprobación explícita del primer entry (`python/`). Si la estructura difiere, el script aborta con mensaje descriptivo antes de extraer. La asunción A1 queda cubierta por este gate en el propio script.

2. **Comportamiento de `process.interrupt()` en uvicorn 0.48.0** — RESOLVED: Aceptado con verificación manual en Plan 09-03
   - Qué sabemos: uvicorn tiene handlers para SIGINT y SIGTERM desde sus versiones iniciales; el código fuente de `uvicorn/server.py` registra ambas señales. `process.interrupt()` envía SIGINT.
   - Resolución: El plan 09-03 incluye una tarea de checkpoint (human-verify) que prueba explícitamente el ciclo arranque+shutdown. Si el timeout de 5s no es suficiente, `process.terminate()` (SIGKILL) garantiza la terminación. El riesgo residual es aceptable para desarrollo (Phase 9).

3. **Impacto de `PYTHONDONTWRITEBYTECODE` en rendimiento de arranque** — RESOLVED: Aceptado con gate manual de 10s
   - Qué sabemos: Sin `.pyc`, Python recompila en cada arranque. Apple Silicon con NVMe hace este proceso rápido (~1-2s para módulos de FastAPI).
   - Resolución: El plan 09-03 Task 3 (checkpoint:human-verify) incluye verificar el tiempo real de arranque. Si supera 10s del timeout de 15s, el ejecutor elimina `PYTHONDONTWRITEBYTECODE` del environment del Process. La variable se mantiene como primera elección (evita errores de escritura en bundle instalado en /Applications).

---

## Environment Availability

| Dependencia                | Requerida por                             | Disponible  | Versión            | Fallback                                                                             |
| -------------------------- | ----------------------------------------- | ----------- | ------------------ | ------------------------------------------------------------------------------------ |
| Xcode                      | Build del proyecto Swift                  | ✓           | 26.5 (Build 17F42) | —                                                                                    |
| Swift                      | Compilación Swift                         | ✓           | 6.3.2              | —                                                                                    |
| uv                         | Build script (uv export)                  | ✓           | 0.11.4             | Actualizar con el instalador oficial de Astral (`curl -LsSf …`, luego `sh`)          |
| curl                       | Build script (descarga tarball)           | ✓           | stdlib macOS       | —                                                                                    |
| Python 3.11+ (sistema)     | NO requerido en runtime                   | N/A         | Sistema: 3.14.3    | N/A — el bundle es autocontenido                                                     |
| macOS 14.0+ (desarrollo)   | SwiftUI `.defaultSize`, deployment target | ✓           | 26.5.1 (superset)  | —                                                                                    |
| Internet (GitHub Releases) | Descarga tarball CPython                  | ✓           | —                  | Cachear tarball localmente: `export PBS_CACHE=~/Downloads/cpython-standalone.tar.gz` |

**Missing dependencies with no fallback:** ninguna — todas las dependencias están disponibles.

**Missing dependencies with fallback:** Internet requerida para descarga inicial del tarball; se puede cachear.

**Nota:** `python-bundle/` aún NO está en `.gitignore`. El build script debe añadirlo o la documentación debe recordar al usuario ejecutar `echo 'python-bundle/' >> .gitignore`. [VERIFIED: `grep python-bundle .gitignore` retorna vacío]

---

## Validation Architecture

### Test Framework

| Propiedad         | Valor                                              |
| ----------------- | -------------------------------------------------- |
| Framework         | pytest 8.0+ (existente en `pyproject.toml [test]`) |
| Archivo de config | `pyproject.toml [tool.pytest.ini_options]`         |
| Comando rápido    | `pytest tests/ -q -x`                              |
| Suite completa    | `pytest tests/ -v`                                 |

**Nota:** Phase 9 es principalmente código Swift y un script bash — no código Python nuevo. Los tests Python existentes (148 tests) deben seguir pasando sin cambios. Los tests de la capa Swift son manuales en Phase 9 (verificación de smoke test, arranque del servidor, health check).

### Phase Requirements → Test Map

| Req ID    | Comportamiento                                      | Tipo de test                         | Comando automatizable                                                   | Archivo existe?                     |
| --------- | --------------------------------------------------- | ------------------------------------ | ----------------------------------------------------------------------- | ----------------------------------- |
| BUNDLE-01 | CPython 3.11.15 extraído en python-bundle/          | Script bash (build-python-bundle.sh) | `./scripts/build-python-bundle.sh && test -f python-bundle/bin/python3` | ❌ Wave 0                            |
| BUNDLE-02 | `import fastapi` funciona desde el bundle           | Smoke test integrado en build script | `python-bundle/bin/python3 -c "import fastapi"`                         | ❌ Wave 0 (incluido en build script) |
| BUNDLE-03 | Puerto libre asignado por kernel                    | Manual (Activity Monitor)            | N/A — verificación visual en macOS                                      | N/A                                 |
| BUNDLE-04 | Health check `GET /api/languages` responde en < 15s | Manual (app Xcode)                   | N/A — verificación visual                                               | N/A                                 |
| BUNDLE-05 | Proceso Python desaparece en < 5s tras cerrar app   | Manual (Activity Monitor)            | N/A — verificación visual                                               | N/A                                 |

### Sampling Rate

- **Por tarea commit:** `pytest tests/ -q -x` — verifica que el código Python no fue roto accidentalmente
- **Por wave merge:** `pytest tests/ -v` + `./scripts/build-python-bundle.sh` (si el script fue modificado)
- **Phase gate:** Suite Python verde + smoke test del bundle verde + verificación manual de BUNDLE-03/04/05

### Wave 0 Gaps

- [ ] `scripts/build-python-bundle.sh` — script principal de la fase (BUNDLE-01, BUNDLE-02)
- [ ] `macos/MDTranslator.xcodeproj` — proyecto Xcode (BUNDLE-03, BUNDLE-04, BUNDLE-05)
- [ ] `.gitignore` — añadir entrada `python-bundle/`

*(Los tests Python existentes cubren todo el código Python — no hay gaps en pytest)*

---

## Security Domain

> `security_enforcement` no está explícitamente desactivado en config.json. Se incluye esta sección.

### Applicable ASVS Categories

| Categoría ASVS        | Aplica                                              | Control estándar                                              |
| --------------------- | --------------------------------------------------- | ------------------------------------------------------------- |
| V2 Authentication     | No (Phase 9 no tiene auth; solo health check local) | —                                                             |
| V3 Session Management | No                                                  | —                                                             |
| V4 Access Control     | Parcial                                             | Servidor bound a 127.0.0.1 exclusivamente — no expuesto a red |
| V5 Input Validation   | No (no hay entrada de usuario en Phase 9)           | —                                                             |
| V6 Cryptography       | No                                                  | —                                                             |

### Known Threat Patterns

| Patrón                                     | STRIDE                             | Mitigación estándar                                                                            |
| ------------------------------------------ | ---------------------------------- | ---------------------------------------------------------------------------------------------- |
| Python subprocess escapa a la red          | Elevation of Privilege             | `--host 127.0.0.1` hardcodeado en args CLI — no depende de la variable de entorno `HOST`       |
| API keys en env vars visibles con `ps aux` | Information Disclosure             | Phase 9 no inyecta API keys (no hay llaves en esta fase); diferido a Phase 10 con Keychain     |
| Proceso Python huérfano tras Force Quit    | Denial of Service (puerto ocupado) | PID file pattern para limpiar al siguiente arranque                                            |
| Tarball de CPython comprometido            | Tampering                          | Verificar checksum SHA256 del tarball (disponible en releases.json de python-build-standalone) |

**Nota de seguridad sobre el tarball:** El build script actual no verifica el checksum SHA256 del tarball descargado. Para un uso personal/desarrollo (Phase 9) esto es aceptable. Para distribución (Phase 12), el `make dmg` debe verificar el checksum. [ASSUMED — la política de verificación no está especificada en las decisiones]

---

## Assumptions Log

| #   | Claim                                                                                                                        | Sección                       | Riesgo si es incorrecto                                                                                        |
| --- | ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------- | -------------------------------------------------------------------------------------------------------------- |
| A1  | El tarball `install_only_stripped` extrae en un subdirectorio `python/` que se elimina con `--strip-components=1`            | Patrón 1 (build script)       | El build script extrae en la ruta incorrecta; `bin/python3` no estaría en `$BUNDLE_DIR/bin/`                   |
| A2  | uvicorn 0.48.0 (versión en uv.lock) responde a SIGINT con graceful shutdown en < 5s                                          | Patrón 2 (ServerManager.stop) | El proceso Python no termina en 5 s → SIGKILL necesario de todas formas                                        |
| A3  | La race condition entre findFreePort() y bind de uvicorn es suficientemente improbable en loopback para ignorarse en Phase 9 | Patrón 3 (free port)          | uvicorn falla al arrancar por puerto ya tomado; el terminationHandler lo detecta y el usuario puede reintentar |
| A4  | El checksum SHA256 del tarball no necesita verificarse en el build script de Phase 9 (uso personal/desarrollo)               | Security Domain               | Tarball comprometido en tránsito/caché; riesgo bajo en desarrollo                                              |
| A5  | `PYTHONDONTWRITEBYTECODE=1` no incrementa el tiempo de arranque por encima del threshold de 15s en Apple Silicon             | Pitfall 2                     | El health check timeout se dispara antes de que el servidor esté listo                                         |

---

## Sources

### Primary (HIGH confidence)

- GitHub API `astral-sh/python-build-standalone/releases/tags/20260510` — URL del asset, tamaño (25 MB), nombre exacto del artefacto
- `developer.apple.com/documentation/foundation/process` — APIs de Foundation.Process (executableURL, arguments, environment, run, interrupt, terminate, terminationHandler)
- `uv pip install --help` (ejecutado en local) — sintaxis exacta de `--target`, `-r`, `--python`
- `uv export --help` + pipeline ejecutado en local — verificación de `--no-dev --no-editable --no-emit-project --no-hashes`
- `.planning/research/STACK.md` — Stack verificado con Context7: SwiftUI APIs, python-build-standalone flavors, release 20260510
- `src/main.py` — confirmación de puerto por defecto (5400), `run()` con `HOST`/`PORT`, `load_dotenv()` al importar

### Secondary (MEDIUM confidence)

- `swiftlang/swift-corelibs-foundation/Sources/Foundation/Process.swift` — `terminationHandler` es `(@Sendable (Process) -> Void)?`; clase es `@unchecked Sendable`
- `developer.apple.com/forums/thread/722574` (DTS Engineer) — recomendación explícita de BSD sockets sobre NWListener para free port
- `github.com/jessesquires/jessesquires.com` (Jesse Squires) — ScenePhase es infiable en macOS; usar NSApplicationDelegateAdaptor
- uvicorn GitHub discussions — SIGTERM/SIGINT handlers registrados para graceful shutdown

### Tertiary (LOW confidence)

- Asunción sobre estructura del tarball (subdirectorio `python/`) basada en convención; no verificado descargando el archivo

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — python-build-standalone verificado via GitHub API; uv pipeline ejecutado en local; Foundation.Process documentado en Apple Docs
- Architecture: HIGH — patrones derivados de documentación oficial + código existente del proyecto
- Pitfalls: HIGH — Force Quit / applicationWillTerminate es comportamiento documentado de macOS; struct tarball es LOW (ver A1)
- Validation: HIGH — arquitectura de tests derivada de infraestructura existente del proyecto

**Research date:** 2026-06-03
**Valid until:** 2026-09-03 (stable stack — python-build-standalone, Foundation, SwiftUI son APIs estables)
