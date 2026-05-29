# Phase 3: Batch UX & Cost Control - Context

**Gathered:** 2026-05-29
**Status:** Ready for planning

<domain>
## Phase Boundary

El usuario **controla lotes grandes** con progreso real, cancelación cooperativa, visibilidad de coste antes de confirmar, y recuperación graceful cuando algunos archivos fallan. Esta fase entrega: jobs con ID y progreso vía SSE (in-memory, proceso único), UI con barra global + lista por archivo, cancelación con ZIP parcial opcional, lotes parciales con `errors.json`, y endpoint `POST /api/translate/estimate` con resumen en UI (lote y archivo único).

**Depende de:** Phase 2 (pipeline `translate_markdown()`, validación + `validation.json` en ZIP, UI vanilla).

**Fuera de alcance:** Redis job store (V2-04), multi-destino (Phase 4), diff editorial (Phase 5), auth/CORS (Phase 4), progreso SSE en editor (solo lote), modal de confirmación extra tras estimate, bundler frontend.

</domain>

<decisions>
## Implementation Decisions

### Progreso en UI durante lote (JOB-01, JOB-02)
- **D-01:** Layout: **barra de progreso global** + **lista de archivos** con icono/estado por entrada (pendiente, en curso, OK, error).
- **D-02:** Eventos SSE alineados con NOTEBOOK §5: `file_start`, `file_done`, `segment_progress`, `error`, `complete` — actualizan barra global y lista.
- **D-03:** Progreso SSE **real solo en pestaña Lote**; editor y archivo único mantienen spinner/indicador simple existente (sin SSE).
- **D-04:** Viewport estrecho: mismo contenido **apilado verticalmente** (barra arriba, lista con scroll debajo).
- **D-05:** Sustituir simulación al 30% en `setLoading()` cuando el modo activo es lote con job SSE; barra refleja progreso real del job.

### Lotes con fallos parciales (JOB-04)
- **D-06:** Estrategia **continuar y entregar parcial**: archivos exitosos van al ZIP aunque otros fallen.
- **D-07:** `errors.json` en raíz del ZIP: array de objetos con **`filename`** + **`message`** (sin stack traces ni segmentos por defecto).
- **D-08:** Archivos exitosos incluyen su **`validation.json`** en el ZIP (mismo patrón Phase 2).
- **D-09:** UI al completar: estados por archivo en la lista + resumen final tipo **«8/10 OK — 2 errores»** con botón descargar ZIP parcial.

### Cancelación de job (JOB-03)
- **D-10:** Botón Cancelar requiere **`confirm()`** antes de enviar cancelación al backend.
- **D-11:** Tras cancelar, **ofrecer descarga** de ZIP parcial con archivos ya completados; `errors.json` puede indicar cancelación para archivos no procesados.
- **D-12:** Cancelación **cooperativa**: completar el **archivo en curso** y luego parar (no interrumpir a mitad de archivo salvo imposibilidad técnica).
- **D-13:** Tras cancelar: **reset UI** al estado inicial con **resumen de cancelación** (archivos completados vs pendientes).

### Estimación de coste (COST-01, COST-02)
- **D-14:** Estimate visible en **pestaña Lote y subida de archivo único**; editor traduce directo (texto ya visible, sin paso estimate).
- **D-15:** Formato de resumen NOTEBOOK §10: **«~N segmentos · ~M chars · ~$X (modelo)»** — incluye proveedor/modelo activo.
- **D-16:** Umbral de aviso configurable vía **`.env`** (`ESTIMATE_WARN_USD`, default sugerido ~1.00); banner de advertencia si supera umbral.
- **D-17:** Estimate **inline** junto al botón Traducir — **sin modal de confirmación extra**; el usuario ve números y pulsa Traducir.

### Infraestructura jobs (pre-decidido + research)
- **D-18:** Job registry **in-memory, proceso único** (sin Redis) — coherente con STATE.md y V2-04 deferred.
- **D-19:** Mantener `POST /api/translate/batch` síncrono existente para compatibilidad; jobs SSE como **superficie paralela** (research ARCHITECTURE.md §7).
- **D-20:** Reutilizar `on_progress` en `TranslateOptions` → `translate_segments` para eventos `segment_progress`.

