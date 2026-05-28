# Codebase Structure

**Analysis Date:** 2026-05-28

## Directory Layout

```
auto-trans-markdown/
├── src/                    # Python application package (pipeline + API)
│   ├── main.py             # FastAPI app, routes, server entry
│   ├── parser.py           # Markdown segmentation and reassembly
│   └── translator.py       # OpenAI / DeepL batch translation
├── static/                 # Frontend (no build step)
│   ├── index.html          # Single-page UI shell
│   ├── css/
│   │   └── app.css         # Design tokens, components, dark mode
│   └── js/
│       └── app.js          # API client, tabs, drag-drop, theme
├── tests/                  # Pytest suite
│   └── test_parser.py      # Parser unit tests only
├── output/                 # Generated translated files (gitignored)
├── .planning/              # GSD planning artifacts
│   └── codebase/           # Codebase map documents (this folder)
├── requirements.txt        # Pip dependencies (mirrors pyproject.toml)
├── pyproject.toml          # Package metadata, pytest config, CLI entry
├── .env.example            # Template for environment variables
├── .env                    # Local secrets (gitignored, do not commit)
├── .gitignore
├── README.md               # User-facing setup and API reference
└── NOTEBOOK.md             # Project notes (non-runtime)
```

## Directory Purposes

**`src/`:**
- Purpose: All server-side logic for the translation product
- Contains: Three flat Python modules — no subpackages, no `__init__.py`
- Key files: `src/main.py`, `src/parser.py`, `src/translator.py`
- Import style: Relative imports within package (`from .parser import ...` in `src/main.py`); tests import as `from src.parser import ...` with `pythonpath = ["."]` in `pyproject.toml`

**`static/`:**
- Purpose: Browser UI served at `/` and `/static/*`
- Contains: HTML, CSS, vanilla JS; Tailwind via CDN in `static/index.html`
- Key files: `static/index.html`, `static/css/app.css`, `static/js/app.js`
- Note: Favicon assets referenced in HTML (`/static/favicon-*.png`, `apple-touch-icon.png`) may exist at runtime but are not required for API operation

**`tests/`:**
- Purpose: Automated tests
- Contains: Parser-focused unit tests
- Key files: `tests/test_parser.py`
- Naming: `test_<behavior>.py` with `test_*` functions

**`output/`:**
- Purpose: Temporary storage for single-file translation downloads
- Contains: `{uuid}_{original_name}.{lang}.md` files created by `POST /api/translate/file`
- Generated: Yes, at request time
- Committed: No (listed in `.gitignore`)

**`.planning/codebase/`:**
- Purpose: Architecture and codebase intelligence for GSD workflows
- Contains: Markdown analysis documents (`ARCHITECTURE.md`, `STRUCTURE.md`, etc.)
- Generated: By `/gsd-map-codebase`
- Committed: Typically yes (no secrets)

## Key File Locations

**Entry Points:**
- `src/main.py`: FastAPI `app`, HTTP routes, `run()` for uvicorn
- `pyproject.toml`: `[project.scripts] md-translate = "src.main:run"`
- `static/index.html`: Web UI entry served at `GET /`

**Configuration:**
- `.env.example`: Documented env var names for OpenAI and server
- `.env`: Local runtime configuration (exists; gitignored)
- `pyproject.toml`: Python version `>=3.11`, dependencies, pytest paths
- `requirements.txt`: Pip-installable dependency list for venv setup

**Core Logic:**
- `src/parser.py`: `segment_markdown()`, `collect_translatable()`, `reassemble()` — add new Markdown protection rules here
- `src/translator.py`: `translate_segments()`, `LANGUAGE_NAMES`, provider clients — add languages or providers here
- `src/main.py`: `_translate_file_content()` — shared orchestration for all translate modes

**Frontend:**
- `static/js/app.js`: All client behavior (tabs, fetch calls, drop zones, download)
- `static/css/app.css`: Component classes (`.card`, `.btn-primary`, `.drop-zone`, dark mode)
- `static/index.html`: Layout, accessibility landmarks, tab panels

**Testing:**
- `tests/test_parser.py`: Segmentation and reassembly tests
- `pyproject.toml` `[tool.pytest.ini_options]`: `testpaths = ["tests"]`, `pythonpath = ["."]`

## Naming Conventions

**Files:**
- Python modules: `snake_case.py` in `src/` (`main.py`, `parser.py`, `translator.py`)
- Tests: `test_<module_or_feature>.py` under `tests/`
- Static assets: `kebab-case` or simple names (`app.js`, `app.css`, `index.html`)

**Directories:**
- Lowercase, short names: `src`, `static`, `tests`, `output`
- Frontend split by type: `static/css/`, `static/js/`

