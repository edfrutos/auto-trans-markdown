# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Commands

```bash
# Backend Python — instalar deps
uv sync                          # con lockfile (reproducible)
pip install -r requirements.txt  # alternativa plana

# Servidor de desarrollo
md-translate serve               # puerto 5400 por defecto
python -m src.main               # equivalente

# Tests
pytest tests/ -q                 # suite completa (148 tests)
pytest tests/test_parser.py -q   # módulo específico
pytest tests/ -k "test_segment"  # filtro por nombre

# CLI
md-translate file input.md --target es
md-translate dir ./docs --target es,fr --out ./translated

# App macOS v3.0 — preparar python-bundle (ejecutar UNA VEZ antes de abrir Xcode)
./scripts/build-python-bundle.sh

# App macOS — build y run
# Abrir macos/MDTranslator/MDTranslator.xcodeproj en Xcode, luego ⌘B + ⌘R
# Ver sección "macOS App (v3.0)" para configuración requerida de Xcode
```

<!-- GSD:project-start source:PROJECT.md -->
## Project

**MarkDown Auto Translator**

Traductor de archivos Markdown que preserva formato y bloques de código,
orientado a documentación técnica y equipos que localizan docs sin romper
sintaxis. Incluye interfaz web (editor, archivo, lote), API FastAPI, CLI Typer y
proveedores OpenAI o DeepL.

**Versión actual:** v2.0 (shipped 2026-05-29). v3.0 en progreso: embedding
Python en app nativa Swift/macOS (fases 9–12).

**Core Value:** Traducir **solo el texto dirigido al usuario** al idioma destino
**sin alterar Markdown ni código**, con coherencia terminológica (glosario +
memoria TM) y coste predecible en lotes grandes.

### Constraints

- **Tech stack**: Python 3.11+, FastAPI, Typer, parser actual; extender sin
  reescritura total
- **Seguridad**: Nunca commitear `.env`; API_TOKEN para auth; API keys en
  Keychain (v3.0)
- **Compatibilidad**: OpenAI y DeepL como proveedores; variables de entorno
  existentes
- **Formato**: Salida siempre Markdown válido; código y URLs intactos
- **Privacidad**: Traducciones y `output/` pueden contener docs privados —
  gitignore y avisos en UI

<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages

- Python 3.11+ (`requires-python = ">=3.11"` en `pyproject.toml`) — backend API,
  Markdown parsing, traducción, CLI
- JavaScript (ES modules, vanilla) — web client en `static/js/`
- HTML5 — SPA shell en `static/index.html`
- CSS — estilos en `static/css/` + Tailwind CDN

## Runtime

- CPython (`.venv/` local, gitignored)
- ASGI server: Uvicorn sirviendo la app FastAPI
- uv — gestor de dependencias; **`uv.lock` presente** (lockfile completo)
- setuptools como build backend (`pyproject.toml`)
- pip/uv para instalar: `uv sync` o `pip install -r requirements.txt`

## Frameworks

- FastAPI `>=0.115.0` — API HTTP, validación Pydantic, mount estático, uploads
- Uvicorn `[standard]>=0.32.0` — servidor ASGI; arranca desde `src/main.py`
  `run()`
- Typer `>=0.21.0` — CLI (`md-translate`), punto de entrada `src/cli.py`
- Pydantic (vía FastAPI) — modelos de request/response en `src/main.py`
- OpenAI SDK `openai>=1.55.0` — Chat Completions con formato JSON en
  `src/translator.py`
- DeepL SDK `deepl>=1.20.0` — batch `translate_text` en `src/translator.py`
- PyYAML `pyyaml>=6.0.2` — carga/guarda `glossary.yaml` en `src/glossary.py`
- Watchdog `watchdog>=6.0.0` — modo `--watch` en CLI para traducción automática
  al guardar
- WeasyPrint `>=62` — **opcional** (`pip install -e ".[pdf]"`); exportación PDF
  en `src/pdf_export.py`
- pytest `>=8.0` — tests en `tests/`; declarado en
  `[project.optional-dependencies] test`

## Key Dependencies

- `fastapi` — superficie REST (`/api/languages`, `/api/translate`,
  `/api/translate/file`, `/api/translate/batch`, `/api/translate/draft`,
  `/api/translate/finalize`, `/api/translate/estimate`,
  `/api/translate/batch/jobs`, `/api/export/pdf`, `/api/glossary`,
  `/api/memory`)
