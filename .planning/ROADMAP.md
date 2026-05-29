# Roadmap: MarkDown Auto Translator

## Milestones

- ✅ **v1.0 NOTEBOOK A→E** — Phases 0–5 (shipped 2026-05-29) → [archive](milestones/v1.0-ROADMAP.md)
- 🚧 **v2.0 Production Polish & PDF** — Phases 6–7 (in progress)

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

## Phases (v2.0 — active)

### Phase 6: v1 Tech Debt Closure
**Goal**: Cerrar gaps periféricos del audit v1.0 sin cambiar arquitectura core  
**Depends on**: v1.0 shipped  
**Requirements**: DEBT-01, DEBT-02, DEBT-03, DEBT-04  
**Success Criteria** (what must be TRUE):
  1. `md-translate batch --zip -t es --tone formal` aplica tono en todas las traducciones del ZIP
  2. Con `API_TOKEN` en servidor, la UI permite guardar token y las peticiones autenticadas funcionan (incl. SSE)
  3. Tras traducir a 2+ idiomas en editor, el usuario puede ver y descargar cada idioma sin perder validación/preview
  4. Existe `02-VERIFICATION.md` con status passed para fase 2  
**Plans:** 4/4 complete

Plans:
- [x] 06-01-PLAN.md — CLI batch ZIP + tone (DEBT-01) — wave 1
- [x] 06-02-PLAN.md — UI Bearer token + fetch/SSE (DEBT-02) — wave 1
- [x] 06-03-PLAN.md — Editor multi-idioma tabs/download (DEBT-03) — wave 2
- [x] 06-04-PLAN.md — 02-VERIFICATION retroactivo + tests regresión (DEBT-04) — wave 3

### Phase 7: PDF Export
**Goal**: Usuario exporta Markdown traducido a PDF desde CLI y UI  
**Depends on**: Phase 6  
**Requirements**: PDF-01, PDF-02, PDF-03, PDF-04  
**Success Criteria** (what must be TRUE):
  1. CLI genera PDF legible desde `.md` traducido (estilos básicos, código preservado visualmente)
  2. UI ofrece «Export PDF» tras traducción exitosa (mismo patrón que HTML)
  3. Dependencia PDF documentada como opcional; tests mock o skip si WeasyPrint/pandoc ausente
  4. README describe instalación y limitaciones (Docker, headless)  
**Plans:** 0 plans

Plans:
- [ ] 07-01-PLAN.md — pdf_export.py + tests (PDF-01, PDF-04)
- [ ] 07-02-PLAN.md — CLI export PDF (PDF-02)
- [ ] 07-03-PLAN.md — UI export PDF + README (PDF-03, PDF-04)

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 0–5 | v1.0 | 29/29 | Complete | 2026-05-29 |
| 6. Tech Debt Closure | v2.0 | 4/4 | Complete | 2026-05-29 |
| 7. PDF Export | v2.0 | 0/3 | Not started | — |

**Execution order:** 6 → 7

---
*Last updated: 2026-05-29 — phase 6 complete*
