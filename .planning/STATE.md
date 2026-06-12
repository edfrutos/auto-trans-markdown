---
gsd_state_version: 1.0
milestone: v3.1
milestone_name: Native macOS Polish
status: shipped
last_updated: "2026-06-12T00:00:00.000Z"
last_activity: 2026-06-12 -- v3.1 cerrada y archivada; sin milestone activo
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 0
  completed_plans: 0
  percent: 100
---

# Project State

## Current Position

**v3.1 COMPLETADA Y ARCHIVADA ✅ — sin milestone activo**

```
v1.0 ✅ → v2.0 ✅ → v3.0 ✅ → v3.1 ✅ → [Phase 16 ⏸ bloqueada / próximo milestone TBD]
```

## Milestone Summary

| Milestone | Phases | Shipped | Archive |
|-----------|--------|---------|---------|
| v1.0 NOTEBOOK A→E | 0–5 | 2026-05-29 | milestones/v1.0-* |
| v2.0 Production Polish & PDF | 6–7 | 2026-05-29 | milestones/v2.0-* |
| v3.0 macOS Native App | 9–12 | 2026-06-09 | milestones/v3.0-REQUIREMENTS.md |
| v3.1 Native macOS Polish | 13–15 | 2026-06-11 | milestones/v3.1-REQUIREMENTS.md |

## Next Work

1. **Phase 16: Distribution Upgrade** (NOTARIZE-01, SANDBOX-01, MAS-01, HARDENED-01) — **BLOQUEADA**: requiere Apple Developer Program ($99/año). Retomar al renovar la cuenta.
2. **Pendiente menor v3.1**: registrar medición de arranque en frío (PERF-03) en `docs/performance.md` — requiere Mac Studio M2 (hardware de referencia). La tabla "Mediciones objetivo post-v3.1" está vacía.
3. **Próximo milestone**: sin definir. Candidatos en `REQUIREMENTS.md` (SSE batch nativo, Universal Binary, deuda v2.0, iCloud sync, file association).

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

- Phase 16 completa: Apple Developer Program no renovado.

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

## Session Continuity

- 2026-06-08: v3.0 fases 9–12 ejecutadas.
- 2026-06-09: v3.0 shipped (DMG + appcast firmado).
- 2026-06-10: Phase 13 shipped (Dock, Open Recent, Drop, Services).
- 2026-06-11: Phases 14 y 15 shipped (hotkeys, estimación, undo; perf, crash reporter, smoke-test).
- 2026-06-12: Cierre administrativo — v3.0/v3.1 archivadas, STATE/REQUIREMENTS/MILESTONES/ROADMAP sincronizados, suite verificada (148 passed).