- `openai` — proveedor por defecto (`TRANSLATION_PROVIDER=openai`, modelo por
  defecto `gpt-4o-mini`)
- `deepl` — proveedor alternativo neural
- `typer` — CLI con subcomandos `file`, `dir`, `batch`, `serve`, `memory`
- `pyyaml` — glosario terminológico persistente
- `watchdog` — modo watch para traducción continua
- stdlib: `asyncio`, `zipfile`, `pathlib`, `re`, `json`, `logging`, `sqlite3`,
  `hashlib`
- Starlette — stack subyacente FastAPI (archivos estáticos, CORS, responses)
- Tailwind CSS — desde `https://cdn.tailwindcss.com` en `static/index.html`

## Configuration

- `python-dotenv` carga `.env` al importar `src/main.py`
- `.env` presente (gitignored); plantilla en `.env.example`
- Proveedor: `TRANSLATION_PROVIDER` (`openai` por defecto, `deepl` alternativo)
  en `src/translator.py`

| Variable                      | Módulo            | Propósito                                                       |
| ----------------------------- | ----------------- | --------------------------------------------------------------- |
| `OPENAI_API_KEY`              | `translator.py`   | Auth OpenAI                                                     |
| `OPENAI_MODEL`                | `translator.py`   | Modelo (por defecto `gpt-4o-mini`)                              |
| `OPENAI_BASE_URL`             | `translator.py`   | Endpoint alternativo (Ollama, Azure…)                           |
| `DEEPL_API_KEY`               | `translator.py`   | Auth DeepL                                                      |
| `DEEPL_API_URL`               | `translator.py`   | Host API DeepL (free tier, etc.)                                |
| `TRANSLATION_PROVIDER`        | `translator.py`   | `openai` o `deepl`                                              |
| `API_TOKEN`                   | `deployment.py`   | Token Bearer para autenticar endpoints (vacío = sin auth)       |
| `CORS_ORIGINS`                | `deployment.py`   | Orígenes CORS (`*` o lista CSV); por defecto `127.0.0.1:{PORT}` |
| `MAX_UPLOAD_MB`               | `deployment.py`   | Límite por archivo (por defecto `10`)                           |
| `MAX_BATCH_UPLOAD_MB`         | `deployment.py`   | Límite total batch (por defecto `50`)                           |
| `OUTPUT_TTL_HOURS`            | `deployment.py`   | TTL archivos en `output/`                                       |
| `OUTPUT_SWEEP_INTERVAL_HOURS` | `deployment.py`   | Frecuencia limpieza periódica `output/`                         |
| `HOST`                        | `main.py` `run()` | Bind address (por defecto `127.0.0.1`)                          |
| `PORT`                        | `main.py` `run()` | Puerto (por defecto `5400`)                                     |

- `pyproject.toml` v2.0 — console script: `md-translate = "src.cli:app"` (Typer,
  no `src.main:run`)
- `requirements.txt` — lista plana para pip; `uv.lock` para reproducibilidad
  exacta
- Docker: `Dockerfile` + `docker-compose.yml` presentes en raíz

## Platform Requirements

- Python 3.11 o superior
- Entorno virtual recomendado (`.venv/` gitignored); instalar con `uv sync` o
  `pip install -r requirements.txt`
- Al menos una API key de traducción (OpenAI **o** DeepL)
- Navegador moderno para la UI en `static/`
- Uvicorn single-process (sin worker config adicional)
- Directorio `output/` escribible — creado al arrancar en `src/main.py`
- Directorio `data/` escribible — DB SQLite de memoria TM en
  `data/translation_memory.db`
- HTTPS saliente hacia la API de traducción elegida
- WeasyPrint instalado solo si se usa exportación PDF

## Project Layout (stack-relevant)

