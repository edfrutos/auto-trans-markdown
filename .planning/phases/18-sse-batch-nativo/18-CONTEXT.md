# Phase 18: SSE Batch Nativo - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning

<domain>

## Phase Boundary

El lote nativo de la app macOS (MDTranslator) pasa del bucle síncrono actual (Phase 13: una llamada `POST /api/translate` por archivo) a consumir los **endpoints de jobs SSE ya existentes** del backend:

1. `POST /api/translate/batch/jobs` — crea el job
2. `GET /api/translate/batch/jobs/{id}/events` — stream SSE (`file_start`, `segment_progress`, `file_done`, `error`, `complete`)
3. `DELETE /api/translate/batch/jobs/{id}` — cancelación cooperativa
4. Descarga del ZIP de resultados al completar

Entregables: vista de lote nativa con progreso real archivo a archivo y por segmentos (SSE-01, SSE-02), botón Cancelar funcional (SSE-03), y Dock alimentado por eventos SSE en lugar del avance por índice actual (SSE-04).

**Sin cambios en el backend Python** — los endpoints, eventos y la cancelación cooperativa ya existen en `src/jobs.py` desde v2.0.

</domain>
<decisions>

## Implementation Decisions

### UI de progreso

- **D-01:** La vista de lote es una **sheet SwiftUI anclada a la ventana principal** (`.sheet()`), no un panel flotante ni un popover de barra de menú.
- **D-02:** Detalle mostrado: **barra global determinada** (archivos completados/total) + **nombre del archivo en curso** con su barra de progreso de segmentos (`segment_progress.done/total`) + contador. No se muestra lista completa de archivos durante el progreso.
- **D-03:** Al recibir `complete`, la sheet muestra un **resumen persistente** (N traducidos, M errores con sus mensajes) con botones **"Cerrar"** y **"Mostrar en Finder"**. No hay autocierre.
- **D-04:** La sheet incluye **"Continuar en segundo plano"**: se oculta, el job sigue, el Dock (SSE-04) muestra el progreso y al terminar llega la notificación de `NotificationManager`. Debe poder reabrirse/consultarse el estado mientras corre.

### Destino de resultados

- **D-05:** Al completar, la app **descarga el ZIP del job y lo extrae en la carpeta de salida** (la de `OutputManager`, fallback Descargas). Los `.md` quedan sueltos como en Phase 13; el ZIP es un detalle interno que se descarta tras extraer.
- **D-06:** Se extraen **solo los `.md` traducidos** — los sidecars `*.validation.json` y `errors.json` del ZIP NO se escriben en disco. Los errores se muestran en el resumen de la sheet.
- **D-07:** Colisiones de nombre: **sobrescribir** (comportamiento actual de `saveFileSilently`). Sin diálogos.

### Cancelación

