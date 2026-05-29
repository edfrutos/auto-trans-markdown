# Milestones

## v1.0 NOTEBOOK A→E (Shipped: 2026-05-29)

**Phases:** 6 (0–5) · **Plans:** 29 · **Tests:** 137 passed

**Delivered:** Traductor Markdown production-ready — pipeline unificado, glosario, memoria TM, validación, preview, lote SSE, multi-destino, Docker, flujo editorial (revisión, diff, watch, tono, export HTML).

**Archives:** [ROADMAP](milestones/v1.0-ROADMAP.md) · [REQUIREMENTS](milestones/v1.0-REQUIREMENTS.md) · [AUDIT](milestones/v1.0-MILESTONE-AUDIT.md)

**Tag:** `v1.0`

---

## v2.0 Production Polish & PDF (Shipped: 2026-05-29)

**Phases:** 2 (6–7) · **Plans:** 7 · **Tests:** 148 passed

**Delivered:** Cierre deuda audit v1.0 (tone batch ZIP, Bearer UI/SSE, tabs multi-idioma editor, 02-VERIFICATION) + export PDF WeasyPrint opcional (CLI, API, UI, README).

**Key accomplishments:**

- Tech debt: paridad `--tone` en batch ZIP; auth completa con `API_TOKEN` + SSE query token
- Editor multi-destino: tabs para preview/descarga por idioma
- Artefacto GSD fase 2 retroactivo (`02-VERIFICATION.md`)
- PDF: `pdf_export.py`, `export --format pdf`, `POST /api/export/pdf`, botón Export PDF

**Deferred to v2.1+:** Redis jobs (V2-04), multi-tenant (V2-03), plugin editor (V2-02), lockfile (LOCK-01)

**Archives:**

- [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md)
- [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md)
- [v2.0-MILESTONE-AUDIT.md](milestones/v2.0-MILESTONE-AUDIT.md)

**Tag:** `v2.0`

---