| Path                         | Rol                                                               |
| ---------------------------- | ----------------------------------------------------------------- |
| `src/main.py`                | FastAPI app, rutas, mount estático, `run()`                       |
| `src/cli.py`                 | CLI Typer (subcomandos `file`, `dir`, `batch`, `serve`, `memory`) |
| `src/pipeline.py`            | Fachada unificada: parser → TM → glosario → traductor → validador |
| `src/parser.py`              | Segmentación Markdown (`Segment`, `SegmentKind`)                  |
| `src/translator.py`          | Batch OpenAI / DeepL, reintentos, chunking                        |
| `src/memory.py`              | Memoria de traducción SQLite (`TranslationMemory`)                |
| `src/glossary.py`            | Glosario YAML (DNT + pares fijos por idioma)                      |
| `src/validator.py`           | Validación estructural post-traducción                            |
| `src/estimate.py`            | Estimación de coste pre-traducción                                |
| `src/review.py`              | Modo revisión: borrador segmentado + finalización                 |
| `src/jobs.py`                | Jobs de lote asíncronos con SSE in-memory                         |
| `src/batch_zip.py`           | Lógica ZIP para lotes extraída de `main.py`                       |
| `src/html_export.py`         | Exportación Markdown → HTML                                       |
| `src/pdf_export.py`          | Exportación Markdown → PDF (WeasyPrint, opcional)                 |
| `src/deployment.py`          | Config CORS, límites upload, limpieza `output/`, auth token       |
| `src/gitignore_filter.py`    | Filtrado de archivos según `.gitignore`                           |
| `src/target_langs.py`        | Parsing y validación de idiomas destino, nombres de salida        |
| `static/`                    | Frontend assets servidos en `/static`                             |
| `data/translation_memory.db` | Cache SQLite de segmentos traducidos (gitignored)                 |
| `glossary.yaml`              | Glosario persistente editable (raíz del proyecto)                 |
| `output/`                    | Archivos `.md` traducidos temporales (gitignored)                 |
| `tests/`                     | Suite completa — un `test_*.py` por módulo (148 tests)            |

## Console entry points

- `md-translate` → `src.cli:app` (Typer) — subcomandos: `file`, `dir`, `batch`,
  `serve`, `memory`
- `python -m src.main` / `src.main:run()` — arranca Uvicorn directamente
  (equivalente a `md-translate serve`)

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns

- Módulos Python en `snake_case`: `parser.py`, `translator.py`, `pipeline.py`,
  `memory.py`…
- Tests bajo `tests/` con prefijo `test_`: `tests/test_parser.py`,
  `tests/test_pipeline.py`…
- Frontend estático: `static/js/`, `static/css/`, `static/index.html`
- Funciones públicas en `snake_case`: `segment_markdown`, `translate_markdown`,
  `build_draft`, `estimate_markdown`
- Helpers internos con prefijo `_`: `_decode_upload`, `_translate_openai_batch`,
  `_append_shell_line`
- Handlers FastAPI async sin prefijo `_`: `translate_text`, `translate_file`,
  `translate_batch`, `translate_draft`
- Punto de entrada CLI: `app` (Typer) en `src/cli.py`; servidor: `run()` en
  `src/main.py`
- `snake_case` para variables locales y parámetros: `target_lang`,
  `translatable`, `zip_buffer`
- Constantes de módulo en `UPPER_SNAKE_CASE`: `FENCE_PATTERN`, `BATCH_SIZE`,
  `SYSTEM_PROMPT`, `LANGUAGE_NAMES`
- Colecciones inmutables con `frozenset` cuando aplica: `SHELL_LANGS` en
  `src/parser.py`
- Clases Pydantic de API en `PascalCase`: `TranslateTextRequest`,
  `TranslateResponse`, `DraftResponse`, `EstimateResponse`
- `dataclass` para modelos de dominio: `Segment` (parser), `TranslateOptions`,
  `TranslateResult` (pipeline)
- `Enum` con valores string: `SegmentKind(str, Enum)` — `PROTECTED`,
  `TRANSLATABLE`
- `Protocol` para callbacks opcionales: `ProgressCallback` en
  `src/translator.py`
- Anotaciones modernas: `str | None`, `list[tuple[int, str]]`, `dict[int, str]`

## Code Style

- No hay configuración activa de Black, Ruff ni isort en el repositorio (solo
  entradas en `.gitignore` para `.mypy_cache/` y `.ruff_cache/`)
- Estilo implícito PEP 8: indentación 4 espacios, comillas dobles en docstrings
  y strings de código
- Líneas largas permitidas en prompts y cadenas multilínea (`SYSTEM_PROMPT` en
  `src/translator.py`)
- No detectado: `.eslintrc`, `ruff.toml`, `mypy.ini`, ni sección `[tool.ruff]` /
  `[tool.mypy]` en `pyproject.toml`
