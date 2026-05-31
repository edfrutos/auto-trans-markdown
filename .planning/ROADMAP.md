# Roadmap: MarkDown Auto Translator

## Milestones

- ✅ **v1.0 NOTEBOOK A→E** — Phases 0–5 (shipped 2026-05-29) → [archive](milestones/v1.0-ROADMAP.md)
- ✅ **v2.0 Production Polish & PDF** — Phases 6–7 (shipped 2026-05-29) → [archive](milestones/v2.0-ROADMAP.md)
- 🔄 **v2.1 Reproducible Dependencies** — Phase 8 (active)

## Phases (v1.0 — shipped)

<details>
<summary>✅ v1.0 NOTEBOOK A→E (Phases 0–5) — SHIPPED 2026-05-29</summary>

| Phase | Name | Plans | Completed |
|-------|------|-------|-----------|
| 0 | MVP Hardening | 4/4 | 2026-05-28 |
| 1 | Production Table Stakes | 5/5 | 2026-05-28 |
| 2 | Trust & QA | 5/5 | 2026-05-29 |
| 3 | Batch UX & Cost Control | 4/4 | 2026-05-29 |
| 4 | Team Scale | 5/5 | 2026-05-29 |
| 5 | Editorial & Pro Workflow | 6/6 | 2026-05-29 |

Detalle: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)

</details>

## Phases (v2.0 — shipped)

<details>
<summary>✅ v2.0 Production Polish & PDF (Phases 6–7) — SHIPPED 2026-05-29</summary>

| Phase | Name | Plans | Completed |
|-------|------|-------|-----------|
| 6 | v1 Tech Debt Closure | 4/4 | 2026-05-29 |
| 7 | PDF Export | 3/3 | 2026-05-29 |

Detalle: [milestones/v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md)

</details>

## Phases (v2.1 — active)

- [ ] **Phase 8: Reproducible Dependencies** - Lockfile uv, Docker frozen install y documentación de instalación actualizada

## Phase Details

### Phase 8: Reproducible Dependencies
**Goal**: El proyecto tiene dependencias fijadas con versiones exactas, cualquier desarrollador puede reproducir el entorno idéntico con un solo comando, y la documentación refleja el flujo actualizado
**Depends on**: Nothing (standalone tooling phase; application logic unchanged)
**Requirements**: LOCK-01, LOCK-02, LOCK-03, LOCK-04, LOCK-05
**Success Criteria** (what must be TRUE):
  1. `uv.lock` existe en el repositorio, está commiteado y cubre todas las dependencias directas e indirectas
  2. Ejecutar `uv sync` en un entorno limpio instala exactamente las mismas versiones sin argumentos adicionales ni resolución de conflictos
  3. El README incluye instrucciones de instalación para `uv` (recomendado) y `pip` (alternativa), incluyendo el comando para actualizar el lockfile
  4. `Dockerfile` y `docker-compose.yml` usan `uv sync --frozen` de forma que la imagen se construye determinísticamente desde el lockfile
**Plans**: 3 planes

Plans:
- [ ] 08-01-PLAN.md — Generar uv.lock y regenerar requirements.txt como artefacto derivado (LOCK-01, LOCK-02, LOCK-03)
- [ ] 08-02-PLAN.md — Reescribir Dockerfile con patrón uv multi-stage (LOCK-05)
- [ ] 08-03-PLAN.md — Actualizar README con instrucciones uv + pip + flujo de lockfile (LOCK-03, LOCK-04)

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. MVP Hardening | 4/4 | Shipped | 2026-05-28 |
| 1. Production Table Stakes | 5/5 | Shipped | 2026-05-28 |
| 2. Trust & QA | 5/5 | Shipped | 2026-05-29 |
| 3. Batch UX & Cost Control | 4/4 | Shipped | 2026-05-29 |
| 4. Team Scale | 5/5 | Shipped | 2026-05-29 |
| 5. Editorial & Pro Workflow | 6/6 | Shipped | 2026-05-29 |
| 6. v1 Tech Debt Closure | 4/4 | Shipped | 2026-05-29 |
| 7. PDF Export | 3/3 | Shipped | 2026-05-29 |
| 8. Reproducible Dependencies | 0/3 | Planned | - |

---
*Last updated: 2026-05-31 — Phase 8 planned (3 planes, 2 waves)*
