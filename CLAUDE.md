<!-- GSD:project-start source:PROJECT.md -->
## Project

**MarkDown Auto Translator**

Traductor de archivos Markdown que preserva formato y bloques de código, orientado a documentación técnica y equipos que localizan docs sin romper sintaxis. Incluye interfaz web (editor, archivo, lote), API FastAPI y proveedores OpenAI o DeepL. Este milestone evoluciona el MVP hacia la hoja de ruta completa del `NOTEBOOK.md` (fases A→E).

**Core Value:** Traducir **solo el texto dirigido al usuario** al idioma destino **sin alterar Markdown ni código**, con coherencia terminológica y coste predecible en lotes grandes.

### Constraints

- **Tech stack**: Mantener Python 3.11+, FastAPI, parser actual; extender sin reescritura total
- **Seguridad**: Nunca commitear `.env`; documentación de planificación sin claves reales
- **Compatibilidad**: OpenAI y DeepL como proveedores; variables de entorno existentes
- **Formato**: Salida siempre Markdown válido; código y URLs intactos
- **Privacidad**: Traducciones y `output/` pueden contener docs privados — gitignore y avisos en UI
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- Python 3.11+ (declared in `pyproject.toml` `requires-python`; README and local venv may use 3.14) — backend API, Markdown parsing, translation orchestration in `src/`
- JavaScript (ES modules, vanilla) — web client in `static/js/app.js`
- HTML5 — SPA shell in `static/index.html`
- CSS — custom styles in `static/css/app.css` plus Tailwind utility classes
## Runtime
- CPython interpreter (local development via `python3 -m venv .venv`)
- ASGI server: Uvicorn serving the FastAPI app
- pip (primary install path: `pip install -r requirements.txt`)
- setuptools (build backend declared in `pyproject.toml`)
- Lockfile: **missing** — no `requirements.lock`, `poetry.lock`, or `uv.lock`; versions are minimum pins only (`>=`)
## Frameworks
- FastAPI `>=0.115.0` — HTTP API, request validation (Pydantic models), static file mount, file upload handling in `src/main.py`
- Uvicorn `[standard]>=0.32.0` — dev/production ASGI server; entry via `uvicorn.run("src.main:app", ...)` in `src/main.py` `run()`
- Pydantic (via FastAPI) — `TranslateTextRequest`, `TranslateResponse`, `LanguageItem` in `src/main.py`
- OpenAI Python SDK `openai>=1.55.0` — Chat Completions API with JSON response format in `src/translator.py` (`create_openai_client`, `_translate_openai_batch`)
- DeepL Python SDK `deepl>=1.20.0` — batch `translate_text` in `src/translator.py` (`create_deepl_client`, `_translate_deepl_batch`)
- pytest — configured in `pyproject.toml` `[tool.pytest.ini_options]` with `testpaths = ["tests"]`, `pythonpath = ["."]`
- **Not** listed in `requirements.txt`; README documents optional `pip install pytest`
- python-dotenv `>=1.0.1` — loads `.env` at import time in `src/main.py` (`load_dotenv()`)
- python-multipart `>=0.0.12` — multipart form uploads for file/batch endpoints
## Key Dependencies
- `fastapi` — REST API surface (`/api/languages`, `/api/translate`, `/api/translate/file`, `/api/translate/batch`)
- `openai` — default translation provider (`TRANSLATION_PROVIDER=openai`, default model `gpt-4o-mini`)
- `deepl` — alternate neural translation provider
- Standard library modules heavily used: `asyncio`, `zipfile`, `pathlib`, `re`, `json`, `logging` in `src/main.py`, `src/parser.py`, `src/translator.py`
- `requests` — pulled in by `deepl` SDK (visible in `.venv`, not pinned at project level)
- Starlette — underlying FastAPI stack (static files, CORS, responses)
- Tailwind CSS — loaded from `https://cdn.tailwindcss.com` in `static/index.html`
- Google Fonts — Plus Jakarta Sans from `fonts.googleapis.com` in `static/index.html`
## Configuration
- `python-dotenv` loads `.env` from project root when `src/main.py` imports (working directory matters for relative `.env` resolution)
- `.env` file present (gitignored); template: `.env.example`
- Provider selection: `TRANSLATION_PROVIDER` (`openai` default, `deepl` alternative) read in `src/translator.py` `get_provider()`
| Variable | Used in | Purpose |
| -------- | ------- | ------- |
| `OPENAI_API_KEY` | `src/translator.py` | OpenAI-compatible API auth |
| `OPENAI_MODEL` | `src/translator.py` | Model id (default `gpt-4o-mini`) |
| `OPENAI_BASE_URL` | `src/translator.py` | Optional compatible endpoint (Ollama, Azure, etc.) |
| `DEEPL_API_KEY` | `src/translator.py` | DeepL auth when provider is `deepl` |
| `DEEPL_API_URL` | `src/translator.py` | Optional API host (e.g. free tier URL per README) |
| `TRANSLATION_PROVIDER` | `src/translator.py` | `openai` or `deepl` |
| `HOST` | `src/main.py` `run()` | Bind address (default `127.0.0.1`) |
| `PORT` | `src/main.py` `run()` | Listen port (default `8000`) |
- `pyproject.toml` — project metadata, dependencies mirror `requirements.txt`, console script `md-translate = src.main:run`
- `requirements.txt` — flat dependency list for pip
- No Docker, Makefile, or CI config detected in repo root
## Platform Requirements
- Python 3.11 or newer
- Virtual environment recommended (`.venv/` gitignored)
- At least one translation API key (OpenAI **or** DeepL depending on `TRANSLATION_PROVIDER`)
- Modern browser for `static/` UI (fetch API, FormData uploads)
- Single-process Uvicorn deployment (no separate worker config in repo)
- Writable `output/` directory — created at startup in `src/main.py` for temporary translated file downloads
- Outbound HTTPS to chosen translation API (OpenAI-compatible host or DeepL)
- No container or cloud hosting manifests in repository
## Project Layout (stack-relevant)
| Path | Role |
| ---- | ---- |
| `src/main.py` | FastAPI app, routes, static mount, CLI `run()` |
| `src/parser.py` | Markdown segmentation (stdlib `re`, dataclasses) |
| `src/translator.py` | OpenAI / DeepL batch translation |
| `static/` | Frontend assets served at `/static` |
| `tests/test_parser.py` | Parser unit tests only |
| `output/` | Ephemeral translated `.md` files (gitignored) |
## Console entry points
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- Módulos Python en `snake_case`: `parser.py`, `translator.py`, `main.py`
- Tests bajo `tests/` con prefijo `test_`: `tests/test_parser.py`
- Frontend estático: `static/js/app.js`, `static/index.html`
- Funciones públicas y helpers en `snake_case`: `segment_markdown`, `collect_translatable`, `translate_segments`
- Helpers internos con prefijo `_`: `_decode_upload`, `_translate_openai_batch`, `_append_shell_line`
- Handlers FastAPI async sin prefijo `_`: `translate_text`, `translate_file`, `translate_batch`
- Punto de entrada CLI/servidor: `run()` en `src/main.py`
- `snake_case` para variables locales y parámetros: `target_lang`, `translatable`, `zip_buffer`
- Constantes de módulo en `UPPER_SNAKE_CASE`: `FENCE_PATTERN`, `BATCH_SIZE`, `SYSTEM_PROMPT`, `LANGUAGE_NAMES`
- Colecciones inmutables con `frozenset` cuando aplica: `SHELL_LANGS` en `src/parser.py`
- Clases Pydantic de API en `PascalCase`: `TranslateTextRequest`, `TranslateResponse`, `LanguageItem`
- `dataclass` para modelos de dominio: `Segment` en `src/parser.py`
- `Enum` con valores string: `SegmentKind(str, Enum)` con miembros `PROTECTED`, `TRANSLATABLE`
- `Protocol` para callbacks opcionales: `ProgressCallback` en `src/translator.py`
- Anotaciones modernas: `str | None`, `list[tuple[int, str]]`, `dict[int, str]`
## Code Style
- No hay configuración activa de Black, Ruff ni isort en el repositorio (solo entradas en `.gitignore` para `.mypy_cache/` y `.ruff_cache/`)
- Estilo implícito PEP 8: indentación 4 espacios, comillas dobles en docstrings y strings de código
- Líneas largas permitidas en prompts y cadenas multilínea (`SYSTEM_PROMPT` en `src/translator.py`)
- No detectado: `.eslintrc`, `ruff.toml`, `mypy.ini`, ni sección `[tool.ruff]` / `[tool.mypy]` en `pyproject.toml`
- Pre-commit: hook `git secrets --pre_commit_hook` en `.git/hooks/pre-commit` (evita filtrar secretos, no formatea código)
- `requires-python = ">=3.11"` en `pyproject.toml`
- Usar `from __future__ import annotations` al inicio de cada módulo en `src/` para forward references
## Import Organization
- Imports absolutos desde el paquete raíz del proyecto:
- `pythonpath = ["."]` en `[tool.pytest.ini_options]` de `pyproject.toml` habilita este patrón
- No hay aliases de import configurados; el paquete vive en `src/` como namespace plano (`src.main:app` para uvicorn)
## Error Handling
- Validación de entrada del cliente → `HTTPException` con códigos 400 (validación), 502 (fallo de traducción), 503 (configuración/servicio no disponible)
- Mensajes de error orientados al usuario en español: `"El contenido está vacío"`, `"Idioma destino no soportado: …"`
- Errores de decodificación de archivo → capturar `ValueError` de `_decode_upload` y reenviar como `HTTPException(400, …)` con `from e`
- Configuración o proveedor ausente → `RuntimeError` desde `src/translator.py` mapeado a `HTTPException(503, str(e))`
- Errores inesperados en traducción → `logger.exception(...)` y `HTTPException(502, …)` con `from e`
- Configuración faltante → `RuntimeError` con mensaje accionable (referencia a variables `.env`, sin incluir valores)
- Respuesta de modelo inválida → `ValueError` con conteo esperado vs recibido
- Reintentos con backoff exponencial (`2 ** (attempt + 1)`) para `RateLimitError` y códigos HTTP 429/5xx de OpenAI
- División recursiva de lotes cuando la respuesta JSON no coincide o DeepL falla en lote grande
- Proveedor desconocido → `RuntimeError` listando valores válidos (`openai`, `deepl`)
- Sin excepciones custom; funciones puras que asumen Markdown bien formado
- Segmentos vacíos se omiten en `_append_segment` (no se añaden al listado)
- Lógica reutilizable: lanzar `ValueError` / `RuntimeError` con mensaje claro
- Borde HTTP: convertir en `HTTPException` en `src/main.py`, no en `parser` ni `translator`
- Usar `raise … from e` al envolver excepciones
## Logging
- `logger = logging.getLogger(__name__)` en `src/main.py` y `src/translator.py`
- Nivel configurado solo al arrancar servidor en `run()`: `logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")`
- `logger.warning` para reintentos y división de lotes en `src/translator.py`
- `logger.exception` antes de respuestas 502 en endpoints de traducción en `src/main.py`
- No hay logging en `src/parser.py` (módulo determinista)
## Comments
- Docstring de módulo al inicio de cada archivo `src/*.py` (descripción breve en español)
- Docstrings en funciones públicas o no obvias: `segment_markdown`, `reassemble`, `collect_translatable`, `translate_segments`
- Comentarios inline solo para reglas de negocio no evidentes (p. ej. comentarios `#` traducibles en bloques shell en `src/parser.py`)
- Estilo Google informal en español, sin tipos repetidos si ya hay anotaciones
- Tests: docstring de módulo en `tests/test_parser.py` (`"""Tests del segmentador Markdown."""`)
## Function Design
- `segment_markdown` en `src/parser.py` es el método más largo (~100 líneas); el resto del código favorece funciones auxiliares `_append_*`, `_split_*`
- `src/translator.py` separa lotes, proveedores y parsing de respuesta en funciones `_`-prefijadas
- Idiomas como códigos ISO cortos (`es`, `pt-BR`); `source_lang=None` o `"auto"` significa detección automática
- Segmentos traducibles como `list[tuple[int, str]]` (índice estable + texto)
- Callback opcional con keyword-only: `on_progress: Callable[[int, int], None] | None = None` en `translate_segments`
- Parser: `list[Segment]`, `dict[int, str]` para traducciones, `str` reconstruido
- Traductor: `dict[int, str]` indexado por índice de segmento
- API: modelos Pydantic o `FileResponse` / `StreamingResponse`
## Module Design
- No hay `src/__init__.py` requerido para el layout actual; uvicorn usa `src.main:app`
- API pública del parser: `SegmentKind`, `Segment`, `segment_markdown`, `reassemble`, `collect_translatable`
- API pública del traductor: `LANGUAGE_NAMES`, `translate_segments`, `get_provider`, factories `create_openai_client` / `create_deepl_client`
- No usados; importar desde el módulo concreto
- `load_dotenv()` una vez al importar `src/main.py`
- Lectura de entorno vía `os.getenv` en traductor y `run()`; documentar nombres en `README.md` y `.env.example` (no commitear `.env`)
- JavaScript vanilla ES modules implícitos (script clásico, no bundler)
- `const` / `let`, funciones con nombre, objeto `state`, helper `$` para `querySelector`
- Comentarios de bloque JSDoc-style en cabecera del archivo
- Mensajes de UI y `SAMPLE_MD` en inglés (contenido de demo), errores vía API en español
## Where New Code Should Match
| Tipo de cambio | Ubicación | Convención |
|----------------|-----------|------------|
| Regla de segmentación MD | `src/parser.py` | Helper `_`, tests en `tests/test_parser.py` |
| Proveedor o lote de traducción | `src/translator.py` | Constantes en mayúsculas, reintentos existentes |
| Endpoint o modelo HTTP | `src/main.py` | Pydantic + `HTTPException`, async + `run_in_executor` para trabajo bloqueante |
| UI web | `static/js/app.js`, `static/index.html` | Patrón `els` / `state`, sin framework |
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Pattern Overview
- **Preserve-then-translate:** `src/parser.py` classifies content before any API call; code blocks, frontmatter, and inline code never leave the process untranslated-by-design.
- **Provider abstraction via env:** `src/translator.py` switches between OpenAI (LLM JSON batches) and DeepL (REST batches) using `TRANSLATION_PROVIDER`; both expose the same `translate_segments()` entry point.
- **Async boundary at I/O:** FastAPI handlers are `async`; blocking translation runs in `asyncio.run_in_executor()` so the event loop stays responsive.
- **Stateless requests:** No session store; each request carries full content. Single-file downloads are written to `output/` with a UUID prefix; batch mode streams a ZIP from memory.
## Layers
- Purpose: Browser interface for editor, single-file upload, and batch ZIP download
- Location: `static/`
- Contains: `static/index.html`, `static/css/app.css`, `static/js/app.js`
- Depends on: REST endpoints under `/api/*` in `src/main.py`
- Used by: End users via browser at `/`
- Purpose: Route definitions, request validation, file decode, orchestration of the pipeline, static file mounting, error mapping to HTTP status codes
- Location: `src/main.py`
- Contains: FastAPI `app`, Pydantic request/response models, upload helpers (`_decode_upload`, `_unique_zip_name`), `_translate_file_content()`
- Depends on: `src/parser.py`, `src/translator.py`, `python-dotenv`, FastAPI/uvicorn
- Used by: Browser client (`static/js/app.js`), external API consumers, OpenAPI docs at `/docs`
- Purpose: Parse Markdown into ordered segments tagged as protected or translatable; reassemble with translations while preserving whitespace
- Location: `src/parser.py`
- Contains: `Segment`, `SegmentKind`, `segment_markdown()`, `collect_translatable()`, `reassemble()`
- Depends on: Standard library only (`re`, `dataclasses`, `enum`)
- Used by: `src/main.py` (all translation endpoints)
- Purpose: Batch translation against OpenAI Chat Completions or DeepL API; retries, chunking, language mapping
- Location: `src/translator.py`
- Contains: `translate_segments()`, `LANGUAGE_NAMES`, provider clients, batch/chunk helpers
- Depends on: `openai` SDK (always imported); `deepl` (lazy import when provider is DeepL); environment variables
- Used by: `src/main.py` via `translate_segments()`
## Data Flow
- No server-side session or job queue.
- Frontend holds UI state in a plain object in `static/js/app.js` (`state.mode`, `state.selectedFile`, `state.batchFiles`, `state.downloadBlob`).
- Theme preference in `localStorage` (`theme` key).
- Translation provider and API keys loaded once at import via `load_dotenv()` in `src/main.py`.
## Key Abstractions
- Purpose: Decouple Markdown structure preservation from translation API details
- Examples: `src/parser.py` (`Segment`, `segment_markdown`, `reassemble`), `src/translator.py` (`translate_segments`)
- Pattern: Index-keyed map — translations keyed by segment `index`, not positional list order in reassembly
- Purpose: Binary classification of markdown fragments
- Examples: `src/parser.py` — `PROTECTED`, `TRANSLATABLE`
- Pattern: Enum with `str` mixin for serializable values
- Purpose: Swap OpenAI vs DeepL without changing callers
- Examples: `src/translator.py` — `get_provider()`, `_translate_openai_batch()`, `_translate_deepl_batch()`
- Pattern: Env-driven branch inside `translate_segments()`; separate batch sizes (`BATCH_SIZE=15` OpenAI, `DEEPL_BATCH_SIZE=40` DeepL) and language maps (`DEEPL_TARGET_MAP`, `DEEPL_SOURCE_MAP`)
- Purpose: Respect API limits and recover from malformed batch responses
- Examples: `src/translator.py` — `_chunk_items()`, recursive halving in `_translate_openai_batch()` / `_translate_deepl_batch()` on parse/API errors
- Pattern: Greedy chunk by item count + `MAX_BATCH_CHARS` (4000); bisect batch on failure when len > 1
- Purpose: Request/response validation and OpenAPI schema generation
- Examples: `src/main.py` — `TranslateTextRequest`, `TranslateResponse`, `LanguageItem`, `ProgressEvent`
- Pattern: FastAPI `response_model=` on routes; note `ProgressEvent` is defined but not yet exposed on any endpoint
## Entry Points
- Location: `src/main.py` — `run()` and `if __name__ == "__main__"`
- Triggers: `python -m src.main`, or CLI script `md-translate` (declared in `pyproject.toml` → `src.main:run`)
- Responsibilities: Configure logging, read `HOST`/`PORT` from env, start uvicorn with `"src.main:app"` and `reload=True`
- Location: `src/main.py` — `app = FastAPI(...)`
- Triggers: uvicorn, any ASGI host
- Responsibilities: Mount `/static`, serve `/` as `static/index.html`, register `/api/*` routes
- Location: `pyproject.toml` — `[project.scripts] md-translate = "src.main:run"`
- Triggers: `pip install -e .` then `md-translate`
- Responsibilities: Same as `run()`
- Location: `tests/test_parser.py`
- Triggers: `pytest tests/ -q` (config in `pyproject.toml` `[tool.pytest.ini_options]`, `pythonpath = ["."]`)
- Responsibilities: Unit tests for parser only; no HTTP or translator integration tests
## Error Handling
- **400 Bad Request:** Empty content, unsupported language, invalid file extension, binary upload, batch limits (`src/main.py` handlers)
- **502 Bad Gateway:** Generic translation failure after logging (`HTTPException(502, ...)`)
- **503 Service Unavailable:** Missing API key or misconfiguration surfaced as `RuntimeError` from `src/translator.py` (`create_openai_client()`, `create_deepl_client()`, unknown provider)
- **Provider retries:** Up to `MAX_RETRIES` (3) with exponential backoff on rate limits and 429/500/502/503 for OpenAI; similar for DeepL string-matched errors
- **Decode fallback:** `_decode_upload()` tries UTF-8, then latin-1 with replacement — avoids crash but may corrupt non-UTF-8 text silently
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, or `.github/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
