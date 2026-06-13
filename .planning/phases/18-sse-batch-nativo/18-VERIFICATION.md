---
phase: 18-sse-batch-nativo
verified: 2026-06-13T11:45:32Z
status: human_needed
score: 6/6
overrides_applied: 0
human_verification:
  - test: "Arrastrar 3+ archivos .md al icono del Dock con el servidor en marcha"
    expected: "BatchSheet se abre en estado .prepared mostrando la lista de archivos y el idioma destino; al pulsar Traducir el stream SSE arranca y las barras de progreso avanzan archivo a archivo"
    why_human: "Requiere app corriendo con servidor Python activo y archivos .md reales; no verificable con grep ni tests unitarios"
  - test: "Pulsar Cancelar mientras el lote está en curso"
    expected: "El botón se deshabilita, aparece el texto 'Cancelando — terminando archivo en curso…' (estado .cancelling), y la sheet pasa a .done con cancelled:true al recibir el evento complete del stream"
    why_human: "La secuencia cooperativa DELETE → SSE complete{cancelled:true} → .done requiere backend real en marcha"
  - test: "Usar el menú Traducir lote… (⌘⇧B) con varios .md seleccionados"
    expected: "NSOpenPanel multi-selección se abre; al confirmar se abre la BatchSheet en estado .prepared con los archivos seleccionados"
    why_human: "Interacción con panel de sistema; no ejercitable sin entorno gráfico"
  - test: "Cerrar la sheet con 'Continuar en segundo plano' y comprobar el Dock tile"
    expected: "La barra de progreso determinada sobre el icono del Dock avanza con cada archivo (file_done); el badge muestra el total inicial; al terminar desaparece la barra y llega una notificación macOS"
    why_human: "Comportamiento visual del Dock tile; solo verificable en runtime"
  - test: "Salir con ⌘Q mientras hay un lote en curso"
    expected: "Aparece el alert 'Hay un lote en curso (N de M archivos)' con botones 'Salir y cancelar' y 'Continuar en segundo plano'"
    why_human: "Flujo de terminación de app; requiere runtime con job activo"
---

# Phase 18: SSE Batch Nativo — Verification Report

**Phase Goal:** El lote en la app macOS muestra progreso real archivo a archivo y permite cancelar, usando los endpoints SSE existentes del backend.
**Verified:** 2026-06-13T11:45:32Z
**Status:** human_needed
**Re-verification:** No — verificacion inicial

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SSE-01: el cliente Swift conecta al endpoint `/api/translate/batch/jobs/{id}/events` usando `URLSession.shared.bytes(for:)` | VERIFIED | `BatchJobManager.swift` L218: `let (bytes, response) = try await URLSession.shared.bytes(for: request)` apuntando a `http://127.0.0.1:{port}/api/translate/batch/jobs/{jobId}/events` con cabecera `Accept: text/event-stream`. El backend expone este endpoint en `src/main.py` L759 con `StreamingResponse` real (lee de `asyncio.Queue`, no array vacío). |
| 2 | SSE-02: la barra de progreso determinada avanza con `filesDone/filesTotal` provenientes de eventos SSE reales | VERIFIED | `BatchJobManager.swift` L272–294: `handleSSELine` incrementa `filesDone` en cada evento `file_done` o `error`, y lee `filesTotal` del payload `file_start`. `BatchSheet.swift` L211: `ProgressView(value: Double(manager.filesDone), total: Double(max(manager.filesTotal, 1)))` — la barra lee directamente del observable del manager, no de datos hardcodeados. |
| 3 | SSE-03: el botón Cancelar envía DELETE a `/api/translate/batch/jobs/{id}` | VERIFIED | `BatchJobManager.swift` L107–114: `cancel()` hace transición a `.cancelling` y llama `sendDelete(jobId:port:)`. `sendDelete` (L329–334) construye `URLRequest` con `httpMethod = "DELETE"` a `http://127.0.0.1:{port}/api/translate/batch/jobs/{jobId}`. El backend tiene `@app.delete("/api/translate/batch/jobs/{job_id}")` en `src/main.py` L776. La cancelación es cooperativa (el stream sigue activo hasta recibir `complete{cancelled:true}`). |
| 4 | SSE-04: el Dock tile muestra progreso determinado durante el job, alimentado por eventos SSE | VERIFIED | `BatchJobManager.swift` L144: `DockProgressManager.shared.showProgress(current:0, total:urls.count)` al arrancar. L286 y L294: `showProgress(current: filesDone, total: filesTotal)` en cada `file_done` y `error`. L303: `hideProgress()` y `setBadge(nil)` al recibir `complete`. `DockProgressManager.swift` L25: fallback `CGSize(width:128, height:128)` cuando `tile.size == .zero`. |
| 5 | Los artefactos nuevos de Phase 18 están cableados en la jerarquía SwiftUI (sheet presentada, notificaciones escuchadas) | VERIFIED | `MDTranslatorApp.swift` L72–90: `.sheet(isPresented: $showBatchSheet)` presenta `BatchSheet` con `manager: BatchJobManager.shared`; `.onReceive(.openBatchSheet)` activa `showBatchSheet = true`. `AppDelegate.swift` L168–171: `openBatchSheet(_ urls:)` llama `BatchJobManager.shared.prepareWith(urls:)` y posta `.openBatchSheet`. `Commands.swift` L135: `openBatchFiles()` posta `.openBatchSheet` con las URLs. |
| 6 | Los métodos de Phase 13 (`confirmAndBatch`, `batchTranslate`, `callTranslateAPI`) han sido eliminados de AppDelegate | VERIFIED | `grep -c "confirmAndBatch\|batchTranslate\|callTranslateAPI" AppDelegate.swift` devuelve `0`. El método `application(_:open:)` reutilizado de Phase 13 ahora llama `openBatchSheet(_:)` para lotes multi-archivo. |

