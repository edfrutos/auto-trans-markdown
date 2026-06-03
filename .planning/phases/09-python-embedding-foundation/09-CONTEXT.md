# Phase 9: Python Embedding Foundation - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Infraestructura base de la app macOS: script de build que embebe CPython standalone + código Swift mínimo que arranca el servidor FastAPI como subprocess, verifica que responde, y lo cierra limpiamente. No hay UI de traducción en esta fase — solo la capa de ciclo de vida del servidor.

**In scope:**
- `scripts/build-python-bundle.sh`: descarga CPython 3.11.15, instala deps desde `uv.lock`, verifica `import fastapi`
- Proyecto Xcode mínimo en `macos/` con App struct + `ServerManager` + `SplashView`
- Gestión del subprocess Python: arranque con puerto dinámico, health check, shutdown limpio (SIGTERM→SIGKILL)

**Out of scope (Phase 10+):**
- `NavigationSplitView`, sidebar, y UI completa de navegación
- Gestión de API keys en Keychain
- Endpoints de traducción en la UI Swift
- Cualquier funcionalidad de traducción en la app nativa

</domain>

<decisions>
## Implementation Decisions

### Dev Workflow
- **D-01:** `build-python-bundle.sh` se invoca **manualmente** una vez antes de compilar en Xcode. No hay Xcode build phase automática.
- **D-02:** El directorio `python-bundle/` en la raíz del repo va en `.gitignore` — no se versiona. README documenta el prerequisito.
- **D-03:** El script usa `uv pip install --target python-bundle/lib/python3.11/site-packages/` instalando desde `uv.lock` — absorbe los requisitos LOCK-01..05 de la fase 8 diferida.

### UI de Arranque
- **D-04:** Durante el startup del servidor se muestra una **ventana splash SwiftUI minimalista**: sin barra de título, `ProgressView` giratorio, texto "Iniciando..." centrado. Desaparece cuando el health check pasa.
- **D-05:** Si el health check falla tras los 15 s de timeout, se muestra un `.alert()` SwiftUI con dos botones: **"Reintentar"** (re-lanza el proceso) y **"Salir"** (`NSApp.terminate(nil)`).
- **D-06:** Diseño visual de la splash a criterio del implementador — coherente con macOS nativo (sin decoraciones extra, fondo del sistema).

### Scaffold Swift (Phase 9 mínimo)
- **D-07:** Phase 9 crea solo la estructura mínima: `@main App` struct + `ServerManager` (actor o class) + `SplashView` como `WindowGroup` principal. `NavigationSplitView` y el resto de la UI se añaden en Phase 10.
- **D-08:** Proyecto en `macos/MDTranslator.xcodeproj` — formato `.xcodeproj` tradicional (no Package.swift puro), compatible con Xcode 26.5.
- **D-09:** App name: **"MD Translator"** · Bundle ID: **`com.edefrutos.md-translator`** · Deployment target: **macOS 14.0**.

### Estructura del .app Bundle
- **D-10:** Intérprete Python en `Contents/Resources/python/` — accesible via `Bundle.main.resourceURL!.appendingPathComponent("python")`.
- **D-11:** Código fuente backend en `Contents/Resources/backend/` — Swift arranca uvicorn con `currentDirectoryURL = Resources/backend/`.
- **D-12:** Dependencias Python (site-packages) dentro del intérprete: `Resources/python/lib/python3.11/site-packages/`. No se usa carpeta separada ni `PYTHONPATH` extra.

### Claude's Discretion
- Tamaño exacto y padding de la ventana splash (sugerido: ~400×220 pt, sin barra de título, `NSWindowStyleMask.borderless`).
- Nombre del actor Swift para gestión del servidor (`ServerManager`, `PythonServerManager`, etc.).
- Patrón exacto de discover-port (bind socket a 0 → leer puerto → cerrar socket → pasar `--port N` a uvicorn).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/REQUIREMENTS.md` §BUNDLE — Requisitos BUNDLE-01..05 que esta fase implementa
- `.planning/ROADMAP.md` §Phase 9 — Goal, success criteria y dependencias de fase

### Key Decisions (pre-decididas)
- `.planning/STATE.md` §Accumulated Context → Key Decisions — CPython version, puerto dinámico, firma ad-hoc, lockfile absorbed

### v3.0 Stack Research
- `.planning/research/STACK.md` — Stack verificado: SwiftUI APIs mínimas, Foundation.Process snippet, python-build-standalone flavor, KeychainAccess SPM, Sparkle 2.9.2
- `.planning/milestones/v2.1-phases/08-reproducible-dependencies/08-RESEARCH.md` — Patrones de `uv pip install --target` y smoke test de `import fastapi`

### Existing Python Backend (read before touching build script)
- `src/main.py` — Entry point FastAPI; `run()` lee HOST/PORT de env; `load_dotenv()` se llama al importar (requiere CWD = directorio del proyecto)
- `pyproject.toml` — `requires-python = ">=3.11"`, dependencies list, console script `md-translate`
- `uv.lock` — lockfile que el build script debe consumir

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/main.py:run()` — arranca uvicorn en `HOST`/`PORT` leídos de env. En el bundle, PORT se inyecta como env var desde Swift (o como arg `--port`); HOST debe ser `127.0.0.1`.
- `uv.lock` — ya existe en el repo; el build script instala exactamente estas versiones.

### Established Patterns
- **Env vars para config**: el backend lee toda su config de variables de entorno. Swift inyecta PORT (y en Phase 10, API keys) via `Process.environment` — no hay que tocar `src/`.
- **load_dotenv() en import**: `src/main.py` llama `load_dotenv()` al importarse. En el bundle no hay `.env` — las claves vendrán de env vars inyectadas por Swift (Phase 10). Phase 9 no necesita API keys (solo verifica `GET /api/languages`).

### Integration Points
- Swift → Python: `Foundation.Process` con `executableURL = Resources/python/bin/python3`, `arguments = ["-m", "uvicorn", "src.main:app", "--port", "\(port)", "--host", "127.0.0.1", "--no-access-log"]`, `currentDirectoryURL = Resources/backend/`
- Swift health check: `URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/api/languages")!)` con retry cada 500 ms, timeout total 15 s
- Shutdown: `process.interrupt()` (SIGTERM); si en 5 s no ha terminado → `process.terminate()` (SIGKILL)

</code_context>

<specifics>
## Specific Ideas

- El build script debe emitir un **smoke test** explícito tras instalar: `python-bundle/bin/python3 -c "import fastapi; print('OK')"` — si falla, el script sale con código de error no-cero (BUNDLE-02).
- La ventana splash debe aparecer **antes** de que `ServerManager` lance el proceso (no después), para que el usuario nunca vea la app "congelada" sin feedback visual.
- El proyecto Xcode en `macos/` se crea desde cero en esta fase — no existe aún en el repo.

</specifics>

<deferred>
## Deferred Ideas

- `NavigationSplitView` completo con sidebar → Phase 10
- Gestión de API keys (Keychain, SecureField en Settings) → Phase 10
- Notificaciones de batch, glosario, TM → Phase 11
- Firma ad-hoc de `.dylib`/`.so` del bundle → Phase 12 (`make dmg`)
- Universal Binary (arm64+x86_64) → v3.1
- SSE streaming de progreso → v3.1

None — discussion stayed within phase 9 scope.

</deferred>

---

*Phase: 09-python-embedding-foundation*
*Context gathered: 2026-06-03*