- Pre-commit: hook `git secrets --pre_commit_hook` en `.git/hooks/pre-commit`
  (evita filtrar secretos, no formatea código)
- `requires-python = ">=3.11"` en `pyproject.toml`
- Usar `from __future__ import annotations` al inicio de cada módulo en `src/`
  para forward references

## Import Organization

- Imports absolutos desde el paquete raíz del proyecto:
- `pythonpath = ["."]` en `[tool.pytest.ini_options]` de `pyproject.toml`
  habilita este patrón
- No hay aliases de import configurados; el paquete vive en `src/` como
  namespace plano (`src.main:app` para uvicorn)

## Error Handling

- Validación de entrada → `HTTPException` 400 (validación), 401 (auth), 502
  (traducción), 503 (config/servicio)
- **401 Unauthorized:** `API_TOKEN` configurado y no presentado — desde
  `_require_api_token` en `main.py`
- **400 Bad Request:** contenido vacío, idioma no soportado, extensión inválida,
  binario, límite batch, JSON inválido
- **502 Bad Gateway:** fallo de traducción tras logging (HTTPException 502)
- **503 Service Unavailable:** API key ausente o proveedor mal configurado
  (`RuntimeError` desde `translator.py`)
- `IncompleteTranslationError` — excepción custom en `translator.py`; capturada
  en `main.py` y convertida a 502 con detalle JSON (`expected`, `received`,
  `missing_indices`)
- Mensajes en español: contenido vacío, no autorizado, job no encontrado, etc.
- `_decode_upload()` → UTF-8 estricto; falla con mensaje accionable si no es
  válido
- `RuntimeError` con mensaje accionable desde módulos de lógica; convertir a
  `HTTPException` solo en `main.py`
- Reintentos con backoff exponencial (`2 ** (attempt + 1)`) para rate limits y
  429/5xx de OpenAI
- División recursiva de lotes si la respuesta JSON no coincide o DeepL falla en
  lote grande
- Proveedor desconocido → `RuntimeError` listando valores válidos
- Usar `raise … from e` al envolver excepciones

## Logging

- `logger = logging.getLogger(__name__)` en `src/main.py` y `src/translator.py`
- Nivel configurado solo al arrancar servidor en `run()`:
  `logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")`
- `logger.warning` para reintentos y división de lotes en `src/translator.py`
- `logger.exception` antes de respuestas 502 en endpoints de traducción en
  `src/main.py`
- No hay logging en `src/parser.py` (módulo determinista)

## Comments

- Docstring de módulo al inicio de cada archivo `src/*.py` (descripción breve en
  español)
- Docstrings en funciones públicas o no obvias: `segment_markdown`,
  `reassemble`, `collect_translatable`, `translate_segments`
- Comentarios inline solo para reglas de negocio no evidentes (p. ej.
  comentarios `#` traducibles en bloques shell en `src/parser.py`)
- Estilo Google informal en español, sin tipos repetidos si ya hay anotaciones
- Tests: docstring de módulo en tests/test_parser.py

## Function Design

- `segment_markdown` en `src/parser.py` es el método más largo (~100 líneas); el
  resto del código favorece funciones auxiliares `_append_*`, `_split_*`
- `src/translator.py` separa lotes, proveedores y parsing de respuesta en
  funciones `_`-prefijadas
- Idiomas como códigos ISO cortos (`es`, `pt-BR`); `source_lang=None` o `"auto"`
  significa detección automática
- Segmentos traducibles como `list[tuple[int, str]]` (índice estable + texto)
- Callback opcional on_progress en translate_segments (ProgressCallback)
- Parser: `list[Segment]`, `dict[int, str]` para traducciones, `str`
  reconstruido
- Traductor: `dict[int, str]` indexado por índice de segmento
- API: modelos Pydantic o `FileResponse` / `StreamingResponse`

## Module Design

- `src/__init__.py` presente (vacío); uvicorn usa `src.main:app`
- **API pública del parser:** `SegmentKind`, `Segment`, `segment_markdown`,
  `reassemble`, `collect_translatable`
- **API pública del traductor:** `LANGUAGE_NAMES`, `translate_segments`,
  `get_provider`, `get_supported_languages`, `is_valid_source_lang`,
  `is_valid_target_lang`, `IncompleteTranslationError`
- **API pública del pipeline:** `TranslateOptions`, `TranslateResult`,
  `translate_markdown`, `DEFAULT_GLOSSARY_PATH`
