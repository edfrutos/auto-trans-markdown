# Roadmap: MarkDown Auto Translator — NOTEBOOK Milestone

## Overview

Brownfield extension del MVP hacia el NOTEBOOK completo (fases A→E). Se parte de un pipeline segment → translate → reassemble ya operativo y se cierra deuda de producción (hardening, glosario, memoria, CLI), luego confianza (validación, preview), UX de lote (SSE, coste), escala de equipo (multi-destino, Docker) y flujo editorial (revisión, diff, watch). Orden de ejecución: Phase 0 (Pre-A hardening) → 1 → 2 → 3 → 4 → 5.

## Phases

**Phase Numbering:**
- **Phase 0 (Pre-A)**: Hardening del MVP antes de ampliar funcionalidad
- **Phases 1–5**: NOTEBOOK A→E (table stakes → trust → batch UX → team scale → editorial)

- [x] **Phase 0: MVP Hardening** - Contratos fiables, UTF-8 estricto, idiomas por proveedor, tests de integración
- [x] **Phase 1: Production Table Stakes** - Pipeline unificado, glosario, memoria SQLite, CLI `md-translate`
- [x] **Phase 2: Trust & QA** - Validación post-traducción, preview renderizada, parser ampliado, frontmatter selectivo
- [x] **Phase 3: Batch UX & Cost Control** - Jobs SSE con progreso real, cancelación, lotes parciales, estimación de coste
- [x] **Phase 4: Team Scale** - Multi-destino, Docker, hardening de despliegue (CORS, límites, TTL)
- [x] **Phase 5: Editorial & Pro Workflow** - Revisión, fallback, diff, watch, árbol de docs, tono, historial, export HTML

## Phase Details

### Phase 0: MVP Hardening
**Goal**: El pipeline existente es fiable y verificable antes de añadir glosario, memoria y CLI
**Depends on**: Nothing (first phase)
**Requirements**: HARD-01, HARD-02, HARD-03, HARD-04
**Success Criteria** (what must be TRUE):
  1. Usuario recibe error explícito cuando una traducción devuelve menos segmentos de los solicitados (sin salida parcial silenciosa)
  2. Usuario recibe error claro al subir archivos que no son UTF-8 válido
  3. La lista de idiomas en UI/API refleja solo las capacidades del proveedor activo (OpenAI vs DeepL)
  4. Tests de integración cubren `translate_segments`, endpoints API y contrato de reassemble
**Plans:** 4/4 plans complete

Plans:
- [x] 00-01-PLAN.md — Rechazo de traducciones incompletas (502, validación OpenAI/DeepL)
- [x] 00-02-PLAN.md — UTF-8 estricto en uploads (400, sin latin-1)
- [x] 00-03-PLAN.md — Idiomas filtrados por proveedor + validación en todas las rutas + UI
- [x] 00-04-PLAN.md — Tests de integración con mocks (traductor, API, reassemble)

### Phase 1: Production Table Stakes
**Goal**: Usuario puede automatizar traducciones con terminología consistente y memoria persistente vía CLI y web
**Depends on**: Phase 0
**Requirements**: PIPE-01, GLOS-01, GLOS-02, GLOS-03, TM-01, TM-02, TM-03, CLI-01, CLI-02, CLI-03, CLI-04, CLI-05
**Success Criteria** (what must be TRUE):
  1. Usuario obtiene el mismo comportamiento de traducción vía API, CLI y web (fachada `translate_markdown()` única)
  2. Usuario define términos en `glossary.yaml` y los gestiona desde la UI; el glosario se aplica en editor, archivo único y lote
  3. Segmentos repetidos se sirven desde cache SQLite sin llamar al proveedor; el usuario puede limpiar la memoria
  4. Usuario ejecuta `md-translate file|dir|batch` con `--dry-run`; `md-translate serve` arranca el servidor web por separado
**Plans:** 5/5 plans complete

Plans:
- [x] 01-01-PLAN.md — Fachada pipeline.py + refactor main.py (PIPE-01)
- [x] 01-02-PLAN.md — Memoria SQLite + integración pipeline + API clear (TM-01, TM-02, TM-03)
- [x] 01-03-PLAN.md — Glosario YAML + integración pipeline + API CRUD (GLOS-01, GLOS-03)
- [x] 01-04-PLAN.md — Panel glosario UI + botón limpiar memoria (GLOS-02, TM-03 UI)
- [x] 01-05-PLAN.md — CLI Typer md-translate + entry points + tests (CLI-01 … CLI-05)
**UI hint**: yes

### Phase 2: Trust & QA
**Goal**: Usuario puede confiar en que la traducción no rompió estructura y puede revisarla visualmente
**Depends on**: Phase 1
**Requirements**: VAL-01, VAL-02, VAL-03, PREV-01, PREV-02, PARS-01, PARS-02, FM-01, FM-02
**Success Criteria** (what must be TRUE):
  1. Usuario ve informe de validación (fences, enlaces, imágenes) tras traducir en UI y en ZIP de lote
  2. Usuario previsualiza Markdown renderizado (original y traducido) con HTML sanitizado
  3. Comentarios traducibles en fences Python, JS/TS y HTML; claves técnicas YAML nunca se traducen
  4. Usuario traduce campos whitelist de frontmatter (`title`, `description`, `summary`) sin alterar slug/fecha/layout
  5. Modo `--strict` en CLI bloquea exportación si la validación falla
