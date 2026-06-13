---
gsd_state_version: 1.0
milestone: v3.1
milestone_name: Native macOS Polish
status: shipped
last_updated: "2026-06-13T16:21:08.607Z"
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Current Position

Phase: 18 (sse-batch-nativo) — COMPLETE ✅
Plan: 3 of 3
**v3.1 COMPLETADA Y ARCHIVADA ✅ — sin milestone activo**

```text
v1.0 ✅ → v2.0 ✅ → v3.0 ✅ → v3.1 ✅ → [Phase 16 ⏸ bloqueada / próximo milestone TBD]
```

## Milestone Summary

| Milestone                    | Phases   | Shipped    | Archive                         |
| ---------------------------- | -------- | ---------- | ------------------------------- |
| v1.0 NOTEBOOK A→E            | 0–5      | 2026-05-29 | milestones/v1.0-*               |
| v2.0 Production Polish & PDF | 6–7      | 2026-05-29 | milestones/v2.0-*               |
| v3.0 macOS Native App        | 9–12     | 2026-06-09 | milestones/v3.0-REQUIREMENTS.md |
| v3.1 Native macOS Polish     | 13–15    | 2026-06-11 | milestones/v3.1-REQUIREMENTS.md |

## Next Work

1. **Phase 16: Release v3.1 Distribuible** (redefinida 2026-06-12, sin App Store/notarización):
   - ✅ REL-01: Makefile VERSION=3.1/BUILD_NUM=2; fixes críticos del pipeline (export anidado, DMG vía /tmp, verificación de versión del bundle)
   - ✅ REL-02: `docs/RELEASE-NOTES-3.1.md` (incluye limitaciones NSServices y TCC)
   - ✅ REL-03: appcast v3.1 firmado (edSignature `561dpL…`, length 43991291); URLs corregidas a `edfrutos`
   - ✅ Verificación funcional en Mac: app 3.1 instalada, hotkey global ✓, Services ✓ (apps AppKit), API keys ✓
   - ✅ REL-04: tag `v3.1` pusheado, GitHub Release publicada, **actualización Sparkle verificada end-to-end** (2026-06-12)
   - ✅ REL-05: PERF-03 medido — **arranque en frío 1,46 s** (mediana, Mac Studio M2, 2026-06-12) con `scripts/measure-cold-start.sh`; registrado en `docs/performance.md`

   **PHASE 16 COMPLETADA AL 100% ✅ — v3.1 publicada, distribuyéndose y con métricas cerradas**

2. **Phase 17 (futura, descartada/diferida)**: NOTARIZE/SANDBOX/MAS/HARDENED — solo si se contrata Apple Developer Program.
3. **Milestone v3.2 Native Workflow & Sync — DEFINIDO (2026-06-12)**: Phases 18–21, 14 REQ-IDs en `REQUIREMENTS.md`:
   - Phase 18: SSE Batch Nativo (SSE-01..04) — progreso real + cancelación, consume endpoints existentes de `src/jobs.py`
   - Phase 19: Asociación `.md` (ASSOC-01..03) — CFBundleDocumentTypes, reutiliza ruta de apertura del Dock
   - Phase 20: Export PDF Nativo (PDFN-01..03) — `WKWebView.createPDF`, sin WeasyPrint en el bundle
   - Phase 21: iCloud Drive Sync (SYNC-01..04) — carpeta iCloud Drive (sin entitlements); requiere parametrizar rutas en glossary.py/memory.py
   - **Siguiente paso**: research + planificación de Phase 18 con el flujo GSD (`/gsd-execute-phase` en Claude Code)
   - Descartado para v3.2: Universal Binary, CloudKit, WeasyPrint embebido, deuda servidor v2.0 (ver Out of Scope)

## Accumulated Context

### Key Decisions

- python-build-standalone CPython 3.11.15 (`install_only_stripped`) para embedding — portable, sin Python del sistema
- Puerto dinámico (`bind(port:0)`) — evita conflictos
- API keys en Keychain macOS (Security.framework) — nunca en `.env` ni argumentos CLI
- Firma ad-hoc (sin Apple Developer account) — clic derecho → Abrir para Gatekeeper
- Sparkle 2.9.2 vía SPM con firma EdDSA — auto-update independiente de notarización
- python-bundle reducido a 116 MB en Phase 15 (PERF-02; baseline ~200 MB)
- Hotkey global ⌥⇧T (`GlobalHotkeyManager`); Services vía `ServiceHandler` + NSServices en Info.plist
- `make smoke-test` (TEST-01) usa `/api/translate/estimate` — no requiere API key real

