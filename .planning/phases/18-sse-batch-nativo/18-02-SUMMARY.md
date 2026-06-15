---
phase: 18-sse-batch-nativo
plan: 02
subsystem: ui
tags: [swiftui, macos, batch, sse, progressview, sheet]

# Dependency graph
requires:

  - phase: 18-01
    provides: BatchJobManager singleton con BatchJobState enum y propiedades de progreso SSE

provides:

  - BatchSheet.swift — vista SwiftUI de lote con tres estados diferenciados (prepared/running+cancelling/done)
  - Barras de progreso determinadas ProgressView(value:) para archivos y segmentos (SSE-02)
  - Botón Cancelar con feedback cooperativo "Cancelando…" (SSE-03)
  - Botón Continuar en segundo plano que oculta la sheet sin detener el job (D-04)
  - Resumen final con errores individuales y botones Cerrar + Mostrar en Finder (D-03, D-08)

affects:

  - 18-03 (MDTranslatorApp.swift monta la sheet con .sheet(isPresented: $showBatchSheet))

# Tech tracking
tech-stack:
  added: []
  patterns:

    - "BatchSheet sigue la estructura VStack + HStack cabecera + Divider + cuerpo de SettingsView.swift"
    - "switch manager.jobState en el body — rama por estado; lógica delegada al manager"
    - "progressBody() @ViewBuilder privado compartido entre .running y .cancelling"
    - "isCancelling como parámetro Bool para reutilizar la misma vista de progreso en ambos casos"

key-files:
  created:

    - macos/MDTranslator/MDTranslator/BatchSheet.swift
  modified: []

key-decisions:

  - "Las ramas .running y .cancelling usan el mismo @ViewBuilder progressBody(isCancelling:) para evitar duplicación"
  - "La barra de segmentos solo se muestra si segmentsTotal > 0 — evita barra vacía al inicio del archivo"
  - "El texto del estado .cancelling se muestra sobre las barras, no como sustitución del nombre del archivo"
  - "UserDefaults.standard.string(forKey: defaultTargetLang) se lee en el momento del tap de Traducir (D-12)"
  - "manager.reset() se llama en Cancelar (prepared) y en Cerrar (done) — mantiene el manager limpio"

patterns-established:

  - "BatchSheet como consumidor puro del manager: cero lógica de negocio, solo switch + botones"
  - "progressBody(@ViewBuilder) como helper privado para estados con vista compartida"

requirements-completed:

  - SSE-02
  - SSE-03

# Metrics
duration: 35min
completed: 2026-06-13
---

# Phase 18 Plan 02: BatchSheet.swift Summary

**Vista SwiftUI nativa de lote con tres estados (prepared/running+cancelling/done), dos barras ProgressView determinadas y botón Cancelar cooperativo, siguiendo el patrón de SettingsView.swift**

## Performance

- **Duration:** 35 min
- **Started:** 2026-06-13T09:00:00Z
- **Completed:** 2026-06-13T09:31:33Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- BatchSheet.swift creado con estructura VStack + cabecera + Divider + switch por estado
- Estado .prepared: lista de archivos en ScrollView (max 150 pt), idioma destino de UserDefaults, botones Cancelar/Traducir con .keyboardShortcut y .disabled si servidor no listo
- Estados .running y .cancelling: barra global determinada (filesDone/filesTotal), nombre del archivo en curso, barra de segmentos determinada (segmentsDone/segmentsTotal), texto cooperativo "Cancelando…" en naranja
- Estado .done: subtítulo contextual (éxito, parcial, cancelado D-08), lista de errores en rojo, botones Cerrar + Mostrar en Finder
- Build BUILD SUCCEEDED verificado con xcodebuild en el proyecto principal
- pytest tests/test_jobs.py pasa (4/4, backend no modificado)

## Task Commits

1. **Tarea 1: Crear BatchSheet.swift** - `5167cb1` (feat)

## Files Created/Modified

- `macos/MDTranslator/MDTranslator/BatchSheet.swift` — Vista SwiftUI de lote; consumidor puro de BatchJobManager con switch sobre jobState y helper @ViewBuilder progressBody(isCancelling:)

## Decisions Made

- **progressBody como @ViewBuilder privado:** Las ramas .running y .cancelling tienen la misma UI salvo el texto de estado y el `.disabled(isCancelling)` del botón Cancelar. Extraer en un helper evita duplicar ~40 líneas de código.
- **Barra de segmentos condicional:** `if manager.segmentsTotal > 0` — evitar mostrar una barra vacía durante el intervalo entre `file_start` (que no incluye segmentsTotal) y el primer `segment_progress`. Comportamiento más limpio que una barra al 0%.
- **isCancelling como Bool, no comprobación de case:** El helper `progressBody(isCancelling:)` recibe el Bool calculado en el switch (`.cancelling` → `true`, `.running` → `false`) para que el switch sea el único punto donde se discrimina el estado.

## Deviations from Plan

None — el plan se ejecutó exactamente como estaba especificado. La única adaptación técnica fue formatear las llamadas `ProgressView(value:...)` en una sola línea para que el grep de verificación `grep -c "ProgressView(value:"` las detectara correctamente (el plan indicaba el patrón explícito).

## Issues Encountered

- **Build desde el worktree falla por Sparkle:** El proyecto Xcode usa `XCLocalSwiftPackageReference` con ruta relativa `../../../../__03.-Github_Repositories/Sparkle`. Esta ruta no existe desde la posición del worktree (`.claude/worktrees/agent-xxx/`). Solución: se copió `BatchSheet.swift` temporalmente al repo principal para verificar `BUILD SUCCEEDED` con el proyecto donde Sparkle sí resuelve correctamente. La copia temporal fue eliminada tras la verificación.
- **BatchJobManager.swift no está en el worktree:** El archivo fue creado por el plan 01 en otro worktree — no está disponible en este worktree hasta que se merge. Se usó un stub mínimo con swiftc para una primera verificación de tipos, y la verificación definitiva se hizo con el proyecto principal.

## User Setup Required

None — solo Swift nativo, sin dependencias externas añadidas.

## Next Phase Readiness

- BatchSheet.swift lista para ser montada en MDTranslatorApp.swift (plan 03) como `.sheet(isPresented: $showBatchSheet)`
- La sheet espera ser invocada mediante `NotificationCenter.default.post(name: .openBatchSheet, object: nil)` tras `BatchJobManager.shared.prepareWith(urls:)`
- El plan 03 debe añadir `.openBatchSheet` a `Notification.Name` en Commands.swift y el `.onReceive` correspondiente en MDTranslatorApp.swift

## Self-Check: PASSED

- `macos/MDTranslator/MDTranslator/BatchSheet.swift` — FOUND (worktree)
- Commit `5167cb1` — FOUND (`git log --oneline | grep 5167cb1`)
- `switch manager.jobState` count: 1 — PASSED
- `ProgressView(value:` count: 2 — PASSED
- `ObservableObject` count: 0 — PASSED
- BUILD SUCCEEDED (xcodebuild con proyecto principal) — PASSED
- pytest tests/test_jobs.py: 4 passed — PASSED

---
*Phase: 18-sse-batch-nativo*
*Completed: 2026-06-13*