**Score:** 6/6 truths verificadas en codebase

---

### Required Artifacts

| Artifact | Expected | Status | Detalles |
|----------|----------|--------|----------|
| `BatchJobManager.swift` | Singleton `@Observable @MainActor`, `URLSession.bytes`, enum `BatchJobState` (5 estados), `prepareWith`, `cancel`, `start` | VERIFIED | 409 líneas, todos los requisitos presentes. Incluye `createJob` (POST multipart), `runSSEStream` (bytes loop), `handleSSELine` (switch sobre 5 tipos de evento), `sendDelete`, `downloadAndExtractZIP`, `extractMarkdownFiles`. |
| `BatchSheet.swift` | Vista `BatchSheet: View`, referencia a `manager.jobState`, `ProgressView` | VERIFIED | 263 líneas. Switch sobre `manager.jobState` con ramas `.prepared`, `.running`, `.cancelling`, `.done`, `default`. `ProgressView` determinada en L211 y L224. |
| `AppDelegate.swift` | Contiene `openBatchSheet`, `NSEvent.addLocalMonitorForEvents`; NO contiene `confirmAndBatch` ni `batchTranslate` | VERIFIED | `openBatchSheet` en L168; `NSEvent.addLocalMonitorForEvents` en L55 (D-10 via ⌘Q); cero ocurrencias de los métodos de Phase 13. |
| `MDTranslatorApp.swift` | Contiene `showBatchSheet`, `.onReceive(.openBatchSheet)` | VERIFIED | `showBatchSheet` en L16; `.onReceive(.openBatchSheet)` en L88; `.sheet` presentando `BatchSheet` en L72. |
| `DockProgressManager.swift` | Fallback `CGSize(width:128, height:128)` para `tile.size == .zero` | VERIFIED | L25: `let size = rawSize == .zero ? CGSize(width: 128, height: 128) : rawSize`. |
| `Commands.swift` | Contiene `Notification.Name.openBatchSheet` y `openBatchFiles()` | VERIFIED | `openBatchFiles()` en L120; `Notification.Name.openBatchSheet` definido en L160; menú "Traducir lote…" con `⌘⇧B` en L34. |

---

### Key Link Verification

