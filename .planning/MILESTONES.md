# Milestones

## v1.0 NOTEBOOK A→E (Shipped: 2026-05-29)

**Phases:** 6 (0–5) · **Plans:** 29 · **Tests:** 137 passed

**Delivered:** Traductor Markdown production-ready — pipeline unificado, glosario, memoria TM, validación, preview, lote SSE, multi-destino, Docker, flujo editorial (revisión, diff, watch, tono, export HTML).

**Key accomplishments:**

- Hardening: traducciones incompletas → 502; UTF-8 estricto; idiomas por proveedor
- Production: `translate_markdown()`, glosario YAML + UI, memoria SQLite, CLI `md-translate`
- Trust: validador post-traducción, preview sanitizada, parser ampliado, `--strict`
- Batch UX: jobs SSE, cancelación, ZIP parcial, estimación de coste
- Team scale: multi-destino, Docker, CORS/upload/TTL, `API_TOKEN` opcional
- Editorial: revisión draft/finalize, fallback DeepL→OpenAI, diff, watch, gitignore, tono, export HTML

**Known deferred items at close:** 4 (see STATE.md Deferred Items)

**Archives:**

- [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
- [v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md)
- [v1.0-MILESTONE-AUDIT.md](milestones/v1.0-MILESTONE-AUDIT.md)

**Tag:** `v1.0`

---
