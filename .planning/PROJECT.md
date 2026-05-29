# MarkDown Auto Translator

## What This Is

Traductor de archivos Markdown que preserva formato y bloques de código, orientado a documentación técnica y equipos que localizan docs sin romper sintaxis. Incluye interfaz web (editor, archivo, lote), API FastAPI, CLI `md-translate`, glosario, memoria de traducción y proveedores OpenAI o DeepL. El milestone NOTEBOOK (fases A→E) está **completo** (fases GSD 0–5).

## Core Value

Traducir **solo el texto dirigido al usuario** al idioma destino **sin alterar Markdown ni código**, con coherencia terminológica y coste predecible en lotes grandes.

## Requirements

### Validated

**MVP + Phase 0 (Hardening)**

- ✓ Segmentación Markdown protegido vs traducible — `src/parser.py`
- ✓ Preservación de bloques ```, inline `code`, frontmatter, indentados — `src/parser.py`
- ✓ Comentarios traducibles en shell, Python, JS/TS, HTML — `src/parser.py`
- ✓ Traducción por lotes vía OpenAI (JSON) o DeepL — `src/translator.py`
- ✓ Rechazo traducciones incompletas (HTTP 502) — Phase 0 / HARD-01
- ✓ UTF-8 estricto en uploads (HTTP 400) — Phase 0 / HARD-02
- ✓ Idiomas filtrados por proveedor activo — Phase 0 / HARD-03
- ✓ Tests integración traductor + API + reassemble — Phase 0 / HARD-04

**Phase 1 — Production table stakes**

- ✓ Fachada `translate_markdown()` (API + CLI + web) — PIPE-01
- ✓ Glosario YAML + UI + pipeline — GLOS-01 … GLOS-03
- ✓ Memoria SQLite + clear UI/CLI/API — TM-01 … TM-03
- ✓ CLI `file|dir|batch`, `--dry-run`, `serve` — CLI-01 … CLI-05

**Phase 2 — Trust & QA**

- ✓ Validación post-traducción + informe UI/ZIP — VAL-01, VAL-02
- ✓ CLI `--strict` — VAL-03
- ✓ Preview marked + DOMPurify — PREV-01, PREV-02
- ✓ Frontmatter YAML selectivo — FM-01, FM-02

**Phase 3 — Batch UX & cost**

- ✓ Jobs SSE, cancelación, ZIP parcial — JOB-01 … JOB-04
- ✓ Estimate API + UI — COST-01, COST-02

**Phase 4 — Team scale**

- ✓ Multi-destino API/CLI/UI — MULTI-01, MULTI-02
- ✓ Docker + compose — DOCKER-01, DOCKER-02
- ✓ CORS, límites upload, TTL `output/`, `API_TOKEN` opcional — SEC-01, SEC-02

**Phase 5 — Editorial & pro**

- ✓ Modo revisión draft/finalize — REV-01, REV-02
- ✓ Fallback DeepL → OpenAI — FALL-01
- ✓ Diff por segmento — DIFF-01
- ✓ `watch`, árbol con `.gitignore` — WATCH-01, TREE-01
- ✓ Tono formal/informal — TONE-01
- ✓ Historial opt-in (metadatos) — HIST-01
- ✓ Export HTML — EXPORT-01

## Current Milestone: v2.0 Production Polish & PDF

**Goal:** Cerrar deuda técnica del audit v1.0 y añadir export PDF sin reabrir arquitectura core.

**Target features:**
- Paridad `--tone` en CLI batch ZIP; UI con Bearer para despliegues protegidos
- Editor multi-idioma usable (ver/descargar cada traducción)
- Export PDF desde CLI y web (dependencia opcional documentada)

**Deferred to v2.1+:** Redis jobs, multi-tenant, plugin editor.

### Active (v2.0)

- [x] Tech debt closure — DEBT-01 … DEBT-04
- [x] PDF export — PDF-01 … PDF-04

### Active (v2.1+ / future)

- [ ] Plugin Obsidian o VS Code — V2-02
- [ ] Multi-tenant con API key por usuario — V2-03
- [ ] Redis job store para multi-worker — V2-04

### Out of Scope

- Traducción directa PDF/DOCX — pipeline distinto; usar MD intermedio
- MT offline sin LLM como calidad principal — inferior en modismos
- Reescritura libre del documento — fuera del core value

## Context

**Estado actual:** Pipeline segment → translate → reassemble con fachada `pipeline.py`. FastAPI + UI estática. Memoria SQLite en `data/`. Glosario en `glossary.yaml`. Jobs de lote in-memory con SSE (single-process). **137 tests** en `tests/`. Despliegue Docker documentado.

**Usuarios objetivo:** Desarrolladores, redactores técnicos y equipos que traducen README, docs y artículos Markdown manteniendo código y estructura.

**Deuda / límites conocidos:** Jobs SSE no persisten entre reinicios (V2-04). Auth opcional vía `API_TOKEN` Bearer, no multi-tenant. Sin lockfile pip (`requirements.txt` con pins mínimos `>=`).

## Constraints

- **Tech stack**: Python 3.11+, FastAPI, parser actual; extender sin reescritura total
- **Seguridad**: Nunca commitear `.env`; documentación de planificación sin claves reales
- **Compatibilidad**: OpenAI y DeepL como proveedores; variables de entorno existentes
- **Formato**: Salida siempre Markdown válido; código y URLs intactos
- **Privacidad**: Traducciones y `output/` pueden contener docs privados — gitignore y avisos en UI

## Key Decisions

| Decision | Rationale | Outcome |
| -------- | --------- | ------- |
| Alcance milestone = NOTEBOOK completo (A→E) | Elección explícita del usuario en GSD init | ✓ Complete — phases 0–5 |
| Mapear codebase antes de planificar | Brownfield con código existente | ✓ `.planning/codebase/` |
| OpenAI por defecto, DeepL alternativo | Ya implementado; glosario favorece LLM | ✓ Good |
| Memoria vía SQLite local | NOTEBOOK §2; mínimo acoplamiento | ✓ `data/translation_memory.db` |
| Jobs in-memory + SSE | Simplicidad single-process Uvicorn | ✓ Good; Redis deferred V2-04 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**Shipped v1.0 (2026-05-29):** NOTEBOOK fases A→E completas. Ver `.planning/MILESTONES.md` y tag `v1.0`.

## Current State (v1.0 shipped)

- **137 tests** (`pytest tests/ -q`)
- **Stack:** Python 3.11+, FastAPI, SQLite TM, vanilla JS UI, Docker
- **Proveedores:** OpenAI (default), DeepL + fallback opcional
- **Modos:** editor, archivo, lote SSE, CLI, watch, revisión editorial

## Next Milestone Goals (v2.0 — active)

Ver `.planning/REQUIREMENTS.md` y `.planning/ROADMAP.md` fases 6–7.

---
*Last updated: 2026-05-29 — v2.0 milestone initialized*