| From | To | Via | Status | Detalles |
|------|----|-----|--------|----------|
| `Commands.openBatchFiles()` | `BatchSheet` (MDTranslatorApp) | `NotificationCenter.post(.openBatchSheet)` → `.onReceive` → `showBatchSheet = true` | WIRED | Cadena completa verificada |
| `AppDelegate.application(_:open:)` | `BatchSheet` | `openBatchSheet(_ urls:)` → `prepareWith` + `post(.openBatchSheet)` | WIRED | L138–144 AppDelegate, L168–171 |
| `BatchSheet` botón Traducir | `BatchJobManager.start(port:targetLang:)` | `Task { await manager.start(...) }` | WIRED | BatchSheet.swift L86–88 |
| `BatchJobManager.start` | Backend `POST /api/translate/batch/jobs` | `createJob(urls:targetLang:port:)` → `URLSession.data(for:)` | WIRED | L186–202 |
| `BatchJobManager.runSSEStream` | Backend `GET .../events` | `URLSession.shared.bytes(for:)` → `bytes.lines` | WIRED | L218–230 |
| `handleSSELine(file_done)` | `DockProgressManager.showProgress` | llamada directa en L286 | WIRED | SSE-04 cableado |
| `BatchJobManager.cancel()` | Backend `DELETE .../jobs/{id}` | `sendDelete(jobId:port:)` → `URLRequest(httpMethod:DELETE)` | WIRED | L329–334 |
| Backend `GET .../events` | `asyncio.Queue` de `jobs.py` | `_job_event_stream` yield desde `event_queue.get()` | WIRED | `src/main.py` L748–756 — datos reales, no array vacío |

---

### Data-Flow Trace (Level 4)

| Artifact | Variable de datos | Fuente | Produce datos reales | Status |
|----------|-------------------|--------|----------------------|--------|
| `BatchSheet` → `ProgressView` | `manager.filesDone`, `manager.filesTotal` | Eventos `file_done`/`file_start` del stream SSE → `handleSSELine` → propiedades `@Observable` | Si — incremento por evento, no hardcodeado | FLOWING |
| `BatchSheet` → texto archivo en curso | `manager.currentFile` | Evento `file_start.filename` en `handleSSELine` L272 | Si — del payload SSE | FLOWING |
| `DockProgressManager` barra | `current/total` pasados en `showProgress` | `filesDone`/`filesTotal` del BatchJobManager | Si — misma cadena SSE | FLOWING |
| Backend SSE stream | eventos en cola | `asyncio.Queue` alimentada por `start_batch_job` en `jobs.py` | Si — `event_queue.put(event)` desde el procesado real de archivos | FLOWING |

---

### Behavioral Spot-Checks

| Comportamiento | Comando | Resultado | Status |
|----------------|---------|-----------|--------|
| Suite de tests Python (148) sin regresion | `uv run pytest tests/ -q` | `148 passed, 3 warnings in 1.04s` | PASS |
| Endpoint SSE existe y retorna stream real | `grep "_job_event_stream" src/main.py` | Función generadora que hace `yield` desde `event_queue.get()` — no array vacío | PASS |
| DELETE endpoint para cancelación existe | `grep "@app.delete.*batch/jobs" src/main.py` | `@app.delete("/api/translate/batch/jobs/{job_id}")` L776 | PASS |
| Métodos Phase 13 eliminados de AppDelegate | `grep -c "confirmAndBatch\|batchTranslate\|callTranslateAPI" AppDelegate.swift` | `0` | PASS |

---

### Probe Execution

Step 7c: SKIPPED — no hay probes declarados en los PLAN.md de esta fase ni scripts `probe-*.sh` en el directorio de phase.

---

### Requirements Coverage

| Requirement | Plan | Descripcion | Status | Evidencia |
|-------------|------|-------------|--------|-----------|
| SSE-01 | 18-01 | Cliente SSE conecta al endpoint `/api/translate/batch/jobs/{id}/events` | SATISFIED | `URLSession.shared.bytes(for:)` en `BatchJobManager.runSSEStream` L218 |
| SSE-02 | 18-02 | Barra de progreso determinada avanza con `filesDone/filesTotal` | SATISFIED | `ProgressView(value: Double(manager.filesDone), total: ...)` en `BatchSheet` L211; datos de eventos `file_done` reales |
| SSE-03 | 18-01 | Botón Cancelar envía DELETE | SATISFIED | `cancel()` → `sendDelete` → `httpMethod = "DELETE"` en `BatchJobManager` L332 |
| SSE-04 | 18-01/03 | Dock tile con progreso determinado durante el job | SATISFIED | `DockProgressManager.showProgress` llamado desde `handleSSELine` en `file_done` y `error`; fallback `CGSize(128,128)` presente |

---

### Anti-Patterns Found