- **API pública de memoria:** `TranslationMemory`, `default_memory_path`,
  `make_key`
- **API pública del glosario:** `Glossary`, `load_glossary`, `save_glossary`,
  `glossary_from_dict`, `glossary_to_dict`, `apply_pre`, `apply_post`,
  `build_prompt_appendix`
- **API pública del validador:** `ValidationReport`, `validate_translation`,
  `validation_to_dict`
- **API pública de estimación:** `EstimateResult`, `estimate_markdown`,
  `estimate_files`
- **API pública de revisión:** `build_draft`, `finalize_draft`
- **API pública de jobs:** `create_batch_job`, `start_batch_job`, `get_job`,
  `cancel_job`, `JobState`
- `load_dotenv()` una vez al importar `src/main.py`; `os.getenv` en los módulos
  de lógica
- JavaScript vanilla (sin bundler): `const`/`let`, objeto `state`, helper `$`
  para `querySelector`
- Errores de API en español; mensajes de UI en inglés (convención histórica del
  proyecto)

## Where New Code Should Match

| Tipo de cambio                 | Ubicación                           | Convención                                                    |
| ------------------------------ | ----------------------------------- | ------------------------------------------------------------- |
| Regla de segmentación MD       | `src/parser.py`                     | Helper `_`, tests en `tests/test_parser.py`                   |
| Orquestación del pipeline      | `src/pipeline.py`                   | `TranslateOptions`, `TranslateResult`; llamar desde `main.py` |
| Proveedor o lote de traducción | `src/translator.py`                 | Constantes mayúsculas, reintentos existentes                  |
| Endpoint o modelo HTTP         | `src/main.py`                       | Pydantic + `HTTPException`, async + `run_in_executor`         |
| Subcomando CLI                 | `src/cli.py`                        | Typer `@app.command()`, docstring en español                  |
| Glosario                       | `src/glossary.py` + `glossary.yaml` | YAML con `version: 1`, `do_not_translate`, `pairs`            |
| Memoria TM                     | `src/memory.py`                     | SQLite stdlib, hash SHA-256 de segmento                       |
| UI web                         | `static/js/`, `static/index.html`   | Patrón `els`/`state`, sin framework                           |
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Pattern Overview

- **Preserve-then-translate:** `src/parser.py` clasifica el contenido antes de
  cualquier llamada API; bloques de código, frontmatter y código inline nunca se
  envían al proveedor.
- **Pipeline unificado:** `src/pipeline.py` actúa como fachada: parser → TM
  (cache) → glosario (pre) → traductor → glosario (post) → validador →
  resultado.
- **Provider abstraction via env:** `src/translator.py` conmuta entre OpenAI
  (JSON batches) y DeepL (REST batches) con `TRANSLATION_PROVIDER`; ambos
  exponen `translate_segments()`.
- **Async boundary at I/O:** handlers FastAPI son `async`; la traducción
  bloqueante corre en `asyncio.run_in_executor()`.
- **Jobs SSE in-memory:** lotes grandes usan `src/jobs.py` con cola de eventos
  asyncio y streaming SSE en `/api/translate/batch/jobs/{id}/events`.
- **Stateless HTTP + persistent TM:** cada request es autocontenida; la memoria
  de traducción persiste entre requests en SQLite
  (`data/translation_memory.db`).
- **Auth opcional:** `API_TOKEN` en `.env` activa Bearer token en todos los
  endpoints de escritura; vacío = sin auth (desarrollo local).

## Layers

**Frontend** — `static/`
Interfaz web SPA: editor, archivo único, lote, revisión editorial, preview
multi-idioma con tabs.
Depende de: `/api/*` en `src/main.py`. Sin bundler, JS vanilla.

**API** — `src/main.py`
Rutas FastAPI, validación Pydantic, decode de uploads, auth token, orchestración
del pipeline, mapping de errores a HTTP.
Endpoints principales: translate, file, batch, draft, finalize, estimate,
batch/jobs (+ SSE events), glossary, memory, export/pdf — ver OpenAPI en
/docs.

**Pipeline** — `src/pipeline.py`
Fachada que orquesta parser + TM + glosario + traductor + validador.
Entrada: `(content: str, options: TranslateOptions)` → Salida:
`TranslateResult`.