**Plans:** 5 plans

Plans:
- [x] 02-01-PLAN.md — Validador post-traducción validator.py + tests (VAL-01)
- [x] 02-02-PLAN.md — Parser comentarios python/js/html + frontmatter YAML (PARS-01, PARS-02, FM-01, FM-02)
- [x] 02-03-PLAN.md — Pipeline + API + validation.json en ZIP lote (VAL-02)
- [x] 02-04-PLAN.md — CLI --strict bloquea export en error (VAL-03)
- [x] 02-05-PLAN.md — Preview marked+DOMPurify + panel Validación UI (PREV-01, PREV-02, VAL-02 UI)
**UI hint**: yes

### Phase 3: Batch UX & Cost Control
**Goal**: Usuario controla lotes grandes con progreso real, cancelación y visibilidad de coste
**Depends on**: Phase 2
**Requirements**: JOB-01, JOB-02, JOB-03, JOB-04, COST-01, COST-02
**Success Criteria** (what must be TRUE):
  1. Usuario inicia lote y ve progreso real (archivo actual, segmentos, porcentaje) vía SSE
  2. Usuario cancela un job en curso desde la UI
  3. Lote con fallos parciales devuelve ZIP con archivos exitosos más `errors.json`
  4. Usuario ve estimación de segmentos, caracteres y coste antes de confirmar traducción grande
**Plans:** 4 plans

Plans:
- [x] 03-01-PLAN.md — estimate.py + POST /api/translate/estimate (COST-01)
- [x] 03-02-PLAN.md — batch_zip + jobs SSE + cancel + partial ZIP (JOB-01, JOB-03, JOB-04)
- [x] 03-03-PLAN.md — UI progreso SSE + cancel + estimate inline (JOB-02, COST-02)
- [x] 03-04-PLAN.md — Tests integración + README (JOB-*, COST-*)
**UI hint**: yes

### Phase 4: Team Scale
**Goal**: Equipos despliegan y traducen a varios idiomas de forma segura y reproducible
**Depends on**: Phase 3
**Requirements**: MULTI-01, MULTI-02, DOCKER-01, DOCKER-02, SEC-01, SEC-02
**Success Criteria** (what must be TRUE):
  1. Usuario selecciona varios idiomas destino y recibe ZIP con archivos `stem.{lang}.md`
  2. Usuario despliega con `Dockerfile` multi-stage y `docker-compose.yml` con volúmenes para `data/` y `output/`
  3. Instancia desplegada respeta allowlist CORS, bind address, límite de upload y TTL/limpieza de `output/` configurables
**Plans:** 5 plans

Plans:
- [x] 04-01-PLAN.md — target_langs + API/jobs/estimate multi-idioma (MULTI-01, MULTI-02)
- [x] 04-02-PLAN.md — deployment.py CORS/upload/TTL (SEC-01, SEC-02)
- [x] 04-03-PLAN.md — UI chips + progreso anidado (MULTI-01 UI)
- [x] 04-04-PLAN.md — CLI `-t es,en,fr` paridad (MULTI-01, MULTI-02)
- [x] 04-05-PLAN.md — Docker + README + integración (DOCKER-*, traceability)
**UI hint**: yes

### Phase 5: Editorial & Pro Workflow
**Goal**: Usuario refina traducciones, automatiza flujos editoriales y exporta resultados enriquecidos
**Depends on**: Phase 4
**Requirements**: REV-01, REV-02, FALL-01, DIFF-01, WATCH-01, TREE-01, TONE-01, HIST-01, EXPORT-01
**Success Criteria** (what must be TRUE):
  1. Usuario edita segmentos traducidos en modo revisión antes de exportar; segmentos dudosos destacados
  2. Traducción hace fallback automático DeepL → OpenAI cuando DeepL falla por cuota o idioma
  3. Usuario compara original vs traducción con diff lado a lado (texto traducible resaltado)
  4. Usuario ejecuta `md-translate watch` o traduce árbol de docs respetando `.gitignore` del proyecto
  5. Usuario elige tono formal/informal; historial opt-in sin secretos; export HTML autocontenido opcional
**Plans:** 6 plans

Plans:
- [x] 05-01-PLAN.md — Fallback DeepL→OpenAI (FALL-01)
- [x] 05-02-PLAN.md — Tono formal/informal API/CLI/UI (TONE-01)
- [x] 05-03-PLAN.md — Modo revisión draft/finalize (REV-01, REV-02)
- [x] 05-04-PLAN.md — Vista diff lado a lado (DIFF-01)
- [x] 05-05-PLAN.md — CLI watch + gitignore tree (WATCH-01, TREE-01)
- [x] 05-06-PLAN.md — Historial opt-in + export HTML (HIST-01, EXPORT-01)
**UI hint**: yes

## Progress

**Execution Order:**
0 → 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. MVP Hardening | 4/4 | Complete    | 2026-05-28 |
| 1. Production Table Stakes | 5/5 | Complete | 2026-05-28 |
| 2. Trust & QA | 5/5 | Complete | 2026-05-29 |
| 3. Batch UX & Cost Control | 4/4 | Complete | 2026-05-29 |
| 4. Team Scale | 5/5 | Complete | 2026-05-29 |
| 5. Editorial & Pro Workflow | 6/6 | Complete | 2026-05-29 |

---
*Roadmap created: 2026-05-28 — NOTEBOOK milestone (brownfield)*
