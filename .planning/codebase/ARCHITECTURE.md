# Architecture

**Analysis Date:** 2026-05-28

## Pattern Overview

**Overall:** Pipeline monolith — segment → translate → reassemble

The application is a single-process FastAPI service with a three-stage translation pipeline. Markdown is split into protected and translatable segments locally, only translatable text is sent to an external translation provider in batches, and the document is reconstructed by index. The web UI is static assets served by the same process; there is no separate frontend build step or database.

**Key Characteristics:**

- **Preserve-then-translate:** `src/parser.py` classifies content before any API call; code blocks, frontmatter, and inline code never leave the process untranslated-by-design.
- **Provider abstraction via env:** `src/translator.py` switches between OpenAI (LLM JSON batches) and DeepL (REST batches) using `TRANSLATION_PROVIDER`; both expose the same `translate_segments()` entry point.
- **Async boundary at I/O:** FastAPI handlers are `async`; blocking translation runs in `asyncio.run_in_executor()` so the event loop stays responsive.
- **Stateless requests:** No session store; each request carries full content. Single-file downloads are written to `output/` with a UUID prefix; batch mode streams a ZIP from memory.

## Layers

**Presentation (Web UI):**

- Purpose: Browser interface for editor, single-file upload, and batch ZIP download
- Location: `static/`
- Contains: `static/index.html`, `static/css/app.css`, `static/js/app.js`
- Depends on: REST endpoints under `/api/*` in `src/main.py`
- Used by: End users via browser at `/`

**HTTP / Application layer:**

- Purpose: Route definitions, request validation, file decode, orchestration of the pipeline, static file mounting, error mapping to HTTP status codes
- Location: `src/main.py`
- Contains: FastAPI `app`, Pydantic request/response models, upload helpers (`_decode_upload`, `_unique_zip_name`), `_translate_file_content()`
- Depends on: `src/parser.py`, `src/translator.py`, `python-dotenv`, FastAPI/uvicorn
- Used by: Browser client (`static/js/app.js`), external API consumers, OpenAPI docs at `/docs`

**Domain / Processing layer (Markdown segmentation):**

- Purpose: Parse Markdown into ordered segments tagged as protected or translatable; reassemble with translations while preserving whitespace
- Location: `src/parser.py`
- Contains: `Segment`, `SegmentKind`, `segment_markdown()`, `collect_translatable()`, `reassemble()`
- Depends on: Standard library only (`re`, `dataclasses`, `enum`)
- Used by: `src/main.py` (all translation endpoints)

**Infrastructure layer (Translation providers):**

- Purpose: Batch translation against OpenAI Chat Completions or DeepL API; retries, chunking, language mapping
- Location: `src/translator.py`
- Contains: `translate_segments()`, `LANGUAGE_NAMES`, provider clients, batch/chunk helpers
- Depends on: `openai` SDK (always imported); `deepl` (lazy import when provider is DeepL); environment variables
- Used by: `src/main.py` via `translate_segments()`

## Data Flow

**Text translation (`POST /api/translate`):**

1. Client sends JSON `{ content, target_lang, source_lang }` (`TranslateTextRequest` in `src/main.py`).
2. Handler validates non-empty content and supported `target_lang` against `LANGUAGE_NAMES` from `src/translator.py`.
3. `segment_markdown(content)` returns ordered `list[Segment]` with monotonic `index` per segment.
4. `collect_translatable(segments)` filters to `(index, text)` pairs where kind is `TRANSLATABLE` and text is non-blank.
5. `translate_segments()` runs in a thread pool executor; chunks items by count/char limits, calls OpenAI or DeepL per chunk, returns `dict[int, str]`.
6. `reassemble(segments, translations)` merges translated text via `_merge_translation()` to preserve leading/trailing whitespace.
7. Response: `TranslateResponse` with full `content`, `segments_total`, `segments_translated`.

**Single file (`POST /api/translate/file`):**

1. Multipart upload: `file`, `target_lang`, `source_lang` form fields.
2. Extension check: `.md`, `.markdown`, `.mdx`.
3. `_decode_upload()`: reject empty/binary; UTF-8 with latin-1 fallback.
4. Same pipeline as text flow via `_translate_file_content()`.
5. Output written to `output/{uuid}_{stem}.{target_lang}{suffix}` (directory created at startup in `src/main.py`).
6. `FileResponse` returns the file with `Content-Disposition` filename `{stem}.{target_lang}{suffix}`.

**Batch (`POST /api/translate/batch`):**

1. Up to 20 files; same extension and decode rules per file.
2. Each file translated through `_translate_file_content()`.
3. `_unique_zip_name()` avoids ZIP entry collisions (appends `_2`, `_3`, …).
4. ZIP built in memory (`io.BytesIO` + `zipfile.ZipFile`); streamed via `StreamingResponse` as `traducciones.zip`.

**Segmentation internals (`src/parser.py`):**

