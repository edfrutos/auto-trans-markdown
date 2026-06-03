---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: macOS Native App
status: Roadmap approved — ready for `/gsd-plan-phase 9`
last_updated: "2026-06-03T12:05:05.395Z"
last_activity: 2026-06-02 — v3.0 roadmap created
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 12
  completed_plans: 0
  percent: 0
---

# Project State

## Current Position

Phase: 9 — Python Embedding Foundation (not started)
Plan: —
Status: Roadmap approved — ready for `/gsd-plan-phase 9`
Last activity: 2026-06-02 — v3.0 roadmap created

```
Progress: [░░░░░░░░░░░░░░░░░░░░] 0% (0/4 phases, 0/12 plans)
```

## Phase Summary

| Phase | Name | Plans | Status |
|-------|------|-------|--------|
| 9 | Python Embedding Foundation | 3 | Not started |
| 10 | Swift App Shell & Auth | 3 | Not started |
| 11 | Translation Features & Native UI | 4 | Not started |
| 12 | Distribution & Auto-Update | 2 | Not started |

## Accumulated Context

### Key Decisions

- python-build-standalone CPython 3.11.15 (release 20260510, `install_only_stripped`) para embedding — portable, sin dependencia del Python del sistema
- Puerto dinámico asignado por el kernel (`bind(port:0)`) — evita conflictos con puertos fijos
- API keys en Keychain macOS via Security.framework — nunca en `.env` ni argumentos CLI
- Firma ad-hoc (sin Apple Developer account) — usuario usa clic derecho → Abrir para bypassear Gatekeeper
- Sparkle 2.9.2 vía SPM con firma EdDSA — auto-update independiente de notarización
- SSE diferido a v3.1 — v3.0 usa ProgressView indeterminado para batch
- Universal Binary diferido a v3.1 — v3.0 es Apple Silicon only
- Phase 8 (v2.1 lockfile) absorbida en build system de Phase 9 — `uv install` en `build-python-bundle.sh`

### Blockers

Ninguno activo.

### Technical Context

- Backend Python existente: FastAPI + uvicorn, sin modificaciones requeridas en `src/`
- Stack Swift: Swift 6.3.2 / Xcode 26.5 / macOS 14+ Sonoma
- Herramientas de distribución: create-dmg 1.2.3, codesign ad-hoc (`--sign -`)
- Tests existentes: 148 passing — no deben regresar

## Session Continuity

Stopped at: Phase 9 context gathered
Resume: `/gsd-plan-phase 9`