- **D-08:** Al cancelar, **se conservan los archivos ya traducidos**: se descarga el ZIP parcial (el backend lo construye con los éxitos acumulados) y se extraen. El resumen indica "Cancelado: N de M traducidos".
- **D-09:** La cancelación es cooperativa (el archivo en curso termina antes de parar): al pulsar Cancelar el botón se deshabilita y la sheet muestra **"Cancelando — terminando archivo en curso…"** hasta recibir `complete` con `cancelled: true`. La UI nunca se cuelga (criterio de éxito #2).
- **D-10:** Si el usuario sale de la app (⌘Q) con un lote en curso: **alert de confirmación** "Hay un lote en curso (N de M archivos). ¿Salir y cancelarlo?" con Salir/Continuar. El servidor Python muere al salir, así que el job no puede sobrevivir al cierre.

### Entrada del lote

- **D-11:** Dos puntos de entrada: el **arrastre al Dock** existente (Phase 13) y una nueva entrada de menú **File → "Traducir lote…"** con `NSOpenPanel` multi-selección (añadir en `Commands.swift`).
- **D-12:** **Un solo idioma destino**: `defaultTargetLang` de Ajustes (UserDefaults), como hoy. El jobs API soporta multi-idioma pero la selección multi-idioma nativa queda fuera — la web UI ya cubre ese caso.
- **D-13:** El `NSAlert` de confirmación de Phase 13 se **sustituye por la propia sheet en estado "preparado"**: lista de archivos, idioma destino y botón "Traducir". Un único componente para confirmar + progreso + resumen.

### Claude's Discretion

- Arquitectura Swift interna del cliente SSE (parser de `URLSession.bytes`, actor/observable del estado del job, etc.)
- Manejo de reconexión/errores de red del stream SSE
- Detalles visuales de la sheet (espaciado, tipografía) siguiendo el estilo existente de SettingsView/SplashView

</decisions>

<canonical_refs>

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Backend (no tocar — solo consumir)

- `src/jobs.py` — Jobs de lote asíncronos: estados (`JobState`), eventos SSE exactos (`file_start`, `segment_progress`, `file_done`, `error`, `complete` con sus payloads), cancelación cooperativa (`cancel_requested`), ZIP final (`job.zip_bytes`)
- `src/main.py` — Endpoints HTTP del jobs API: `POST /api/translate/batch/jobs`, `GET .../events` (SSE), `DELETE .../{id}`, descarga del ZIP (409 si el job sigue en curso)
- `src/batch_zip.py` — Contenido del ZIP: `.md` traducidos + `*.validation.json` por archivo + `errors.json` si hubo fallos (relevante para D-06: extraer solo `.md`)
- `.planning/REQUIREMENTS.md` §SSE — Requisitos SSE-01..04 literales

### App macOS (código a modificar/reutilizar)

- `macos/MDTranslator/MDTranslator/AppDelegate.swift` — Flujo batch actual de Phase 13 (`confirmAndBatch`, `batchTranslate`, `callTranslateAPI`) que esta fase sustituye; `application(_:open:)` se mantiene
- `macos/MDTranslator/MDTranslator/DockProgressManager.swift` — API `showProgress(current:total:)`, `setBadge(_:)`, `hideProgress()` — se alimentará de eventos SSE (SSE-04)
- `macos/MDTranslator/MDTranslator/OutputManager.swift` — `saveFileSilently` (carpeta bookmarked, fallback Descargas, sobrescribe), `revealOutputFolder()`
- `macos/MDTranslator/MDTranslator/NotificationManager.swift` — Notificación al terminar (se mantiene para el modo segundo plano)
- `macos/MDTranslator/MDTranslator/Commands.swift` — Donde añadir File → "Traducir lote…" (D-11)
- `macos/MDTranslator/MDTranslator/ServerManager.swift` — `serverPort` y `state == .running` como precondición de cualquier llamada al API

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- `DockProgressManager` (Phase 13): ya dibuja barra determinada sobre el Dock tile + badge — solo cambia la fuente de datos (eventos SSE en vez de índice del bucle)
- `OutputManager.saveFileSilently`: guardado con security-scoped bookmark y fallback a Descargas — reutilizable para los `.md` extraídos del ZIP
- `NotificationManager.sendTranslationDone`: notificación de fin de lote — se mantiene
- `ServerManager` (`@Observable @MainActor`): patrón de estado observable a imitar para el estado del job

### Established Patterns

- Swift 6 + macOS 14: `@Observable` macro (NO `ObservableObject`), `@State` en vistas, `@MainActor` en managers
- Views en ficheros `.swift` separados; lógica en managers singleton (`*.shared`) — la nueva vista de lote y el cliente SSE deben seguir este patrón
- Llamadas HTTP con `URLSession` nativo y `127.0.0.1:{serverPort}` — el cliente SSE usará `URLSession.shared.bytes(for:)`
- Mensajes de UI nativa en español (alerts, botones de AppDelegate)

### Integration Points

- `AppDelegate.application(_:open:)` → rama multi-archivo: hoy llama `confirmAndBatch` → pasará a abrir la sheet en estado "preparado" (D-13)
- La sheet vive en la jerarquía SwiftUI de `MDTranslatorApp`/`ContentView` — AppDelegate necesita un puente (p. ej. notificación o estado compartido observable) para pedirle a la UI que abra la sheet con las URLs
- `unzip`: Foundation no trae API pública de ZIP — decidir en research entre `Process` + `/usr/bin/unzip` (la app ya no está sandboxed) o parser ZIP mínimo en Swift

</code_context>

<specifics>
## Specific Ideas

- El flujo debe sentirse como una operación nativa de macOS: sheet estándar, sin ventanas extra, Dock como indicador secundario cuando la sheet está oculta
- "Cancelar" debe comunicar honestamente la semántica cooperativa del backend ("Cancelando — terminando archivo en curso…"), nunca aparentar cancelación instantánea
- El coste de API ya pagado no se tira: cancelar conserva lo traducido (D-08)

</specifics>

<deferred>
## Deferred Ideas

- **Multi-idioma destino en el lote nativo** — el jobs API ya lo soporta (`target_langs`); si se quiere paridad con la web, es una fase/extensión futura (D-12 lo deja fuera)
- **Drag & drop de varios `.md` sobre la ventana principal** como tercera entrada del lote — descartado de esta fase (D-11)
- **Lista completa de archivos con estado individual en la sheet** — descartada en favor de la vista compacta (D-02); podría reconsiderarse para lotes muy grandes

</deferred>

---

*Phase: 18-SSE Batch Nativo*
*Context gathered: 2026-06-12*
