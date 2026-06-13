---
phase: 18-sse-batch-nativo
plan: "03"
subsystem: macos-swift
tags: [swift, sse, batch-sheet, appdelegate, nsevent, quit-guard, integration]
dependency_graph:
  requires:
    - BatchJobManager.shared
    - BatchSheet
    - Notification.Name.openBatchSheet
  provides:
    - flujo-batch-sse-end-to-end
    - D-10-quit-guard
  affects:
    - macos/MDTranslator/MDTranslator/AppDelegate.swift
    - macos/MDTranslator/MDTranslator/MDTranslatorApp.swift
    - macos/MDTranslator/MDTranslator/DockProgressManager.swift
---

# Plan 03 — SUMMARY

## Qué se hizo

- **AppDelegate.swift**: eliminados `confirmAndBatch`, `batchTranslate`, `callTranslateAPI`. Añadido `openBatchSheet(_:)`. Registrado `NSEvent.addLocalMonitorForEvents(.keyDown)` para D-10. `applicationShouldTerminate` + `.terminateLater` como fallback.
- **MDTranslatorApp.swift**: `@State var showBatchSheet`, `.sheet(isPresented: $showBatchSheet) { BatchSheet(...) }`, `.onReceive(.openBatchSheet)`.
- **DockProgressManager.swift**: fix SSE-04 — fallback `CGSize(128,128)` cuando `tile.size == .zero`.

## Pitfalls encontrados

- `@NSApplicationDelegateAdaptor` crea dos instancias de AppDelegate en Swift 6/Xcode 26; `applicationShouldTerminate` se invoca en la segunda instancia pero no llega a ejecutarse → NSEvent monitor como solución fiable.
- `CommandGroup(replacing: .appTermination)` no intercepta ⌘Q con WKWebView en foco.
- `NSDockTile.size` devuelve `.zero` en contextos async.
- SSE-01: `NSTemporaryDirectory()` ≠ `/tmp`; path correcto `${TMPDIR}md-translator-server.log`.

## Estado del checkpoint

| ID | Criterio | Estado |
|----|----------|--------|
| SSE-02 | Barra sheet avanza | ✅ |
| SSE-03 | Cancelar detiene job | ✅ |
| SSE-04 | Dock tile durante batch | ✅ |
| D-10 | ⌘Q alert con lote activo | ✅ NSEvent monitor |

## Commits clave

- `4ebe5f6` — NSEvent local monitor (path principal D-10)
- `adb8cfb` — applicationShouldTerminate fallback
- `5979df8` — limpieza diagnósticos
