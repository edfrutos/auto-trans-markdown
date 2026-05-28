# Architecture Patterns — Markdown Auto Translator (Extension)

**Domain:** Brownfield Markdown translation pipeline (segment → translate → reassemble)  
**Researched:** 2026-05-28  
**Scope:** Integración de glosario, memoria de traducción, CLI, validador y SSE sin romper `parser` / `translator` / `main`  
**Overall confidence:** HIGH (basado en código existente + NOTEBOOK/PROJECT); MEDIUM en detalles de job store SSE (patrones estándar FastAPI)

## Executive Recommendation

**No embeber glosario, memoria ni validación dentro de `parser.py`.** El parser debe seguir siendo determinista y libre de I/O. **Centralizar la orquestación en un nuevo módulo `src/pipeline.py`** que hoy está duplicado en `_translate_file_content()` y en los handlers de `src/main.py`. API, CLI y jobs SSE deben llamar **una sola función** `translate_markdown()`; `translator.translate_segments()` recibe hooks opcionales (memoria, glosario, progreso) pero no conoce HTTP ni ZIP.

Mantener el contrato actual:

| Módulo | Entrada | Salida | Regla |
|--------|---------|--------|-------|
| `parser` | `str` Markdown | `list[Segment]`, `dict[int,str]` vía reassemble | Sin red, sin disco, sin glosario |
| `translator` | `list[tuple[int,str]]`, langs | `dict[int,str]` | Solo proveedores MT; extensible con pre/post y cache |
| `pipeline` | contenido + `TranslateOptions` | `TranslateResult` | Orquesta parser → memory → glossary → translator → reassemble → validator |
| `main` | HTTP multipart/JSON | respuestas FastAPI | Delgado: validación HTTP, jobs SSE, estáticos |
| `cli` | argv + archivos | exit codes, archivos en disco | Sin uvicorn; misma `pipeline` |

---

## Current State (Baseline)

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│ static/ UI  │────▶│  src/main.py │────▶│ segment_markdown│────▶│ collect_     │
│  REST       │     │  (FastAPI)   │     │ (parser)        │     │ translatable │
└─────────────┘     └──────┬───────┘     └─────────────────┘     └──────┬───────┘
                           │                                              │
                           │         run_in_executor                      ▼
                           └──────────────────────────────────▶ translate_segments
                                                                  (translator)
                                           reassemble ◀──────────────────┘
```

**Deuda relevante para la extensión:**

- `_translate_file_content()` en `main.py` es el único punto de orquestación reutilizable hoy; los tres endpoints repiten segment → translate → reassemble con variaciones mínimas.
- `translate_segments(..., on_progress=...)` ya existe en `translator.py` pero **nunca se pasa desde `main.py`** (`ProgressEvent` definido pero sin endpoint).
- `md-translate` en `pyproject.toml` apunta a `src.main:run` (servidor), no a CLI de traducción.

---

## Target Architecture

```
                    ┌──────────────────────────────────────────────────────────┐
                    │              Entry surfaces (thin)                        │
                    │  main.py (REST+SSE)  │  cli.py  │  future: watch, jobs   │
                    └───────────┬────────────────────────────────────────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │   src/pipeline.py     │  ◀── NEW: single orchestration
                    │ translate_markdown()  │
                    └───────────┬───────────┘
          ┌─────────────────────┼─────────────────────┐
          ▼                     ▼                     ▼
   ┌─────────────┐      ┌─────────────┐       ┌─────────────┐
   │ src/parser  │      │ src/memory  │       │src/glossary │
   │ (pure MD)   │      │ (SQLite)    │       │ (rules I/O) │
   └─────────────┘      └──────┬──────┘       └──────┬──────┘
                               │                     │
                               └──────────┬──────────┘
                                          ▼
                               ┌─────────────────────┐
                               │  src/translator.py  │
                               │ translate_segments  │
                               └─────────────────────┘
                                          │
                                          ▼
                               ┌─────────────────────┐
                               │ src/validator.py    │  post-reassemble (optional)
                               └─────────────────────┘