1. Line-by-line scan with `splitlines(keepends=True)`.
2. **Protected blocks:** YAML frontmatter (`---`), fenced code (```` ``` ```` / `~~~`), HTML `<pre>`/`<code>`, indented code blocks (4 spaces or tab, excluding list items).
3. **Special case:** Shell fences (`bash`, `sh`, `shell`, `zsh`, `fish`) — `#` comment lines split

into protected `#` prefix + translatable comment body via `_append_shell_line()`.

4. **Inline code:** `_split_inline_code()` on backtick runs within normal lines.
5. Everything else is `TRANSLATABLE` at line or sub-line granularity.

**State Management:**

- No server-side session or job queue.
- Frontend holds UI state in a plain object in `static/js/app.js` (`state.mode`, `state.selectedFile`, `state.batchFiles`, `state.downloadBlob`).
- Theme preference in `localStorage` (`theme` key).
- Translation provider and API keys loaded once at import via `load_dotenv()` in `src/main.py`.

## Key Abstractions

**Segment pipeline:**

- Purpose: Decouple Markdown structure preservation from translation API details
- Examples: `src/parser.py` (`Segment`, `segment_markdown`, `reassemble`), `src/translator.py` (`translate_segments`)
- Pattern: Index-keyed map — translations keyed by segment `index`, not positional list order in reassembly

**SegmentKind enum:**

- Purpose: Binary classification of markdown fragments
- Examples: `src/parser.py` — `PROTECTED`, `TRANSLATABLE`
- Pattern: Enum with `str` mixin for serializable values

**Provider strategy:**

- Purpose: Swap OpenAI vs DeepL without changing callers
- Examples: `src/translator.py` — `get_provider()`, `_translate_openai_batch()`, `_translate_deepl_batch()`
- Pattern: Env-driven branch inside `translate_segments()`; separate batch sizes (`BATCH_SIZE=15` OpenAI, `DEEPL_BATCH_SIZE=40` DeepL) and language maps (`DEEPL_TARGET_MAP`, `DEEPL_SOURCE_MAP`)

**Chunking with split-on-failure:**

- Purpose: Respect API limits and recover from malformed batch responses
- Examples: `src/translator.py` — `_chunk_items()`, recursive halving in `_translate_openai_batch()` / `_translate_deepl_batch()` on parse/API errors
- Pattern: Greedy chunk by item count + `MAX_BATCH_CHARS` (4000); bisect batch on failure when len > 1

**Pydantic API contracts:**

- Purpose: Request/response validation and OpenAPI schema generation
- Examples: `src/main.py` — `TranslateTextRequest`, `TranslateResponse`, `LanguageItem`, `ProgressEvent`
- Pattern: FastAPI `response_model=` on routes; note `ProgressEvent` is defined but not yet exposed on any endpoint

## Entry Points

**Primary server entry:**

- Location: `src/main.py` — `run()` and `if __name__ == "__main__"`
- Triggers: `python -m src.main`, or CLI script `md-translate` (declared in `pyproject.toml` → `src.main:run`)
- Responsibilities: Configure logging, read `HOST`/`PORT` from env, start uvicorn with `"src.main:app"` and `reload=True`

**ASGI application:**

- Location: `src/main.py` — `app = FastAPI(...)`
- Triggers: uvicorn, any ASGI host
- Responsibilities: Mount `/static`, serve `/` as `static/index.html`, register `/api/*` routes

**Package execution:**

- Location: `pyproject.toml` — `[project.scripts] md-translate = "src.main:run"`
- Triggers: `pip install -e .` then `md-translate`
- Responsibilities: Same as `run()`

**Test entry:**

- Location: `tests/test_parser.py`
- Triggers: `pytest tests/ -q` (config in `pyproject.toml` `[tool.pytest.ini_options]`, `pythonpath = ["."]`)
- Responsibilities: Unit tests for parser only; no HTTP or translator integration tests

## Error Handling

**Strategy:** Fail fast on validation; map provider/runtime errors to HTTP exceptions; log unexpected errors with `logger.exception`.

**Patterns:**

- **400 Bad Request:** Empty content, unsupported language, invalid file extension, binary upload, batch limits (`src/main.py` handlers)
- **502 Bad Gateway:** Generic translation failure after logging (`HTTPException(502, ...)`)
- **503 Service Unavailable:** Missing API key or misconfiguration surfaced as `RuntimeError` from `src/translator.py` (`create_openai_client()`, `create_deepl_client()`, unknown provider)
- **Provider retries:** Up to `MAX_RETRIES` (3) with exponential backoff on rate limits and 429/500/502/503 for OpenAI; similar for DeepL string-matched errors
- **Decode fallback:** `_decode_upload()` tries UTF-8, then latin-1 with replacement — avoids crash but may corrupt non-UTF-8 text silently

## Cross-Cutting Concerns

**Logging:** Python `logging` module; `basicConfig` in `run()` at INFO; module loggers in `src/main.py` and `src/translator.py` for translation failures and retry warnings.

**Validation:** Pydantic models for JSON body; manual checks for file types and batch size; language codes validated against `LANGUAGE_NAMES` (DeepL further validates via `_deepl_target()` / `_deepl_source()` at translation time).

**Authentication:** None — local/dev-oriented service with CORS `allow_origins=["*"]`.

**Concurrency:** Single shared thread pool for all `run_in_executor` translation calls; no explicit rate limiting beyond provider-side retries.

**Configuration:** Environment variables via `.env` (loaded at import); `.env.example` documents OpenAI/server vars; README documents full provider matrix. Secrets never committed (`output/`, `.env` in `.gitignore`).

---

*Architecture analysis: 2026-05-28*
