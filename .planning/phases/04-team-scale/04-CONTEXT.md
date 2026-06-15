# Phase 4: Team Scale - Context

**Gathered:** 2026-05-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Equipos **despliegan y traducen a varios idiomas de forma segura y reproducible**. Esta fase entrega: selección multi-destino en UI y CLI, salida ZIP/archivos `stem.{lang}.md`, empaquetado Docker (Dockerfile + compose con volúmenes `data/` y `output/`), y hardening de instancia (CORS allowlist, límites de upload, TTL/limpieza de `output/`).

**Depende de:** Phase 3 (jobs SSE, estimate, batch_zip, pipeline unificado).

**Fuera de alcance:** Auth multi-tenant / API key por usuario (V2-03), Redis multi-worker (V2-04), fallback DeepL→OpenAI (Phase 5), revisión editorial (Phase 5), auth obligatorio en v1.

</domain>

<decisions>
## Implementation Decisions

### Multi-destino en UI (MULTI-01)

- **D-01:** **Todos los modos** soportan multi-destino: editor, archivo único y lote.
- **D-02 (Claude):** Selector destino = **chips/tags removibles** debajo del control principal (más claro que `<select multiple>` para 2–5 idiomas). Mantener compatibilidad con un solo idioma seleccionado.
- **D-03 (Claude):** Estimate multi-idioma = **línea agregada** «~N segmentos · ~M chars · ~$X total (K idiomas)»; si supera umbral, un aviso; desglose por idioma solo en tooltip o texto secundario opcional (no modal).
- **D-04 (Claude):** Progreso SSE en lote = **lista por archivo con sub-entradas por idioma** (pendiente/activo/OK/error), alineado con orden backend archivo→idiomas.

### Multi-destino en backend (MULTI-02)

- **D-05:** Orden de procesamiento: **por archivo, luego todos los idiomas destino** (`file_then_lang`).
- **D-06:** Contrato API: **aceptar ambos** — `target_lang` (string, un idioma) y `target_langs` (lista); un solo `target_lang` equivale a lista de uno. Aplicar en translate, batch, jobs, estimate.
- **D-07 (Claude):** ZIP multi-idioma = **plano en raíz** con nombres `stem.{lang}.md` (literal MULTI-02); `validation.json` por archivo×idioma como `{stem}.validation.json` o `{stem}.{lang}.validation.json` — planner elige convención consistente con Phase 2.
- **D-08 (Claude):** Concurrencia entre idiomas = **`MULTI_LANG_CONCURRENCY` en .env**, default **1** (serial); subir solo si documentado (rate limits).
- **D-09:** Jobs SSE existentes se **extienden** con eventos que incluyan `target_lang` en `file_start` / `file_done` / `segment_progress` cuando aplique multi-destino.
- **D-10:** Memoria de traducción **compartida entre idiomas** del mismo origen (NOTEBOOK §9) — lookup/store por par (source, target) sin duplicar lógica.

### Docker y despliegue (DOCKER-01, DOCKER-02)

- **D-11:** Objetivo de despliegue: **equipo interno (LAN) y VPS/prod** — compose documentado para ambos; perfil dev opcional vs prod sin reload.
- **D-12 (Claude):** Lockfile = **`requirements.txt`** en imagen (brownfield); no introducir `uv.lock` en Fase 4 salvo que research demuestre bajo coste — DOCKER-01 se cumple con multi-stage + non-root + deps pinneadas en build.
- **D-13 (Claude):** `docker-compose.yml` = servicio app + volúmenes **`data/`** y **`output/`** + `.env`; **healthcheck** `GET /api/languages` (NOTEBOOK §11).
- **D-14:** Puerto publicado en compose: **5400 por defecto** (menos conflictos que 8000); mapeo configurable vía `.env` (`PORT=5400`, `HOST=0.0.0.0` en contenedor).
- **D-15:** Imagen **non-root**; base slim; objetivo **< 200 MB** si es viable (NOTEBOOK §11).

### Hardening de despliegue (SEC-01, SEC-02)

- **D-16:** CORS = **`CORS_ORIGINS`** comma-separated; si vacío en prod, default restrictivo (`http://127.0.0.1:5400`, `http://localhost:5400`); `*` solo documentado para dev local explícito.
- **D-17:** Upload limits = **ambos**: `MAX_UPLOAD_MB` por archivo **y** `MAX_BATCH_UPLOAD_MB` tope total por request lote/jobs.
- **D-18:** Limpieza `output/` = **barrido al arrancar** + **tarea periódica**; TTL vía `OUTPUT_TTL_HOURS` (default razonable, ej. 24).
- **D-19 (Claude):** **Sin auth obligatorio** en Fase 4. Opcional: si `API_TOKEN` está definido en `.env`, exigir header `Authorization: Bearer …` en rutas `/api/*` — default sin token (coherente con REQUIREMENTS «SaaS sin auth v1»).