**Parser** — `src/parser.py`
Segmentación Markdown determinista. Stdlib pura. Sin efectos secundarios.

**Translator** — `src/translator.py`
Batch OpenAI / DeepL, reintentos, chunking, `IncompleteTranslationError`.

**Memory** — `src/memory.py`
Cache SQLite de segmentos. Hash SHA-256 por texto + par origen/destino.

**Glossary** — `src/glossary.py`
Sustituciones pre/post-traducción. Cargado desde `glossary.yaml` (YAML,
`version: 1`).

**Validator** — `src/validator.py`
Checks post-traducción: recuento de segmentos, integridad de código, URLs.

**Jobs** — `src/jobs.py`
Jobs de lote asíncronos. Estado en memoria (single-process). SSE vía
`event_queue: asyncio.Queue`.

**CLI** — `src/cli.py`
Typer app. Subcomandos: `file`, `dir`, `batch`, `serve`, `memory`. Punto de
entrada del console script `md-translate`.

## Data Flow (request normal)

```text
Browser/CLI → POST /api/translate
  → _decode_upload() / validación Pydantic
  → translate_markdown(content, TranslateOptions)   # pipeline.py
      → segment_markdown()                          # parser.py
      → TM lookup (cache hits)                      # memory.py
      → apply_pre() glosario                        # glossary.py
      → translate_segments() [API call]             # translator.py
      → apply_post() glosario                       # glossary.py
      → TM store (nuevas traducciones)              # memory.py
      → validate_translation()                      # validator.py
      → TranslateResult
  → TranslateResponse JSON / FileResponse / ZIP
```

## Key Abstractions

- **Index-keyed map:** traducciones indexadas por `Segment.index` (estable), no
  por posición
- **SegmentKind enum:** `PROTECTED` / `TRANSLATABLE` — clasificación binaria de
  fragmentos MD
- **TranslateOptions dataclass:** encapsula target_lang, source_lang, tone,
  flags de TM/glosario, callback de progreso
- **IncompleteTranslationError:** excepción custom con `expected`, `received`,
  `missing_indices`
- **Batch chunking:** greedy por item count + `MAX_BATCH_CHARS` (4000);
  bisección recursiva en error

## Entry Points

- `md-translate` → `src.cli:app` (Typer) — CLI principal
- `md-translate serve` / `python -m src.main` / `src.main:run()` — arranca
  Uvicorn en `HOST:PORT` (por defecto `127.0.0.1:5400`)
- `pytest tests/ -q` — suite completa, 148 tests, `pythonpath = ["."]`
- `Dockerfile` / `docker-compose.yml` — despliegue containerizado

## HTTP Error Codes

- **400** — validación entrada (contenido vacío, idioma, extensión, binario,
  límites)
- **401** — API_TOKEN configurado y no presentado
- **404** — job no encontrado
- **409** — job aún en curso al intentar descargar ZIP
- **502** — fallo de traducción (tras logging)
- **503** — API key ausente / proveedor mal configurado

## Cross-Cutting Concerns

- CORS configurable vía `CORS_ORIGINS`; por defecto solo `127.0.0.1:{PORT}`
- Limpieza periódica de `output/` configurable con `OUTPUT_TTL_HOURS` y
  `OUTPUT_SWEEP_INTERVAL_HOURS`
- Límites de upload configurables: `MAX_UPLOAD_MB` (10 MB),
  `MAX_BATCH_UPLOAD_MB` (50 MB)

<!-- GSD:architecture-end -->

## macOS App (v3.0) — Phase 9+

v3.0 embebe el backend FastAPI/uvicorn como subprocess dentro de una app nativa
Swift/macOS. La UI web existente se servirá vía WKWebView (Phase 10+).

### Layout

| Path                                                    | Rol                                                                                               |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `macos/MDTranslator/MDTranslator.xcodeproj`             | Proyecto Xcode                                                                                    |
| `macos/MDTranslator/MDTranslator/ServerManager.swift`   | Lifecycle del subprocess Python: puerto libre, arranque, health check, shutdown                   |
| `macos/MDTranslator/MDTranslator/SplashView.swift`      | Spinner durante arranque + alert de error/retry                                                   |
| `macos/MDTranslator/MDTranslator/MDTranslatorApp.swift` | Entry point `@main`; conmuta entre SplashView y UI principal                                      |
| `macos/MDTranslator/MDTranslator/AppDelegate.swift`     | `applicationWillTerminate` → shutdown graceful del servidor                                       |
| `scripts/build-python-bundle.sh`                        | Descarga CPython 3.11.15 (python-build-standalone) e instala deps con uv; genera `python-bundle/` |
| `python-bundle/`                                        | CPython portátil + site-packages (gitignored, ~200 MB)                                            |