```

### Component Boundaries

| Component | Responsibility | Communicates With | Must NOT |
|-----------|----------------|-------------------|----------|
| **`parser`** | Clasificar fragmentos (`PROTECTED` / `TRANSLATABLE`), reensamblar por `index` | `pipeline` only | Llamar APIs, leer glosario/DB, validar estructura global |
| **`glossary`** | Cargar reglas (`glossary.yaml/json`), resolver par `source→target`, aplicar pre/post o inyectar prompt | `pipeline`, `translator` (inyección de texto/prompt) | Parsear Markdown, gestionar HTTP |
| **`memory`** | Lookup/store por hash normalizado + `source_lang` + `target_lang` | `pipeline` (antes/después de `translate_segments`) | Alterar segmentación o índices del parser |
| **`translator`** | Lotes OpenAI/DeepL, chunking, reintentos, `on_progress(done,total)` | `pipeline`, opcional `glossary` helpers | Conocer uploads, ZIP, SSE, rutas de salida |
| **`validator`** | Comparar invariantes estructurales original vs traducido | `pipeline` (post `reassemble`) | Traducir ni llamar proveedores |
| **`pipeline`** | Orquestar flujo completo, métricas (`cache_hits`, segment counts), opciones | Todos los anteriores | Rutas FastAPI, argparse |
| **`main`** | HTTP, CORS, decode uploads, `output/`, ZIP, **job registry + SSE** | `pipeline`, `jobs` helper | Lógica de glosario/memoria inline duplicada |
| **`cli`** | argparse, lectura/escritura filesystem, exit codes CI | `pipeline` | Montar FastAPI ni servir estáticos |
| **`jobs`** (recomendado) | `job_id`, cola de eventos, cancelación, progreso por archivo | `main` (SSE), `pipeline` (callbacks) | Sustituir `translate_segments` |

---

## Integration Contracts

### 1. Parser — sin cambios de contrato para Fase A

Los nuevos módulos **no modifican** la firma pública existente:

- `segment_markdown(content: str) -> list[Segment]`
- `collect_translatable(segments) -> list[tuple[int, str]]`
- `reassemble(segments, translations: dict[int, str]) -> str`

**Futuras extensiones del parser** (frontmatter YAML selectivo, más lenguajes en fences) siguen siendo cambios **solo en `parser.py`** con tests en `tests/test_parser.py`. Glosario y memoria operan sobre **texto de segmentos ya extraídos**, no sobre el AST de Markdown.

### 2. Pipeline — contrato propuesto (facade obligatorio)

```python
# src/pipeline.py (contrato sugerido)

@dataclass(frozen=True)
class TranslateOptions:
    target_lang: str
    source_lang: str | None = None          # None = auto
    glossary_path: Path | None = None       # o Glossary inyectado
    use_memory: bool = True
    validate: bool = False                  # True en CLI --strict
    on_progress: Callable[[int, int], None] | None = None
    on_file_progress: Callable[[str, int, int], None] | None = None  # SSE multi-file

@dataclass
class TranslateResult:
    content: str
    segments_total: int
    segments_translated: int
    cache_hits: int = 0
    validation: ValidationReport | None = None

def translate_markdown(content: str, options: TranslateOptions) -> TranslateResult:
    ...
```

**Flujo interno:**

1. `segments = segment_markdown(content)`
2. `items = collect_translatable(segments)`
3. `cached, pending = memory.partition(items, source, target)` si `use_memory`
4. `pending = glossary.apply_pre(pending)` (placeholders DeepL / marcadores OpenAI)
5. `new_translations = translate_segments(pending, ..., on_progress=options.on_progress)`
6. `new_translations = glossary.apply_post(new_translations)`
7. `memory.store(pending, new_translations, ...)`
8. `all_translations = {**cached, **new_translations}`
9. `output = reassemble(segments, all_translations)`
10. `validation = validator.validate(content, output)` si `validate`
11. return `TranslateResult`

`main._translate_file_content()` pasa a ser un thin wrapper: `await run_in_executor(translate_markdown, ...)`.

### 3. Glossary — dónde enganchar

| Proveedor | Punto de integración | Mecanismo |
|-----------|---------------------|-----------|
| **OpenAI** | `translator._build_user_prompt` o ampliar `SYSTEM_PROMPT` vía `glossary.to_prompt_rules(target_lang)` | Reglas en system/user: «traduce X como Y», «no traduzcas Z» |
| **DeepL** | Pre: `glossary.wrap_placeholders(text)` → `⟦g0⟧...⟦/g0⟧`; Post: restaurar tras batch | Evita que DeepL rompa términos fijos sin glossary API nativa |

**API pública sugerida (`src/glossary.py`):**

- `load(path: Path | None) -> Glossary`
- `apply_pre(items: list[tuple[int,str]], source, target) -> list[tuple[int,str]]`
- `apply_post(translations: dict[int,str]) -> dict[int,str]`
- `to_prompt_appendix(target_lang) -> str` para OpenAI

La UI (panel glosario) solo persiste archivo + llama endpoints que **reutilizan `Glossary.load`**; no duplica reglas en el frontend.

### 4. Translation memory — envolver, no reemplazar `translate_segments`

**Clave:** `sha256(normalize(text) + source_lang + target_lang)` (NOTEBOOK §2).

```python
# src/memory.py
def partition(
    items: list[tuple[int, str]],
    source_lang: str | None,
    target_lang: str,
) -> tuple[dict[int, str], list[tuple[int, str]]]:
    """Devuelve (cached_map, items_still_needed)."""

