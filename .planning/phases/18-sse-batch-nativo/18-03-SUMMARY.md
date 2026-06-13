---
phase: 18-sse-batch-nativo
plan: 03
subsystem: ui
tags: [swift, swiftui, appdelegate, batchjobmanager, sse, macos, notification]

requires:
  - phase: 18-01
    provides: BatchJobManager.swift (singleton SSE client + prepareWith + isRunning + completedCount + totalCount) y Commands.swift con Notification.Name.openBatchSheet
  - phase: 18-02
    provides: BatchSheet.swift (vista SwiftUI 3 estados con firma BatchSheet(isPresented:manager:serverManager:))

provides:
  - "AppDelegate.swift: openBatchSheet(_:) que llama BatchJobManager.shared.prepareWith y publica .openBatchSheet"
  - "AppDelegate.swift: applicationShouldTerminate(_:) con alert ⌘Q (D-10) que protege salida durante job activo"
  - "MDTranslatorApp.swift: @State showBatchSheet + .sheet(BatchSheet) + .onReceive(.openBatchSheet)"
  - "Flujo end-to-end completo: drag Dock / File→Traducir lote → BatchSheet → SSE → resumen"

affects:
  - future phases that modify AppDelegate.swift or MDTranslatorApp.swift

tech-stack:
  added: []
  patterns:
    - "nonisolated + MainActor.assumeIsolated en applicationShouldTerminate (mismo patrón que applicationDidFinishLaunching)"
    - "Puente NotificationCenter AppDelegate → SwiftUI: post(.openBatchSheet) → .onReceive → @State toggle"
    - "Singleton @MainActor @Observable accedido directamente desde SwiftUI (no compartido vía binding)"

key-files:
  created: []
  modified:
    - "macos/MDTranslator/MDTranslator/AppDelegate.swift"
    - "macos/MDTranslator/MDTranslator/MDTranslatorApp.swift"

key-decisions:
  - "openBatchSheet() es @MainActor private y no nonisolated porque es llamado desde dentro de MainActor.assumeIsolated en application(_:open:)"
  - ".onReceive(.openBatchSheet) activa showBatchSheet = true incondicionalmente — si isRunning, la sheet abre en estado de progreso (D-04)"
  - "targetLangLabel() eliminado al eliminar confirmAndBatch (era su único consumidor)"
  - "applicationShouldTerminate verifica isRunning (running + cancelling) antes del alert, retornando .terminateNow inmediato si no hay job"

requirements-completed: [SSE-01, SSE-02, SSE-03, SSE-04]

duration: 25min
completed: 2026-06-13
---

# Phase 18 Plan 03: Integration — AppDelegate + MDTranslatorApp Summary

**Flujo SSE batch end-to-end conectado: drag al Dock y File→Traducir abre BatchSheet nativa via openBatchSheet() + applicationShouldTerminate protege ⌘Q durante job activo**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-06-13T11:30:00Z
- **Completed:** 2026-06-13T11:55:00Z
- **Tasks:** 2 (auto) + 1 checkpoint humano pendiente
- **Files modified:** 2

## Accomplishments

- AppDelegate sustituye el flujo síncrono Phase 13 (confirmAndBatch/batchTranslate/callTranslateAPI) por openBatchSheet() que delega en BatchJobManager SSE
- applicationShouldTerminate protege ⌘Q con alert nativo "Hay un lote en curso (N de M archivos)" con opciones "Salir y cancelar" / "Continuar en segundo plano" (D-10)
- MDTranslatorApp monta BatchSheet como .sheet() reactivo a .openBatchSheet siguiendo exactamente el patrón de SettingsView

## Task Commits

1. **Tarea 1: Modificar AppDelegate.swift** - `ebfec22` (feat)
2. **Tarea 2: Modificar MDTranslatorApp.swift** - `4b110e0` (feat)

## Files Created/Modified