### Arquitectura del subprocess

```text
MDTranslatorApp (@main)
  └── ServerManager (@MainActor @Observable)
        ├── findFreePort()          — bind(port=0) en loopback, cierra socket
        ├── start() async           — Process.run() + waitForHealthCheck
        ├── waitForHealthCheck()    — GET /api/languages cada 500ms, timeout 15s
        └── stop()                  — SIGINT → espera 5s → SIGKILL (Foundation.Process.terminate)

Resources/
  ├── python/              — CPython portátil (de python-bundle/)
  │   └── bin/python3      — intérprete usado como executableURL
  └── backend/             — copia de src/ + pyproject.toml + uv.lock
      └── src/main.py      — ASGI app; cwd del subprocess
```

La copia a `Resources/` la hace un **Run Script phase** en Xcode (Build Phases →
"Copy Python Bundle & Backend") usando rsync.

### Configuración Xcode obligatoria

| Setting                        | Valor requerido     | Motivo                                                                                          |
| ------------------------------ | ------------------- | ----------------------------------------------------------------------------------------------- |
| Deployment Target              | macOS 14.0          | `@Observable`, `.task`, `defaultSize`                                                           |
| App Sandbox                    | **Eliminado**       | Sandbox impide lanzar subprocesos externos                                                      |
| User Script Sandboxing         | No                  | Permite rsync en el Run Script phase                                                            |
| "Based on dependency analysis" | **Desactivado**     | Si está activo, Xcode omite el Run Script en builds incrementales sin inputs/outputs declarados |
| Signing Certificate            | Sign to Run Locally | Desarrollo sin Apple Developer account                                                          |

### Pitfalls críticos (aprendidos en Phase 9)

1. **`p.environment` debe heredar el entorno del proceso padre** — nunca
   reemplazar completamente. Usar ProcessInfo.processInfo.environment y
   sobreescribir solo HOST, PORT, PYTHONDONTWRITEBYTECODE y PYTHONUNBUFFERED.
   Si se reemplaza completamente, Python pierde HOME/TMPDIR y subprocesos shell
   fallan con "getcwd: cannot access parent directories".

2. **App Sandbox y subprocess son incompatibles** — eliminar la capability
   completa en Signing & Capabilities. No añadir entitlements alternativos: no
   hay entitlement estándar para ejecutar intérpretes arbitrarios.

3. **`p.run()` vs `p.launch()`** — usar `p.run()` (no deprecated). Igual con
   `p.executableURL` (no `p.launchPath`).

4. **`@Observable` + `@MainActor`** — en Swift 6, `@MainActor class` no puede
   conformar `ObservableObject`. Usar `@Observable` macro (macOS 14+), `@State`
   en lugar de `@StateObject`, eliminar `@ObservedObject`.

5. **Huérfanos tras Force Quit** — `applicationWillTerminate` no se llama en
   Force Quit. `ServerManager.init()` lee `/tmp/md-translator-python.pid` y mata
   el proceso previo si sigue vivo.

6. **Log del subprocess** — stdout/stderr de uvicorn se redirigen a
   `NSTemporaryDirectory()/md-translator-server.log` para diagnóstico.

### Añadir código macOS

- Lógica del servidor → `ServerManager.swift` (no añadir state a `AppDelegate`
  ni `App`)
- Views nuevas → ficheros `.swift` separados; el switch `state == .running` en
  `MDTranslatorApp` controla qué view mostrar
- Phase 10 reemplazará `Text("Main UI — Phase 10")` por un `WKWebView` cargando
  `http://127.0.0.1:{serverPort}`

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`,
`.agents/skills/`, `.cursor/skills/`, or `.github/skills/` with a `SKILL.md`
index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD
command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly
asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer
profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community
structure, and cross-file relationships.

Rules:

- For codebase questions, first run `graphify query "<question>"` when
  graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for
  relationships and `graphify explain "<concept>"` for focused concepts. These
  return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw
  grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of
  raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when
  query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current
  (AST-only, no API cost).
