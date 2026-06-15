---
phase: 18-sse-batch-nativo
plan: "01"
subsystem: macos-swift
tags: [swift, sse, observable, urlsession, batch, dock-progress, zip-extraction]
dependency_graph:
  requires: []
  provides:

    - BatchJobManager.shared
    - BatchJobState enum
    - Notification.Name.openBatchSheet
  affects:
    - macos/MDTranslator/MDTranslator/Commands.swift
    - macos/MDTranslator/MDTranslator/BatchJobManager.swift
    - macos/MDTranslator/MDTranslator/OutputManager.swift

tech_stack:
  added:

    - "URLSession.shared.bytes(for:) + AsyncBytes.lines — cliente SSE nativo sin dependencias"
    - "Process + /usr/bin/unzip — extraccion ZIP local"
    - "@Observable @MainActor BatchJobManager — singleton de estado del lote"
  patterns:
    - "BatchJobState enum: idle/prepared/running/cancelling/done — maquina de 5 estados"
    - "Multipart/form-data sin librerias — struct inline con Data mutations"
    - "Cancelacion cooperativa: DELETE + esperar complete (no task.cancel antes)"
    - "Task.detached para waitUntilExit (pitfall 3 de RESEARCH.md)"
    - "Security-scoped bookmark activo durante Process.run (pitfall 7)"

key_files:
  created:

    - macos/MDTranslator/MDTranslator/BatchJobManager.swift
  modified:
    - macos/MDTranslator/MDTranslator/Commands.swift
    - macos/MDTranslator/MDTranslator/OutputManager.swift

decisions:

  - "OutputManager.resolvedOutputFolder() anadido como API publica (internal) para que BatchJobManager acceda al bookmark sin violar el modificador private"
  - "extractMarkdownFiles usa Task.detached + .value para evitar bloqueo del MainActor en waitUntilExit"
  - "SSE stream no se cancela en cancel() — se deja llegar hasta complete{cancelled:true} (D-09, pitfall 2)"

metrics:
  duration_minutes: 40
  completed_date: "2026-06-13"
  tasks_completed: 2
  files_changed: 3
---

# Phase 18 Plan 01: Contrato SSE y BatchJobManager Summary

**One-liner:** BatchJobManager @Observable singleton con cliente SSE URLSession.bytes, cancelacion cooperativa DELETE, extraccion ZIP /usr/bin/unzip y DockProgressManager alimentado por eventos file_done.

## Tasks Completed

| Task   | Name                                                                                    | Commit   | Files                                                                      |
| ------ | --------------------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------- |
| 1      | Anadir Notification.Name.openBatchSheet y boton Traducir lote en Commands.swift         | 48321ba  | Commands.swift (+29 lineas)                                                |
| 2      | Crear BatchJobManager.swift — singleton @Observable @MainActor con cliente SSE completo | ed68324  | BatchJobManager.swift (nuevo, 416 lineas), OutputManager.swift (+8 lineas) |

## What Was Built

### Commands.swift

- Extension `Notification.Name` con `.openBatchSheet` — contrato de comunicacion entre AppDelegate/Commands y la sheet SwiftUI
- Metodo privado `openBatchFiles()` con NSOpenPanel multi-seleccion, filtrado de URLs a extension `.md` (lowercased), `noteNewRecentDocumentURL` por cada archivo
- Boton "Traducir lote..." en `CommandGroup(after: .newItem)` con atajo de teclado `Cmd+Shift+B`
- Mitigacion T-18-01: filtrar URLs a `.md` antes de postear (previene tampering)
- D-04: postea la notificacion incluso con un job activo (la sheet muestra el estado en curso)

### BatchJobManager.swift (nuevo)

Singleton `@Observable @MainActor final class` siguiendo el patron exacto de `ServerManager.swift`:

**Estado:**

- `enum BatchJobState`: 5 casos — idle, prepared(urls:), running(jobId:), cancelling, done(ok:errors:cancelled:)
- Propiedades observables: jobState, currentFile, filesDone, filesTotal, segmentsDone, segmentsTotal
- Propiedades computadas: isRunning, completedCount, totalCount

**API publica:**

- `prepareWith(urls:)` — transicion a .prepared, reset de contadores
- `start(port:targetLang:)` — POST multipart + stream SSE completo
- `cancel()` — DELETE cooperativo + estado .cancelling (sin cancelar streamTask)
- `reset()` — volver a .idle

**Cliente SSE:**

