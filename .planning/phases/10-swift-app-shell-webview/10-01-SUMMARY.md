# Plan 10-01 — SUMMARY
## WKWebView: embeber la UI web existente

**Estado:** COMPLETADO  
**Fecha:** 2026-06-08

---

## Archivos creados / modificados

| Archivo                                                 | Estado                                           |
| ------------------------------------------------------- | ------------------------------------------------ |
| `macos/MDTranslator/MDTranslator/WebView.swift`         | NUEVO                                            |
| `macos/MDTranslator/MDTranslator/MDTranslatorApp.swift` | MODIFICADO                                       |
| `macos/MDTranslator/MDTranslator/ServerManager.swift`   | MODIFICADO (`serverPort` private → private(set)) |

---

## Funcionalidades implementadas

### WebView (`NSViewRepresentable`)

- Carga `http://127.0.0.1:{serverPort}` al aparecer la vista running.
- `developerExtrasEnabled = true` — inspector web disponible en desarrollo (clic derecho → Inspeccionar).
- `WKNavigationDelegate` (`Coordinator`):
  - `didFailProvisionalNavigation` / `didFail` → página de error inline con botón "Reintentar".
  - `decidePolicyFor` → links `target="_blank"` se abren en el navegador del sistema via `NSWorkspace`.
- Escucha `WebView.reloadNotification` → `webView.reload()` (publicada desde `Commands.swift`).
- Escucha `WebView.openMarkdownNotification` → inyecta contenido en el textarea del editor vía JS `evaluateJavaScript`.
- Limpieza de observers (`deinit` del Coordinator).

### MDTranslatorApp

- Usa `WebView` cuando `state == .running`; `SplashView` en cualquier otro estado.
- `WindowGroup(id: "main")` — macOS persiste el frame entre reinicios.
- Dimensiones: splash 400×220 → WebView 1100×720.
- Transición animada con `.animation(.easeInOut(duration: 0.3), value: ...)`.
- `.commands { AppCommands(...) }` integrado (Plan 10-02).

### ServerManager

- `serverPort` cambiado de `private` a `private(set)` para ser legible desde `MDTranslatorApp` y `WebView`.

---

## Notas de implementación

- La UI web en `static/` no requirió cambios — es agnóstica de host.
- El `updateNSView` solo recarga si el host/puerto cambiaron (no ocurre en condiciones normales).
- La inyección de Markdown vía JS usa `getElementById('editor')` con fallback a `querySelector('textarea')`.

---

## Criterios de aceptación

- [x] `WebView.swift` creado con `NSViewRepresentable`
- [x] `MDTranslatorApp` usa `WebView` cuando `state == .running`
- [x] Dimensiones splash→WebView correctas (400×220 → 1100×720)
- [x] `serverPort` accesible desde fuera de `ServerManager`
- [x] `WindowGroup(id: "main")` para persistencia de frame