### CLI multi-idioma (paridad MULTI-01/02)

- **D-20:** **Paridad web** — `md-translate file|dir|batch` soporta multi-destino.
- **D-21:** Sintaxis **`-t es,en,fr`** (coma separada) además de `-t es` único.
- **D-22:** Salida CLI = **`stem.{lang}.md`** (misma convención que web/ZIP).

### Claude's Discretion

- Convención exacta de `validation.json` multi-idioma en ZIP.
- Perfiles compose `dev`/`prod` (nombres y flags).
- Implementación de chips UI (vanilla JS, sin bundler).
- Valor default exacto de TTL y límites MB.
- Si implementar `API_TOKEN` opcional o dejarlo documentado-only para Fase 4 mínima.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requisitos y roadmap

- `.planning/REQUIREMENTS.md` — MULTI-01…02, DOCKER-01…02, SEC-01…02
- `.planning/ROADMAP.md` — Phase 4 goal y success criteria
- `.planning/STATE.md` — sin auth v1; hardening parcial Fase 4
- `.planning/phases/03-batch-ux-cost-control/03-CONTEXT.md` — jobs SSE, batch_zip, estimate; multi-destino explícitamente Fase 4

### NOTEBOOK y research

- `NOTEBOOK.md` §9 — multi-destino, UI multi-select, `target_langs`, concurrencia
- `NOTEBOOK.md` §11 — Docker, compose, healthcheck, imagen slim, volúmenes
- `.planning/research/SUMMARY.md` — Phase D deliverables

### Código base

- `src/main.py` — CORS `allow_origins=["*"]`, batch/jobs/estimate endpoints
- `src/jobs.py` — worker SSE, cancel, partial ZIP
- `src/batch_zip.py` — builder ZIP compartido
- `src/pipeline.py` — `translate_markdown()`, TM lookup/store
- `src/cli.py` — Typer, flags `-t`
- `static/js/app.js` — `#target-lang`, translateBatch EventSource
- `static/index.html` — selector idioma destino único
- `.env.example` — variables existentes HOST/PORT/ESTIMATE_WARN_USD

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `build_batch_zip` / jobs worker — extender para múltiples `out_name` por idioma
- `estimate_files` / `estimate_markdown` — agregar loop `target_langs`
- `_unique_zip_name` — generalizar a `stem.{lang}.md`
- `TranslateOptions` + TM — reutilizar por cada par (content, target_lang)
- CORS middleware ya montado — sustituir origins por env

### Established Patterns

- FastAPI Form `target_lang` + JSON body — añadir `target_langs` sin romper clientes
- Vanilla JS `state` + `els` — chips encajan en panel compartido source/target
- Tests con mocks en `conftest.py` — extender API tests multi-lang
- Sin lockfile hoy — Docker usa `pip install -r requirements.txt`

### Integration Points

- UI: reemplazar/ampliar `#target-lang` → lista chips + hidden/API payload `target_langs[]`
- API: todos los endpoints de traducción y estimate
- CLI: parser `-t` comma-split
- Nuevo módulo opcional `src/config.py` o `src/security.py` para CORS/TTL/limits
- Startup hook en `main.py` para sweep output/ + background task

</code_context>

<specifics>
## Specific Ideas

- Puerto Docker **5400** por defecto (usuario prefiere evitar 8000 ocupado).
- Despliegue tanto LAN interna como VPS documentado.
- Progreso lote: sub-entradas por idioma bajo cada archivo.
- CLI: `-t es,en,fr` con salida `doc.es.md`, `doc.en.md`.

</specifics>

<deferred>
## Deferred Ideas

- Auth multi-tenant / API keys por usuario — V2-03
- Redis job store multi-worker — V2-04
- Fallback automático DeepL → OpenAI — Phase 5 (FALL-01)
- Carpetas por idioma en ZIP (`es/doc.md`) — usuario prefirió convención plana MULTI-02
- `uv.lock` — diferido salvo decisión explícita en plan; brownfield usa requirements.txt

</deferred>

---

*Phase: 04-team-scale*
*Context gathered: 2026-05-29*