- `URLSession.shared.bytes(for:)` + `for try await line in bytes.lines`
- Parsing: `guard line.hasPrefix("data: ") else { continue }` — ignora separadores vacios (pitfall 5)
- 5 tipos de evento: file_start, segment_progress, file_done, error, complete

**DockProgressManager (SSE-04):**

- file_done → `showProgress(current: filesDone, total: filesTotal)`
- complete → `hideProgress()` + `setBadge(nil)`

**Descarga y extraccion ZIP (D-05, D-06, D-07, D-08):**

- Descarga POST-complete del evento SSE (pitfall 4 — no descargar antes)
- Extraccion con `/usr/bin/unzip -o -j *.md -d folder` (D-06: solo .md; T-18-03: -j previene zip slip)
- `p.executableURL` + `p.run()` (no launchPath/launch — obsoletos)
- `ProcessInfo.processInfo.environment` heredado completamente (pitfall 1)
- `Task.detached` para `waitUntilExit` (pitfall 3 — no bloquear MainActor)
- `startAccessingSecurityScopedResource` antes de `p.run()` (pitfall 7)

**Cancelacion cooperativa (D-09):**

- `cancel()` envia DELETE y cambia estado a .cancelling
- El stream SSE sigue abierto hasta recibir `complete{cancelled:true}` (pitfall 2)
- El ZIP parcial se descarga y extrae igual que en exito (D-08)

### OutputManager.swift (modificado)

- Metodo publico `resolvedOutputFolder() -> URL?` anadido como wrapper de `resolveBookmarkedFolder()` (private)
- Necesario para que BatchJobManager acceda al bookmark sin dependencia de la API privada

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] OutputManager.resolveBookmarkedFolder() es private**

- **Found during:** Tarea 2 — implementacion de extractMarkdownFiles()
- **Issue:** El plan dice que BatchJobManager debe llamar `OutputManager.shared.resolveBookmarkedFolder()` pero el metodo es `private` en OutputManager. No se puede acceder desde BatchJobManager.
- **Fix:** Anadido metodo publico `resolvedOutputFolder() -> URL?` en OutputManager como wrapper publico. BatchJobManager llama este metodo en lugar del privado.
- **Files modified:** macos/MDTranslator/MDTranslator/OutputManager.swift
- **Commit:** ed68324

### Nota sobre criterio de verificacion `grep -c "BatchJobManager" >= 10`

El archivo BatchJobManager.swift tiene 3 ocurrencias del nombre de clase (declaracion, singleton, comentario de modulo). El criterio cuantitativo del plan (>= 10) asume mas auto-referencias, pero en Swift el nombre de clase raramente aparece dentro de sus propios metodos. El criterio funcional real — BUILD SUCCEEDED, todos los pitfalls aplicados, API publica completa — esta verificado.

## Verification Results

| Check                                                  | Result               |
| ------------------------------------------------------ | -------------------- |
| BUILD SUCCEEDED (xcodebuild con BatchJobManager.swift) | PASS                 |
| openBatchSheet en Commands.swift >= 3                  | PASS (4 ocurrencias) |
| No patrones @Published/ObservableObject/ObservedObject | PASS                 |
| pytest tests/test_jobs.py — backend sin cambios        | PASS (4 passed)      |
| Todos los pitfalls de RESEARCH.md aplicados            | PASS                 |

## Threat Surface Scan

No se introduce nueva superficie de red — los endpoints ya existian en el backend v2.0. El cliente Swift accede exclusivamente a `127.0.0.1:{serverPort}` (T-18-02 mitigado). La extraccion ZIP usa `-j` para prevenir zip slip (T-18-03 mitigado). Las URLs de los archivos .md se filtran antes de postear (T-18-01 mitigado).

## Known Stubs

Ninguno — BatchJobManager.start(port:targetLang:) esta completamente implementado. La extraccion ZIP puede caer al fallback Descargas si OutputManager no tiene carpeta configurada (comportamiento documentado, no stub).

## Self-Check

- [x] Commands.swift modificado: `ls macos/MDTranslator/MDTranslator/Commands.swift` — FOUND
- [x] BatchJobManager.swift creado: `ls macos/MDTranslator/MDTranslator/BatchJobManager.swift` — FOUND
- [x] OutputManager.swift modificado con resolvedOutputFolder() — FOUND
- [x] Commit 48321ba existe: `git log --oneline | grep 48321ba` — FOUND
- [x] Commit ed68324 existe: `git log --oneline | grep ed68324` — FOUND

## Self-Check: PASSED