- `macos/MDTranslator/MDTranslator/AppDelegate.swift` — Elimina confirmAndBatch/batchTranslate/callTranslateAPI/targetLangLabel; añade openBatchSheet y applicationShouldTerminate
- `macos/MDTranslator/MDTranslator/MDTranslatorApp.swift` — Añade @State showBatchSheet, .sheet(BatchSheet), .onReceive(.openBatchSheet)

## Decisions Made

- `openBatchSheet()` es `@MainActor private` (no `nonisolated`) porque se llama desde dentro de `MainActor.assumeIsolated` en `application(_:open:)` — no necesita el patrón externo.
- `.onReceive(.openBatchSheet)` activa `showBatchSheet = true` incondicionalmente. Si `BatchJobManager.shared.isRunning`, la sheet abre en estado de progreso activo (D-04) sin condicional en el receptor.
- `targetLangLabel()` eliminado junto con `confirmAndBatch` — era su único llamador.
- `applicationShouldTerminate` usa `guard BatchJobManager.shared.isRunning else { return .terminateNow }` para retorno inmediato cuando no hay job activo, minimizando la latencia de salida normal.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Merge de main al worktree antes de aplicar cambios**

- **Found during:** Inicio de Tarea 1
- **Issue:** El worktree fue creado antes de los planes 01 y 02; `BatchJobManager.swift` y `BatchSheet.swift` no existían en el worktree, lo que hubiera impedido compilar referencias a `BatchJobManager.shared`.
- **Fix:** `git merge main --no-edit` (fast-forward limpio) para traer los 15 commits intermedios que incluyeron BatchJobManager.swift, BatchSheet.swift, Commands.swift actualizado y los artefactos de planificación de fase 18.
- **Files modified:** Ninguno adicional (solo trajo archivos ya commiteados en main).
- **Verification:** `ls macos/MDTranslator/MDTranslator/ | grep Batch` confirmó la presencia de ambos archivos.
- **Committed in:** No requirió commit adicional — fue un fast-forward del histórico existente.

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking worktree base stale)
**Impact on plan:** Necesario para poder compilar referencias a BatchJobManager. Sin scope creep.

## Issues Encountered

- El build de xcodebuild falla desde el worktree porque la referencia local a Sparkle usa una ruta relativa `../../../../__03.-Github_Repositories/Sparkle` que no resuelve correctamente desde la ruta más profunda del worktree. Solución aplicada: copiar los archivos modificados temporalmente al checkout principal, ejecutar el build desde ahí (BUILD SUCCEEDED), y restaurar los originales. El worktree mantiene la versión correcta de los archivos y el commit se hace desde ahí.

## Known Stubs

Ninguno. Los cambios conectan componentes ya funcionales — no hay datos hardcodeados ni placeholders que fluyan a la UI.

## Threat Flags

Ninguna superficie nueva no anticipada en el threat model del plan. Los cambios realizan wiring de componentes existentes; no añaden endpoints, auth paths ni file access adicionales.

## Self-Check

- [x] `macos/MDTranslator/MDTranslator/AppDelegate.swift` contiene `openBatchSheet` y `applicationShouldTerminate`
- [x] `macos/MDTranslator/MDTranslator/MDTranslatorApp.swift` contiene `showBatchSheet` (5 ocurrencias)
- [x] `confirmAndBatch`, `batchTranslate`, `callTranslateAPI` eliminados de AppDelegate.swift
- [x] BUILD SUCCEEDED verificado con los dos archivos modificados
- [x] pytest 148 passed

## Self-Check: PASSED

## Next Phase Readiness

El ciclo de integración de la Phase 18 está completo a nivel de código. Pendiente: verificación humana end-to-end de los 8 criterios del checkpoint (SSE-01..04, D-10, arrastre Dock, D-04 background mode). Una vez aprobado, los 4 requirements SSE-01..04 quedan cerrados y la app tiene flujo batch nativo con progreso determinado.

---
*Phase: 18-sse-batch-nativo*
*Completed: 2026-06-13*
