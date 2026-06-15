# Technology Stack

**Analysis Date:** 2026-05-28

## Languages

**Primary:**

- Python 3.11+ (declared in `pyproject.toml` `requires-python`; README and local venv may use 3.14) — backend API, Markdown parsing, translation orchestration in `src/`

**Secondary:**

- JavaScript (ES modules, vanilla) — web client in `static/js/app.js`
- HTML5 — SPA shell in `static/index.html`
- CSS — custom styles in `static/css/app.css` plus Tailwind utility classes

## Runtime

**Environment:**

- CPython interpreter (local development via `python3 -m venv .venv`)
- ASGI server: Uvicorn serving the FastAPI app

**Package Manager:**

- pip (primary install path: `pip install -r requirements.txt`)
- setuptools (build backend declared in `pyproject.toml`)
- Lockfile: **missing** — no `requirements.lock`, `poetry.lock`, or `uv.lock`; versions are minimum pins only (`>=`)

## Frameworks

**Core:**

- FastAPI `>=0.115.0` — HTTP API, request validation (Pydantic models), static file mount, file upload handling in `src/main.py`
- Uvicorn `[standard]>=0.32.0` — dev/production ASGI server; entry via `uvicorn.run("src.main:app", ...)` in `src/main.py` `run()`
- Pydantic (via FastAPI) — `TranslateTextRequest`, `TranslateResponse`, `LanguageItem` in `src/main.py`

**Translation / AI:**

- OpenAI Python SDK `openai>=1.55.0` — Chat Completions API with JSON response format in `src/translator.py` (`create_openai_client`, `_translate_openai_batch`)
- DeepL Python SDK `deepl>=1.20.0` — batch `translate_text` in `src/translator.py` (`create_deepl_client`, `_translate_deepl_batch`)

**Testing:**

- pytest — configured in `pyproject.toml` `[tool.pytest.ini_options]` with `testpaths = ["tests"]`, `pythonpath = ["."]`
- **Not** listed in `requirements.txt`; README documents optional `pip install pytest`

**Build/Dev:**

- python-dotenv `>=1.0.1` — loads `.env` at import time in `src/main.py` (`load_dotenv()`)
- python-multipart `>=0.0.12` — multipart form uploads for file/batch endpoints

## Key Dependencies

**Critical:**

- `fastapi` — REST API surface (`/api/languages`, `/api/translate`, `/api/translate/file`, `/api/translate/batch`)
- `openai` — default translation provider (`TRANSLATION_PROVIDER=openai`, default model `gpt-4o-mini`)
- `deepl` — alternate neural translation provider
- Standard library modules heavily used: `asyncio`, `zipfile`, `pathlib`, `re`, `json`, `logging` in `src/main.py`, `src/parser.py`, `src/translator.py`

**Infrastructure (transitive / implicit):**

- `requests` — pulled in by `deepl` SDK (visible in `.venv`, not pinned at project level)
- Starlette — underlying FastAPI stack (static files, CORS, responses)

**Frontend (CDN, not npm):**

- Tailwind CSS — loaded from `https://cdn.tailwindcss.com` in `static/index.html`
- Google Fonts — Plus Jakarta Sans from `fonts.googleapis.com` in `static/index.html`

## Configuration

**Environment:**

- `python-dotenv` loads `.env` from project root when `src/main.py` imports (working directory matters for relative `.env` resolution)
- `.env` file present (gitignored); template: `.env.example`
- Provider selection: `TRANSLATION_PROVIDER` (`openai` default, `deepl` alternative) read in `src/translator.py` `get_provider()`

**Key configs required:**

| Variable               | Used in               | Purpose                                            |
| ---------------------- | --------------------- | -------------------------------------------------- |
| `OPENAI_API_KEY`       | `src/translator.py`   | OpenAI-compatible API auth                         |
| `OPENAI_MODEL`         | `src/translator.py`   | Model id (default `gpt-4o-mini`)                   |
| `OPENAI_BASE_URL`      | `src/translator.py`   | Optional compatible endpoint (Ollama, Azure, etc.) |
| `DEEPL_API_KEY`        | `src/translator.py`   | DeepL auth when provider is `deepl`                |
| `DEEPL_API_URL`        | `src/translator.py`   | Optional API host (e.g. free tier URL per README)  |
| `TRANSLATION_PROVIDER` | `src/translator.py`   | `openai` or `deepl`                                |
| `HOST`                 | `src/main.py` `run()` | Bind address (default `127.0.0.1`)                 |
| `PORT`                 | `src/main.py` `run()` | Listen port (default `8000`)                       |

**Note:** `.env.example` documents only OpenAI and server vars; README documents full provider matrix including DeepL and `TRANSLATION_PROVIDER`.

**Build:**

- `pyproject.toml` — project metadata, dependencies mirror `requirements.txt`, console script `md-translate = src.main:run`
- `requirements.txt` — flat dependency list for pip
- No Docker, Makefile, or CI config detected in repo root

## Platform Requirements

**Development:**

- Python 3.11 or newer
- Virtual environment recommended (`.venv/` gitignored)
- At least one translation API key (OpenAI **or** DeepL depending on `TRANSLATION_PROVIDER`)
- Modern browser for `static/` UI (fetch API, FormData uploads)

**Production:**

- Single-process Uvicorn deployment (no separate worker config in repo)
- Writable `output/` directory — created at startup in `src/main.py` for temporary translated file downloads
- Outbound HTTPS to chosen translation API (OpenAI-compatible host or DeepL)
- No container or cloud hosting manifests in repository

## Project Layout (stack-relevant)

| Path                   | Role                                             |
| ---------------------- | ------------------------------------------------ |
| `src/main.py`          | FastAPI app, routes, static mount, CLI `run()`   |
| `src/parser.py`        | Markdown segmentation (stdlib `re`, dataclasses) |
| `src/translator.py`    | OpenAI / DeepL batch translation                 |
| `static/`              | Frontend assets served at `/static`              |
| `tests/test_parser.py` | Parser unit tests only                           |
| `output/`              | Ephemeral translated `.md` files (gitignored)    |

## Console entry points

```bash
python -m src.main          # Starts Uvicorn with reload=True
md-translate                # Same via pyproject script entry (after pip install -e .)
```

OpenAPI docs auto-generated at `/docs` (FastAPI default).

---

*Stack analysis: 2026-05-28*
