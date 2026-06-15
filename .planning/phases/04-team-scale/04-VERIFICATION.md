---
status: passed
phase: 04-team-scale
verified: 2026-05-29
requirements:

  - MULTI-01
  - MULTI-02
  - DOCKER-01
  - DOCKER-02
  - SEC-01
  - SEC-02

---

# Phase 4 Verification

## Must-haves

| Criterio                                    | Estado   | Evidencia                                   |
| ------------------------------------------- | -------- | ------------------------------------------- |
| Multi-destino API/UI/CLI → `stem.{lang}.md` | PASS     | target_langs.py, app.js chips, cli -t es,en |
| Jobs SSE incluyen target_lang               | PASS     | jobs.py file_then_lang                      |
| Estimate agrega K idiomas                   | PASS     | estimate_for_langs, language_count          |
| CORS configurable                           | PASS     | deployment.get_cors_origins                 |
| Límites upload                              | PASS     | check_upload_limits en main                 |
| TTL output/                                 | PASS     | sweep startup + periódico                   |
| Docker multi-stage + compose 5400           | PASS     | Dockerfile, docker-compose.yml              |

## Automated checks

- `pytest tests/ -q` — 118 passed

## Human verification (recommended)

1. UI: añadir es+en, traducir lote — progreso por idioma; ZIP con `doc.es.md` y `doc.en.md`
2. `docker compose up --build` — http://localhost:5400
3. `md-translate file doc.md -t es,en` — dos archivos salida