### Claude's Discretion
- Rutas exactas de endpoints jobs (`POST …/jobs`, `GET …/events`, `DELETE …/jobs/{id}`, `GET …/download`).
- Esquema JSON de payloads SSE y forma de `errors.json` (campos opcionales: `code`, `timestamp`).
- Tabla de precios por proveedor/modelo (archivo config vs constantes en código).
- Valor default exacto de `ESTIMATE_WARN_USD` y moneda mostrada.
- Progreso en CLI `md-translate batch` (stderr/TTY) — no discutido; mínimo viable si bajo esfuerzo.
- Deprecación futura del endpoint batch síncrono (mantener en Fase 3).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requisitos y roadmap
- `.planning/REQUIREMENTS.md` — JOB-01…04, COST-01…02
- `.planning/ROADMAP.md` — Phase 3 goal y success criteria
- `.planning/phases/02-trust-qa/02-CONTEXT.md` — validation.json en ZIP, fuera de alcance SSE en Fase 2
- `.planning/phases/01-production-table-stakes/01-CONTEXT.md` — pipeline, `on_progress`, TranslateOptions

### NOTEBOOK y research
- `NOTEBOOK.md` §5 — progreso SSE, eventos, cancelación, descarga ZIP
- `NOTEBOOK.md` §10 — estimación segmentos/chars/coste
- `.planning/research/ARCHITECTURE.md` §7 — diseño jobs SSE, endpoints propuestos, registry in-memory
- `.planning/research/SUMMARY.md` — Phase C deliverables
- `.planning/STATE.md` — SSE in-memory single-process

### Código base
- `src/pipeline.py` — `TranslateOptions.on_progress`, fachada única
- `src/translator.py` — `ProgressCallback`, `translate_segments` chunk progress
- `src/main.py` — batch ZIP actual, integración jobs/estimate
- `static/js/app.js` — `translateBatch()`, `setLoading()` simulado al 30%
- `static/index.html`, `static/css/app.css` — UI vanilla, panel lote

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `translate_markdown()` / `TranslateOptions.on_progress` — cablear progreso real sin cambiar contrato del pipeline
- `translate_segments()` — ya invoca `on_progress(len(result), total)` por chunk
- `POST /api/translate/batch` — ZIP con `validation.json` por archivo (Phase 2)
- Panel colapsable Glosario / Validación — patrón UI para estimate inline o lista de archivos
- `setLoading()` en `app.js` — reemplazar simulación 30% en flujo lote

### Established Patterns
- FastAPI async + `run_in_executor` para traducción bloqueante por archivo
- SSE no existe aún; vanilla JS `EventSource` vía CDN coherente con stack
- Errores HTTP en español; mensajes UI en inglés para demo content
- Sin Redis/ORM; SQLite solo para TM (Phase 1)

### Integration Points
- Nuevo módulo `src/jobs.py` (o equivalente) entre `main.py` y `pipeline`
- `POST /api/translate/estimate` — segmentación + conteo sin llamar proveedor
- UI lote: crear job → EventSource → actualizar barra/lista → download al `complete`
- ZIP builder compartido entre batch síncrono y job async (DRY)

</code_context>

<specifics>
## Specific Ideas

- Progreso: barra global + lista por archivo; eventos NOTEBOOK completos; solo lote con SSE real.
- Fallos: continuar, errors.json minimal (filename + message), validation.json en exitosos, resumen «N/M OK».
- Cancelar: confirm(), ZIP parcial ofrecido, terminar archivo en curso, reset UI con resumen.
- Coste: estimate en lote + archivo; formato «~70 segmentos · ~12 000 chars · ~$0.02 (gpt-4o-mini)»; umbral .env; sin confirm extra.

</specifics>

<deferred>
## Deferred Ideas

- Progreso SSE en editor y traducción de texto pegado — fuera de Fase 3 (spinner simple basta)
- Modal confirmación extra tras estimate — usuario prefiere inline
- Desglose estimate con cache hits / ahorro TM — formato simple NOTEBOOK en Fase 3
- Redis job store — V2-04
- Abortar lote completo al primer error — usuario eligió continuar parcial
- Diff visual / revisión editorial — Phase 5

</deferred>

---

*Phase: 03-batch-ux-cost-control*
*Context gathered: 2026-05-29*
