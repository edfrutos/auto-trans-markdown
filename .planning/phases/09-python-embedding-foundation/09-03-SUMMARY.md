# Plan 09-03 — SUMMARY
## Swift: ServerManager, health check, splash screen

**Estado:** COMPLETADO  
**Fecha:** 2026-06-07 / 2026-06-08

---

## Archivos creados / modificados

| Archivo | Estado |
|---------|--------|
| `macos/MDTranslator/MDTranslator/ServerManager.swift` | NUEVO |
| `macos/MDTranslator/MDTranslator/SplashView.swift` | NUEVO |
| `macos/MDTranslator/MDTranslator/AppDelegate.swift` | NUEVO |
| `macos/MDTranslator/MDTranslator/MDTranslatorApp.swift` | REEMPLAZADO (boilerplate Xcode) |

---

## Funcionalidades implementadas

### ServerManager (`@MainActor @Observable`)
- `findFreePort()` — socket BSD, bind(port=0), getsockname, CFSwapInt16BigToHost
- `start()` async — lanza python3 con `-m uvicorn src.main:app`
- `waitForHealthCheck(port:)` — GET `/api/languages`, retry 500ms, timeout 15s
- `stop()` — SIGINT → SIGKILL diferido 5s
- Limpieza de procesos huérfanos en `init()` via `/tmp/md-translator-python.pid`
- Log de salida uvicorn en `NSTemporaryDirectory()/md-translator-server.log`

### SplashView
- Spinner + texto "Iniciando servidor..."
- `.task { await serverManager.start() }` al aparecer la vista
- Alert con "Reintentar" / "Salir" cuando `state == .failed`

### AppDelegate
- `applicationWillTerminate` → `serverManager?.stop()` + `Thread.sleep(1.0)`
- Referencia compartida desde `MDTranslatorApp.body` via `delegate.serverManager = serverManager`

### MDTranslatorApp
- `@NSApplicationDelegateAdaptor(AppDelegate.self)`
- `@State private var serverManager = ServerManager()` (migrado de @StateObject/@Observable)
- Conmuta entre `SplashView` y `Text("Main UI — Phase 10")` según `state`

---

## Problemas encontrados y soluciones

| Problema | Causa | Solución |
|----------|-------|----------|
| `ObservableObject` no conforme con `@MainActor class` | Swift 6 strict concurrency | Migrar a `@Observable` macro (macOS 14+); `@State` en vez de `@StateObject` |
| `/tmp/md-translator-server.log` no creado | App Sandbox bloqueaba escritura | Eliminar App Sandbox (ya resuelto en 09-02) |
| uvicorn arranca pero cae inmediatamente | `p.environment` reemplazado completamente eliminaba `HOME`, `TMPDIR`, `PATH`, etc. | Heredar `ProcessInfo.processInfo.environment` y sobreescribir solo las vars necesarias |
| Health check timeout 15s aunque server OK | Causado por entorno insuficiente (mismo root cause anterior) | Ídem |

---

## Verificación de aceptación

- [x] App arranca → spinner visible brevemente
- [x] Tras ~1-2s aparece "Main UI — Phase 10"
- [x] `ps aux | grep uvicorn` muestra proceso hijo durante ejecución
- [x] ⌘Q → shutdown limpio: `ps aux | grep uvicorn` devuelve vacío en <6s
- [x] Log de uvicorn en `$TMPDIR/md-translator-server.log`

---

## Pitfalls documentados (para fases siguientes)

1. **`p.environment` debe heredar el entorno del proceso padre** — nunca reemplazar completamente o Python pierde HOME/TMPDIR y los subprocesos fallan con getcwd errors.
2. **App Sandbox incompatible con subprocess externo** — eliminar para desarrollo; revisar si se necesita App Store distribution en fases futuras.
3. **Run Script "Based on dependency analysis"** — desactivar siempre para scripts de copia que no declaran inputs/outputs.
4. **`@Observable` vs `ObservableObject`** — usar `@Observable` en Swift 6 con `@MainActor class`; `@State` en lugar de `@StateObject`.