| Archivo | Linea | Patron | Severidad | Impacto |
|---------|-------|--------|-----------|---------|
| `BatchJobManager.swift` | L333 | `_ = try? await URLSession.shared.data(for: request)` (resultado DELETE ignorado) | Info | Intencional y documentado — el stream SSE confirma la cancelacion via `complete{cancelled:true}`; ignorar el resultado HTTP del DELETE es el diseno correcto |
| `AppDelegate.swift` | L96 | `Thread.sleep(forTimeInterval: 1.0)` en `applicationWillTerminate` | Info | Patron heredado de fase anterior para dar tiempo al shutdown del servidor Python; no es un stub |

Sin `TBD`, `FIXME`, `XXX` sin referenciar en ningun archivo modificado por esta fase. Sin placeholders ni `return null`/`return []` en rutas criticas.

---

### Human Verification Required

Los 6 must-haves estan verificados en codebase. La fase requiere confirmacion humana de los flujos interactivos que no son ejercitables con grep ni tests unitarios:

#### 1. Flujo SSE completo end-to-end

**Test:** Arrastrar 3+ archivos `.md` al icono del Dock con el servidor en marcha (app arrancada, servidor Python activo).
**Expected:** BatchSheet se abre en estado `.prepared` con la lista de archivos y el idioma de Ajustes. Al pulsar "Traducir", la barra global avanza archivo a archivo y el nombre del archivo en curso se actualiza. Al terminar, la sheet muestra el resumen con el boton "Mostrar en Finder" y los archivos `.md` aparecen en la carpeta de salida configurada.
**Why human:** Requiere app corriendo con servidor Python activo y archivos `.md` reales con contenido traducible.

#### 2. Cancelacion cooperativa

**Test:** Iniciar un lote de 5+ archivos y pulsar "Cancelar" a mitad.
**Expected:** El boton "Cancelar" se deshabilita, aparece el mensaje "Cancelando — terminando archivo en curso…". Cuando llega `complete{cancelled:true}`, la sheet pasa a `.done` indicando "Cancelado: N de M traducidos". Los archivos ya traducidos estan disponibles en la carpeta de salida (ZIP parcial extraido).
**Why human:** La secuencia cooperativa `DELETE` → SSE `complete{cancelled:true}` → `.done` requiere backend real con job en marcha.

#### 3. Entrada desde menu (⌘⇧B)

**Test:** Con el servidor en marcha, usar el menu Traducir lote... (⌘⇧B) y seleccionar varios `.md` en el `NSOpenPanel`.
**Expected:** La `BatchSheet` se abre en estado `.prepared` con los archivos seleccionados. El flujo de traduccion funciona igual que via Dock.
**Why human:** Interaccion con panel del sistema; no ejercitable sin entorno grafico.

#### 4. Modo segundo plano y Dock tile

**Test:** Iniciar un lote y pulsar "Continuar en segundo plano" para cerrar la sheet.
**Expected:** La barra de progreso determinada sobre el icono del Dock avanza con cada archivo; el badge muestra el conteo inicial; al terminar desaparece la barra y llega una notificacion macOS. Reabrir la sheet (via menu Traducir lote...) mientras corre muestra el estado en curso.
**Why human:** Comportamiento visual del Dock tile; solo verificable en runtime.

#### 5. Proteccion de cierre con lote activo (D-10)

**Test:** Con un lote en marcha, pulsar ⌘Q o usar el menu Archivo → Salir.
**Expected:** Aparece el alert "Hay un lote en curso (N de M archivos)" con los botones "Salir y cancelar" y "Continuar en segundo plano". Seleccionar "Continuar en segundo plano" descarta el alert sin salir.
**Why human:** Flujo de terminacion de app; requiere runtime con job activo y verificacion del alert en pantalla.

---

### Gaps Summary

Sin gaps. Todos los must-haves verificados con evidencia directa en codebase. Los 5 items de verificacion humana son flujos interactivos que requieren runtime; no representan ausencias de implementacion.

La implementacion es completa y sustantiva:
- `BatchJobManager.swift` (409 lineas): cliente SSE real con maquina de estados de 5 estados, POST multipart, stream `URLSession.bytes`, cancelacion cooperativa DELETE, descarga y extraccion ZIP con `/usr/bin/unzip`.
- `BatchSheet.swift` (263 lineas): 4 ramas de UI (prepared/running/cancelling/done), `ProgressView` determinada alimentada por datos SSE reales.
- `DockProgressManager`, `AppDelegate`, `MDTranslatorApp`, `Commands` — todos actualizados y cableados.
- 148 tests Python pasan sin regresion.

---

_Verified: 2026-06-13T11:45:32Z_
_Verifier: Claude (gsd-verifier)_