### Blockers

- Ninguno para la release v3.1 ad-hoc. Notarización/MAS (Phase 17 futura) seguiría requiriendo Apple Developer Program.
- Los pasos `make dmg`/`make appcast` requieren Xcode en el Mac del usuario (no ejecutables desde el sandbox de Cowork).

### Technical Context

- Backend Python intacto: FastAPI + uvicorn, 148 tests passing (verificado 2026-06-12)
- Stack Swift: Swift 6.3.2 / Xcode 26.5 / macOS 14+; Apple Silicon only
- Distribución: create-dmg, codesign ad-hoc (`--sign -`), appcast Sparkle firmado
- Git: working tree limpio; HEAD `05c08c0` (Phase 15 completa); sin tags v3.0/v3.1 (último tag: `v2.0`)
- Fases 13–15 ejecutadas sin directorios en `.planning/phases/` (sin artefactos PLAN/VERIFICATION por fase)

## Pitfalls críticos (v3.0/v3.1 — vigentes para trabajo futuro en macOS)

1. `p.environment` debe heredar `ProcessInfo.processInfo.environment` — reemplazarlo rompe uvicorn
2. App Sandbox incompatible con subprocess externo — rediseño necesario para MAS-01 (Phase 16)
3. Run Script "Based on dependency analysis" → desactivado en Xcode
4. `@Observable` + `@MainActor` (no `ObservableObject`) para Swift 6
5. `WKScriptMessageHandler` retiene el Coordinator — usar wrapper weak
6. Security-Scoped Bookmarks necesitarán entitlement extra si se activa Sandbox
7. NSServices requiere re-registro con `lsregister` tras cambios (fix e4860e5; usar `$(HOME)` en Makefile, no `~`)
8. Keychain ACL + firma ad-hoc: re-firmar invalida el acceso — ver fix 8e4f802
9. **`cp -R` con destino existente ANIDA el bundle** — el Makefile distribuía la app v3.0 rancia en cada build. Fix: `rm -rf "$(APP)"` antes de exportar + verificación de versión (2026-06-12)
10. `hdiutil create` falla con "Recurso ocupado" escribiendo en volúmenes externos — crear DMG en /tmp y copiar (fix en Makefile)
11. TCC (Accesibilidad) se invalida con cada re-firma ad-hoc — entrada antigua falla en silencio sin re-preguntar: `tccutil reset Accessibility com.edefrutos.md-translator` + re-conceder + relanzar
12. NSServices de texto solo funciona en apps AppKit (TextEdit, Notas, Mail…) — Electron/Java no lo implementan; el workaround es el hotkey global
13. El usuario de GitHub es **edfrutos** (no edefrutos) — verificar URLs de appcast/SUFeedURL contra el remote real
14. Mantener UNA sola copia instalada de la app — duplicados (~/Applications + /Applications) confunden Services, hotkeys y TCC

## Session Continuity

- 2026-06-08: v3.0 fases 9–12 ejecutadas.
- 2026-06-09: v3.0 shipped (DMG + appcast firmado).
- 2026-06-10: Phase 13 shipped (Dock, Open Recent, Drop, Services).
- 2026-06-11: Phases 14 y 15 shipped (hotkeys, estimación, undo; perf, crash reporter, smoke-test).
- 2026-06-12: Cierre administrativo — v3.0/v3.1 archivadas, STATE/REQUIREMENTS/MILESTONES/ROADMAP sincronizados, suite verificada (148 passed).
- 2026-06-12 (tarde): Phase 16 ejecutada — build 3.1 real tras descubrir y corregir el bug de export anidado del Makefile; usuario GitHub corregido (edfrutos) en appcast/SUFeedURL/docs; appcast firmado; verificación funcional completa en el Mac (hotkey, Services, keys); limpieza de worktrees huérfanos y artefactos; pendiente solo REL-04 (tag + GitHub Release).