def store_batch(
    items: list[tuple[int, str]],
    translations: dict[int, str],
    source_lang: str | None,
    target_lang: str,
) -> None:
    ...
```

**Orden crítico:** lookup sobre **texto original del segmento** (antes de placeholders de glosario). Si el glosario usa placeholders, la memoria debe clavear el texto **pre-glosario** o almacenar ambas formas; recomendación: **memoria antes de `apply_pre`**, store con texto origen del segmento.

**Ubicación de datos:** `data/translation_memory.db` (SQLite), gitignored; volumen Docker montado en `data/`.

### 5. Validator — después de reassemble

El validador compara **documento completo** original vs traducido (invariantes de NOTEBOOK §6):

| Check | Implementación |
|-------|----------------|
| Fences | Contar líneas `^```|^~~~` |
| Enlaces / imágenes | Regex conteo `[...](...)` / `![...](...)` |
| Inline code | Contar backticks no escapados (heurística) |
| Encabezados | Profundidad `#` por línea |
| Longitud por segmento | Opcional: re-segmentar y comparar ratios |

```python
# src/validator.py
@dataclass
class ValidationIssue:
    level: Literal["warning", "error"]
    code: str
    message: str

@dataclass
class ValidationReport:
    issues: list[ValidationIssue]
    ok: bool  # no errors (warnings allowed)

def validate(original: str, translated: str) -> ValidationReport:
    ...
```

**Integración:** `pipeline` adjunta informe; `main` lo incluye en JSON de respuesta o en `validation.json` dentro del ZIP de lote. **No bloquea** el pipeline por defecto; `--strict` en CLI o flag UI para bloquear descarga.

### 6. CLI — entry point separado del servidor

**`pyproject.toml` propuesto:**

```toml
[project.scripts]
md-translate = "src.cli:main"
# opcional: md-translate-server = "src.main:run"
```

**`src/cli.py`:** subcomandos `file`, `dir`, `batch`; flags `-t`, `-o`, `--provider`, `--dry-run`, `--no-memory`, `--glossary path`, `--strict`.

- `--dry-run`: solo `segment_markdown` + `collect_translatable` + print counts (sin `translate_segments`).
- Exit codes: `0` OK, `1` errores parciales en dir, `2` fatal (config, provider).

**Sin FastAPI:** importa `pipeline.translate_markdown` directamente en el hilo principal (bloqueante aceptable para CI).

### 7. SSE — jobs sin cambiar el pipeline síncrono

**Principio:** El endpoint actual `POST /api/translate/batch` puede **permanecer** (compatibilidad). SSE es una **superficie paralela** con jobs.

```
POST /api/translate/batch/jobs     → { job_id }
GET  /api/translate/batch/jobs/{id}/events   → text/event-stream
DELETE /api/translate/batch/jobs/{id}       → cancel
GET  /api/translate/batch/jobs/{id}/download → ZIP cuando complete
```

**`src/jobs.py` (recomendado):**

- `BatchJob`: id, files metadata, state, `asyncio.Queue` de eventos
- Registry en memoria: `dict[str, BatchJob]` (proceso único; Redis solo si escala multi-worker)

**Worker por job:** para cada archivo, `await loop.run_in_executor(None, partial(translate_markdown, content, options))` con:

- `on_progress` → evento `segment_progress` (done/total del archivo)
- `on_file_progress` o wrapper → `file_start`, `file_done`, `error`

Eventos alineados con NOTEBOOK §5: `file_start`, `file_done`, `segment_progress`, `error`, `complete`.

**Conexión con `translator`:** pasar `on_progress` desde `TranslateOptions` hasta `translate_segments` (ya soportado).

**UI:** `EventSource` en `static/js/app.js`; barra real sustituye simulación al 30%.

---

## Data Flow (Extended Single File)

```
content (str)
    │
    ▼
segment_markdown ──► segments[]
    │
    ▼
collect_translatable ──► items[(index, text)]
    │
    ▼
memory.partition ──► cached{index: text} + pending[]
    │
    ▼
glossary.apply_pre(pending) ──► pending'[]
    │
    ▼
translate_segments(pending', on_progress) ──► new_map{index: text}
    │
    ▼
glossary.apply_post(new_map)
    │
    ▼
memory.store_batch(pending, new_map)   # claves sobre texto origen
    │
    ▼
merge cached + new_map ──► translations{}
    │
    ▼
reassemble(segments, translations) ──► output (str)
    │
    ▼
validator.validate(content, output) ──► ValidationReport (optional)
```

**Batch con SSE:** repetir el diagrama por archivo; agregar capa ZIP en `main`/`jobs`, no en `pipeline`.

---

## Data Flow (HTTP vs CLI)

| Paso | REST (existente) | REST (SSE job) | CLI |
|------|------------------|----------------|-----|
| Decode | `main._decode_upload` | igual | `Path.read_text` |
| Translate | `pipeline` vía executor | `pipeline` en executor por archivo | `pipeline` sync |
| Persist | `output/` UUID | ZIP en job al `complete` | `-o` path |
| Progress | N/A | SSE events | stderr TTY o `--quiet` |
| Validation | opcional en JSON | `validation.json` en ZIP | stdout / exit 1 si `--strict` |

---

## Patterns to Follow

### Facade pipeline (obligatorio antes de CLI/SSE)

**What:** Un solo módulo orquesta el flujo; entrypoints delgados.  
**When:** Antes de glosario, memoria, CLI o SSE.  
**Why:** Evita cuatro copias de segment→translate→reassemble y garantiza glosario/memoria en editor, archivo, lote y CI.

### Index-keyed translations (mantener)

**What:** `dict[int, str]` keyed por `Segment.index`, no por posición en lista filtrada.  
**When:** Siempre; memoria y glosario deben preservar índices al partir lotes.

### Progress at chunk boundary

**What:** `on_progress(len(result), total)` ya se invoca por chunk en `translate_segments`.  
**When:** SSE segment-level; no hace falta instrumentar el parser.

### Optional strict validation

**What:** Warnings en UI; errors solo con opt-in.  
**When:** Lotes grandes — un falso positivo no debe abortar 20 archivos.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Glosario dentro de `segment_markdown`

**What:** Sustituir términos durante el scan línea a línea.  
**Why bad:** Rompe índices, mezcla estructura con negocio, duplica lógica OpenAI vs DeepL.  
**Instead:** Pre/post sobre `collect_translatable` output.

### Anti-Pattern 2: Memoria dentro de `translate_segments` sin partición explícita

**What:** Consultar SQLite por cada string dentro del loop de chunks sin separar cached/pending.  
**Why bad:** Dificulta testing, `--dry-run`, y métricas de cache hit.  
**Instead:** `memory.partition` en `pipeline` antes de llamar al traductor.

### Anti-Pattern 3: SSE que reimplementa traducción

**What:** Duplicar OpenAI/DeepL en handlers de eventos.  
**Why bad:** Divergencia de comportamiento respecto a POST síncrono.  
**Instead:** Jobs llaman `translate_markdown` idéntico.

### Anti-Pattern 4: Romper `POST /api/translate/batch` al introducir jobs

**What:** Sustituir endpoint síncrono por solo SSE.  
**Why bad:** Rompe clientes y scripts actuales.  
**Instead:** Añadir rutas `/batch/jobs/*`; UI migra gradualmente.

### Anti-Pattern 5: Validator pre-reassemble