**Functions (Python):**
- Public API: `snake_case` without leading underscore (`segment_markdown`, `translate_segments`, `collect_translatable`)
- Internal helpers: leading underscore (`_decode_upload`, `_chunk_items`, `_translate_openai_batch`)
- Async route handlers: `snake_case` decorated with `@app.get` / `@app.post`

**Classes / types:**
- Pydantic models: PascalCase (`TranslateTextRequest`, `TranslateResponse`, `LanguageItem`)
- Dataclasses / enums: PascalCase (`Segment`, `SegmentKind`)
- Constants: UPPER_SNAKE_CASE (`LANGUAGE_NAMES`, `BATCH_SIZE`, `FENCE_PATTERN`)

**JavaScript (`static/js/app.js`):**
- Functions: `camelCase` (`loadLanguages`, `translateEditor`, `setupDropZone`)
- DOM refs object: `els` with camelCase keys matching element purpose
- State object: `state` with camelCase keys
- CSS classes: kebab-case in HTML/Tailwind; semantic component classes in `app.css` (`.btn-primary`, `.tab-btn-active`)

**API routes:**
- Prefix `/api/` for JSON/multipart endpoints
- Resource-oriented paths: `/api/languages`, `/api/translate`, `/api/translate/file`, `/api/translate/batch`
- Static mount: `/static` → `static/` directory

**Output files:**
- Pattern: `{uuid.hex}_{stem}.{target_lang}{suffix}` on disk in `output/`
- Client download name: `{stem}.{target_lang}{suffix}` (no UUID)
- Batch ZIP entries: `{stem}.{target_lang}{suffix}` with numeric suffix on collision

## Where to Add New Code

**New Markdown protection rule (e.g. mermaid blocks, admonitions):**
- Primary code: `src/parser.py` — extend the line loop in `segment_markdown()` or add a helper like `_append_shell_line()`
- Tests: `tests/test_parser.py` — one test per rule for protected vs translatable behavior and reassembly

**New translation provider (e.g. Azure Translator, Gemini):**
- Primary code: `src/translator.py` — add `_translate_<provider>_batch()`, branch in `translate_segments()`, env check in client factory
- Configuration: `.env.example`, `README.md` env table
- API layer: Usually no changes in `src/main.py` unless new request fields needed

**New language:**
- Primary code: `src/translator.py` — add to `LANGUAGE_NAMES`; if DeepL should support it, add mappings in `DEEPL_TARGET_MAP` / `DEEPL_SOURCE_MAP`
- API: `GET /api/languages` auto-includes new entries via `LANGUAGE_NAMES`

**New HTTP endpoint or upload mode:**
- Primary code: `src/main.py` — new `@app` route; reuse `_translate_file_content()` when input is Markdown text
- Frontend: `static/js/app.js` — new fetch handler; `static/index.html` — UI panel if user-facing

**New UI feature (progress streaming, settings panel):**
- Markup: `static/index.html`
- Behavior: `static/js/app.js`
- Styles: `static/css/app.css` (prefer CSS variables in `:root` / `html.dark`)
- Backend: `src/main.py` if new API needed (e.g. wire `ProgressEvent` + SSE/WebSocket — not present today)

**Shared utilities (path helpers, encoding):**
- Keep in `src/main.py` if HTTP-specific (`_decode_upload`, `_unique_zip_name`)
- Keep in `src/parser.py` if Markdown-specific
- Keep in `src/translator.py` if provider-specific
- Avoid new top-level modules unless the codebase grows beyond these three concerns

**Tests:**
- Parser behavior: `tests/test_parser.py`
- New test modules: `tests/test_translator.py`, `tests/test_api.py` following `test_*.py` naming
- Run: `pytest tests/ -q` from project root

## Special Directories

**`output/`:**
- Purpose: Persist single-file translation results for `FileResponse`
- Generated: Yes, per `POST /api/translate/file`
- Committed: No — may contain private translated documents

**`.venv/`:**
- Purpose: Local Python virtual environment
- Generated: Yes, via `python3 -m venv .venv`
- Committed: No

**`.pytest_cache/`, `.mypy_cache/`:**
- Purpose: Tool caches
- Generated: Yes
- Committed: No

**`.git/hooks/`:**
- Purpose: Git hooks (e.g. pre-commit)
- Committed: Hook scripts may live in repo; this is standard git metadata

**`static/` (assets):**
- Purpose: Committed frontend source
- Generated: No build output directory — edit files in place
- Committed: Yes (`static/index.html`, `static/css/app.css`, `static/js/app.js`)

---

*Structure analysis: 2026-05-28*
