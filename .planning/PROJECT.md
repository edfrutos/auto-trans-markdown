# MarkDown Auto Translator

## What This Is

Traductor de archivos Markdown que preserva formato y bloques de código, orientado a documentación técnica y equipos que localizan docs sin romper sintaxis. Incluye interfaz web (editor, archivo, lote), API FastAPI, CLI `md-translate`, glosario, memoria de traducción y proveedores OpenAI o DeepL. Milestones **v1.0** (NOTEBOOK A→E) y **v2.0** (polish + PDF) están **completos**.

## Core Value

Traducir **solo el texto dirigido al usuario** al idioma destino **sin alterar Markdown ni código**, con coherencia terminológica y coste predecible en lotes grandes.

## Current Milestone: v2.1 Reproducible Dependencies

**Goal:** Añadir un lockfile al proyecto para que las instalaciones sean deterministas y reproducibles.

**Target features:**
- Lockfile con versiones exactas pinadas (`uv.lock` o equivalente)
- Flujo de actualización documentado (cómo renovar el lock)
- README / instrucciones de instalación actualizadas

## Requirements

<details>
<summary>Shipped v1.0 (phases 0–5) — NOTEBOOK A→E</summary>

Ver `.planning/milestones/v1.0-REQUIREMENTS.md` para el listado completo (HARD, PIPE, GLOS, TM, CLI, VAL, PREV, JOB, COST, MULTI, DOCKER, SEC, REV, FALL, DIFF, WATCH, TONE, HIST, EXPORT).

</details>

<details>
<summary>Shipped v2.0 (phases 6–7) — Production Polish & PDF</summary>

- ✓ Tech debt audit — DEBT-01 … DEBT-04 (tone batch ZIP, Bearer UI/SSE, editor multi-idioma, 02-VERIFICATION)
- ✓ Export PDF — PDF-01 … PDF-04 (WeasyPrint opcional, CLI, API, UI, README)

Ver `.planning/milestones/v2.0-REQUIREMENTS.md`.

</details>

### Backlog (v2.1+)

- [ ] Plugin Obsidian o VS Code — V2-02
- [ ] Multi-tenant con API key por usuario — V2-03
- [ ] Redis job store para multi-worker — V2-04
- [ ] Lockfile reproducible — LOCK-01

## Context

**Estado actual:** Pipeline segment → translate → reassemble con fachada `pipeline.py`. FastAPI + UI estática. Memoria SQLite. Glosario YAML. Jobs in-memory SSE. Export HTML + PDF (opcional). **148 tests**. Docker documentado.

**Usuarios objetivo:** Desarrolladores, redactores técnicos y equipos que traducen README, docs y artículos Markdown.

**Límites conocidos:** Jobs SSE no persisten (V2-04). Auth Bearer opcional, no multi-tenant. WeasyPrint no en imagen Docker por defecto. Sin lockfile pip.

## Constraints

- **Tech stack**: Python 3.11+, FastAPI, parser actual; extender sin reescritura total
- **Seguridad**: Nunca commitear `.env`
- **Compatibilidad**: OpenAI y DeepL; variables de entorno existentes
- **Formato**: Salida Markdown válida; código y URLs intactos
- **Privacidad**: Traducciones y `output/` pueden ser privados — gitignore y avisos UI

## Key Decisions

| Decision | Rationale | Outcome |
| -------- | --------- | ------- |
| v2.0 scope = debt + PDF only | Enfoque acotado post-v1.0 | ✓ Shipped 2026-05-29 |
| WeasyPrint opcional | Deps nativas Cairo/Pango | ✓ `[pdf]` extra, mock tests |
| PDF vía html_export | Reutilizar CSS HTML existente | ✓ Paridad visual CLI |
| SSE auth query token | EventSource sin headers custom | ✓ DEBT-02 |

## Evolution

**Shipped v1.0 (2026-05-29):** NOTEBOOK A→E — tag `v1.0`  
**Shipped v2.0 (2026-05-29):** Tech debt + PDF — tag `v2.0`

## Current State (v2.0 shipped)

- **148 tests** (`pytest tests/ -q`)
- **Stack:** Python 3.11+, FastAPI, SQLite TM, vanilla JS UI, Docker
- **Proveedores:** OpenAI (default), DeepL + fallback opcional
- **Modos:** editor (multi-idioma tabs), archivo, lote SSE, CLI, watch, revisión, export HTML/PDF
- **Despliegue:** `API_TOKEN` + UI Bearer; CORS, límites upload, TTL output/

## Next Milestone Goals

Ejecutar `/gsd-new-milestone` para definir v2.1+. Candidatos en backlog: plugin editor, multi-tenant, Redis jobs, lockfile.

---
*Last updated: 2026-05-31 — v2.1 milestone started*