**What:** Validar segmentos sueltos sin contexto de fences globales.  
**Why bad:** No detecta desbalance de ``` entre segmentos.  
**Instead:** Validar documentos completos post-`reassemble`.

---

## Suggested Build Order

Orden pensado para **no romper el pipeline** y maximizar reutilización (alineado con NOTEBOOK Fase A→B→C, refinado por dependencias técnicas):

| Order | Deliverable | Rationale | Touches |
|-------|-------------|-----------|---------|
| **1** | `src/pipeline.py` + refactor `main._translate_file_content` | Base común antes de cualquier feature; tests de integración con mock translator | `main.py` |
| **2** | `src/memory.py` + wire en pipeline | Beneficia editor/archivo/lote/CLI de inmediato; sin UI nueva obligatoria | `pipeline`, `.gitignore` `data/` |
| **3** | `src/glossary.py` + wire en pipeline/translator | Depende de pipeline; OpenAI prompt + DeepL placeholders | `translator.py` (mínimo), `pipeline` |
| **4** | `src/cli.py` + fix `pyproject.toml` scripts | Consume pipeline estable; `md-translate serve` opcional | `pyproject.toml` |
| **5** | `src/validator.py` + flags en pipeline/CLI | Post-`reassemble`; no bloquea 1–4 | `pipeline`, respuestas API opcionales |
| **6** | `src/jobs.py` + SSE routes + UI EventSource | Requiere `on_progress` end-to-end; mantener POST batch legacy | `main.py`, `static/js/app.js` |

**Paralelizable después de (1):** (2) memoria y (5) validador en ramas separadas si el equipo divide trabajo; (3) glosario debe ir antes o con (4) CLI si la CLI expone `--glossary`.

**Explícitamente después de este milestone slice:** preview Markdown (Fase B UI), multi-destino, Docker, frontmatter — no bloquean la integración arquitectónica anterior.

---

## Scalability Considerations

| Concern | Single user / local | 10 concurrent API users | Multi-worker deploy |
|---------|----------------------|-------------------------|---------------------|
| Translation | `run_in_executor` + thread pool | Cola implícita en executor; latencia lineal | Mismo; considerar límite de workers |
| Memory SQLite | Archivo local, WAL | Contención leve; suficiente para docs | **Riesgo:** cada worker DB distinta → usar Redis o DB central |
| SSE jobs | `dict` en memoria OK | OK en un proceso uvicorn | **Requiere** Redis/pub-sub + sticky sessions o un worker |
| `output/` TTL | Manual / cron | Disco crece | Volumen + job cleanup |

---

## File Layout (Target)

```
src/
  parser.py          # unchanged role
  translator.py      # providers + on_progress; glossary hooks
  pipeline.py        # NEW orchestration
  glossary.py        # NEW
  memory.py          # NEW
  validator.py       # NEW
  jobs.py            # NEW (SSE registry)
  cli.py             # NEW
  main.py            # thin HTTP + mount static
data/                # translation_memory.db (gitignored)
glossary.yaml        # optional project default
tests/
  test_parser.py
  test_pipeline.py   # NEW
  test_memory.py
  test_glossary.py
  test_validator.py
```

---

## Migration Checklist (Non-Breaking)

- [ ] Extraer `translate_markdown` sin cambiar respuestas JSON de `/api/translate` y `/api/translate/file`
- [ ] Mantener `POST /api/translate/batch` hasta que UI use jobs
- [ ] Pasar `on_progress` en executor cuando se añada SSE (mismo comportamiento si `None`)
- [ ] Documentar `md-translate` → CLI; servidor vía `uvicorn` / subcomando `serve`
- [ ] Añadir `data/` y `glossary.yaml` a `.gitignore` si contienen contenido local

---

## Sources

- Código: `src/main.py`, `src/parser.py`, `src/translator.py` (firmas y flujo verificados 2026-05-28)
- Producto: `.planning/PROJECT.md`, `NOTEBOOK.md` (fases A–C, criterios glosario/memoria/CLI/validator/SSE)
- Mapa brownfield: `.planning/codebase/ARCHITECTURE.md`
- Patrón SSE FastAPI: práctica común `EventSourceResponse` + background task (MEDIUM confidence sin implementación en repo aún)

---

*Architecture research for milestone extension — 2026-05-28*
