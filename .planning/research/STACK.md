# Technology Stack

**Project:** MarkDown Auto Translator — NOTEBOOK milestone extensions  
**Researched:** 2026-05-28  
**Mode:** Ecosystem (brownfield extension)  
**Confidence:** HIGH for core extensions; MEDIUM for optional Phase E items

## Executive Recommendation

Extend the existing **Python 3.11+ / FastAPI / vanilla JS** monolith in place. Do **not** introduce a frontend build step, ORM, or Redis for this milestone. The standard 2025 stack for local-first Markdown translation tools that add glossary, TM, CLI, validation, SSE, and Docker is:

| Layer | Keep | Add |
|-------|------|-----|
| Runtime | CPython 3.11+, Uvicorn | — |
| API | FastAPI ≥0.135, Pydantic v2 | `fastapi.sse.EventSourceResponse` |
| CLI | — | **Typer** (not Click) |
| Persistence | — | **stdlib `sqlite3`** (TM) + JSON/YAML files (glossary) |
| Config | python-dotenv | **PyYAML**, optional **pydantic-settings** |
| Frontend | Tailwind CDN, vanilla JS | **marked.js + DOMPurify** (CDN) |
| Packaging | pip + pyproject.toml | **uv lockfile** + multi-stage **Docker** |
| Watch | — | **watchdog** (Phase E) |

This matches patterns in comparable local-first tools (FoundryL10n, TransDuck) and aligns with FastAPI/Typer author conventions.

---

## Recommended Stack

### Core Framework (unchanged + bump)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Python | ≥3.11 | Runtime | Already declared; 3.12 in Docker for slim wheels |
| FastAPI | ≥0.135.0 | HTTP API, SSE, validation | Native SSE via `EventSourceResponse` since 0.135 — no manual `StreamingResponse` framing |
| Uvicorn | `[standard]≥0.32` | ASGI server | Keep; `[standard]` includes websockets/httptools |
| Pydantic | v2 (via FastAPI) | Request/response models | Already in use; extend for glossary/TM DTOs |
| python-dotenv | ≥1.0.1 | `.env` loading | Keep at import time in `main.py` |
| python-multipart | ≥0.0.12 | File uploads | Keep for batch/file endpoints |

**Bump rationale:** Pin `fastapi>=0.135.0` when adding SSE. Older versions require hand-rolled `text/event-stream` formatting; 0.135+ handles keep-alive pings, `Cache-Control`, and `X-Accel-Buffering` automatically ([FastAPI SSE docs](https://fastapi.tiangolo.com/tutorial/server-sent-events/)).

### Translation Providers (unchanged)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| openai | ≥1.55.0 | LLM translation + glossary in prompt | Default provider; JSON batch format already works |
| deepl | ≥1.20.0 | Neural MT + formality | Lazy import pattern already correct |

No change to provider SDKs. Glossary injection belongs in `translator.py` prompts (OpenAI) and placeholder pre/post-processing (DeepL).

### Persistence — Translation Memory & Glossary

| Technology | Version | Purpose | When to Use |
|------------|---------|---------|-------------|
| **sqlite3** (stdlib) | — | TM: `data/translation_memory.db` | **Default for TM** — sync API, WAL mode, zero deps |
| **PyYAML** | ≥6.0.2 | `glossary.yaml`, frontmatter parsing | Glossary file + selective frontmatter (NOTEBOOK §1, §8) |
| JSON (stdlib) | — | Validation reports, glossary export | Machine-readable batch reports in ZIP |

**Why stdlib sqlite3 over aiosqlite/SQLModel:**

- TM access pattern is simple: `SELECT translation WHERE hash=? AND src=? AND tgt=?` — no ORM needed.
- Existing codebase already offloads blocking I/O via `asyncio.run_in_executor()` in `main.py`; wrap TM reads/writes the same way.
- CLI (`md-translate file`) runs synchronously — one implementation, no dual sync/async DB layer.
- Local-first tools (TransDuck, FoundryL10n) use plain SQLite files on disk; proven pattern.

**TM schema (recommended minimum):**

```sql
CREATE TABLE IF NOT EXISTS tm_entries (
    segment_hash TEXT NOT NULL,
    source_lang  TEXT NOT NULL,
    target_lang  TEXT NOT NULL,
    source_text  TEXT NOT NULL,
    translation  TEXT NOT NULL,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (segment_hash, source_lang, target_lang)
);
CREATE INDEX IF NOT EXISTS idx_tm_langs ON tm_entries(source_lang, target_lang);
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
```

**Hash key:** `sha256(normalize(text) + source_lang + target_lang)` as specified in NOTEBOOK §2.

**Glossary storage:** YAML file at project root (`glossary.yaml`) loaded at startup; optional UI CRUD writes back to same file. PyYAML with `safe_load`/`safe_dump` only.

### CLI

| Technology | Version | Purpose | When to Use |
|------------|---------|---------|-------------|
| **Typer** | ≥0.21.0 | `md-translate` CLI with subcommands | All new CLI work (NOTEBOOK §3) |
| Rich | (transitive via Typer) | Progress bars, colored output | Batch dir translation, CI logs |

**Why Typer over Click:**

- Same author/ecosystem as FastAPI (Sebastián Ramírez); type-hint-driven, less boilerplate.
- Native shell completion, subcommand groups (`md-translate file`, `md-translate dir`, `md-translate serve`).
- Official pattern for `pyproject.toml` entry points ([Typer packaging docs](https://github.com/fastapi/typer/blob/master/docs/tutorial/package.md)).

**Entry point change (required):**

```toml
[project.scripts]
md-translate = "src.cli:app"   # Typer app, not src.main:run
```

Add `serve` subcommand that wraps existing Uvicorn startup; decouple CLI from server boot.

**Exit codes:** 0 success, 1 partial failure (some files in batch), 2 fatal — standard for CI integration.

### Real-Time Progress (SSE)

| Technology | Version | Purpose | When to Use |
|------------|---------|---------|-------------|
| **fastapi.sse** | (FastAPI ≥0.135) | `EventSourceResponse`, `ServerSentEvent` | Batch progress stream (NOTEBOOK §5) |
| **asyncio.Queue** | stdlib | Per-job event bus | In-process job events — no Redis |
| **EventSource** | Browser native | Client consumer | Replace simulated spinner in `static/js/app.js` |

**Why SSE over WebSocket:**

- One-way server→client progress fits SSE exactly; no bidirectional need.
- Works over standard HTTP; simpler behind Docker/nginx.
- FastAPI 0.135+ first-class support with typed `ServerSentEvent(data=..., event="file_done", id=...)`.

**Job orchestration (local-first, no Redis):**

```
POST /api/translate/batch  →  returns { job_id }
GET  /api/translate/batch/{job_id}/stream  →  SSE (EventSourceResponse)
```

Store `job_id → asyncio.Queue` in an in-memory dict on the FastAPI app state. Acceptable for single-process local deployment; document limitation for multi-worker Uvicorn.

**Client events (NOTEBOOK contract):** `file_start`, `file_done`, `segment_progress`, `error`, `complete`.

**Critical implementation notes:**

- Check `await request.is_disconnected()` in generator loop to avoid leaks.
- Set cookies *before* returning `EventSourceResponse`, not on injected `Response`.
- Do **not** add Redis until horizontal scaling is a real requirement (Out of Scope per PROJECT.md).

### Validation

| Technology | Version | Purpose | When to Use |
|------------|---------|---------|-------------|
| **stdlib `re`, `dataclasses`** | — | Structure checks (fences, links, headings) | `src/validator.py` — no new deps |
| Pydantic models | — | Validation report JSON schema | API response + ZIP sidecar |

Validation is pure Python over source/translated strings. Avoid `markdown-it-py` or similar unless fuzzy AST comparison is needed later — regex/count-based checks match NOTEBOOK §6 and keep deps minimal.

### Frontend Extensions (CDN-only, no npm)

| Library | Delivery | Purpose | When to Use |
|---------|----------|---------|-------------|
| **marked** | jsDelivr CDN | MD → HTML preview | NOTEBOOK §4 |
| **DOMPurify** | jsDelivr CDN | XSS sanitization of preview HTML | **Mandatory** with marked |
| **diff-match-patch** | jsDelivr CDN | Side-by-side diff | NOTEBOOK §14 (Phase E) |

**Why stay CDN/vanilla:**

- Existing `static/` has no bundler; introducing Vite/webpack is disproportionate scope.
- marked explicitly warns output is **not sanitized** — DOMPurify postprocess hook is non-negotiable ([marked.js.org](https://marked.js.org/)).

```javascript
// Pattern for static/js/preview.js
marked.use({
  hooks: {
    postprocess(html) { return DOMPurify.sanitize(html); }
  }
});
```

Keep Tailwind CDN and Plus Jakarta Sans; extend `app.css` for preview/diff panels.

### Configuration

| Technology | Version | Purpose | When to Use |
|------------|---------|---------|-------------|
| python-dotenv | ≥1.0.1 | Secrets, provider keys | Keep |
| **pydantic-settings** | ≥2.0 | Typed config (`GlossaryConfig`, TM paths, TTL) | Optional but recommended for Phase A+ |
| PyYAML | ≥6.0.2 | `config.yaml` for frontmatter allowlist | NOTEBOOK §8 |

Extend `.env.example`; never commit `.env`. Add `DATA_DIR=data/` for TM DB and glossary overrides.

### File Watch (Phase E)

| Technology | Version | Purpose | When to Use |
|------------|---------|---------|-------------|
| **watchdog** | ≥6.0.0 | Filesystem events for `input/` → `output/` | NOTEBOOK §15 |
| **watchdog[watchmedo]** | optional | Shell utility for dev | Debugging only |

Cross-platform native backends (FSEvents on macOS, inotify on Linux). Use `PatternMatchingEventHandler(patterns=["*.md", "*.markdown", "*.mdx"])`. Debounce rapid saves (300–500 ms) before triggering translation.

Implement as `md-translate watch ./input -o ./output` subcommand, not a background thread in the web server.

### Docker & Deployment

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **python:3.12-slim-bookworm** | pinned digest | Runtime base | glibc compatibility for compiled wheels (WeasyPrint later); ~150 MB |
| **uv** | latest (copy binary from `ghcr.io/astral-sh/uv`) | Lockfile install in build | 10–100× faster than pip; standard 2025 Python packaging |
| **multi-stage Dockerfile** | — | Builder + runtime | Dependencies cached separately from app code |
| **docker-compose.yml** | v2 | Local team deploy | Volumes, env, healthcheck |

**Recommended Dockerfile pattern** ([uv Docker guide](https://docs.astral.sh/uv/guides/integration/docker/)):

1. **Builder stage:** `uv sync --locked --no-install-project` → copy source → `uv sync --locked --no-editable`
2. **Runtime stage:** copy `.venv` + app only; `USER 65532:65532` (non-root)
3. **HEALTHCHECK:** `curl -f http://localhost:8000/api/languages || exit 1`
4. **Volumes:** `./data:/app/data` (TM + glossary), `./output:/app/output`

**Target image size:** <200 MB achievable with slim + no dev deps (`uv sync --no-dev`).

**Do not use Alpine** unless pure-Python confirmed — DeepL/OpenAI SDKs and future WeasyPrint need glibc wheels.

### Package Management

| Tool | Role | Recommendation |
|------|------|----------------|
| **uv** | Primary lockfile (`uv.lock`) | Add and commit; `uv sync` in dev/CI/Docker |
| **pip + requirements.txt** | Compatibility export | Generate via `uv export --no-hashes -o requirements.txt` for users without uv |
| **pytest** | Testing | Add to `[dependency-groups] dev` in pyproject.toml |

Current gap (no lockfile) should be closed in Phase A — reproducible builds matter once Docker lands in Phase D.

### Testing

| Technology | Version | Purpose | When to Use |
|------------|---------|---------|-------------|
| pytest | ≥8.0 | Unit/integration tests | Parser, validator, TM, glossary |
| **httpx** | ≥0.28 | Async FastAPI test client | SSE endpoint tests |
| pytest-asyncio | ≥0.24 | Async test support | TM + SSE integration |

Keep tests colocated in `tests/`. Add `tests/test_memory.py`, `tests/test_validator.py`, `tests/test_cli.py`.

### Phase E / Deferred (document now, add later)

| Technology | Version | Purpose | Defer Because |
|------------|---------|---------|---------------|
| WeasyPrint | ≥62 | PDF export | Heavy system deps in Docker; NOTEBOOK §19 |
| pandoc | system binary | HTML/PDF via CLI | External binary; optional sidecar container |
| tiktoken | ≥0.8 | Token/cost estimation | Nice for §10; can approximate with char/4 initially |
| SQLCipher | — | Encrypted TM | Only if enterprise privacy requirement emerges |

For cost estimation (NOTEBOOK §10), start with character counts + static price table in config — add tiktoken when accuracy matters.

---

## Module-to-Stack Mapping

| New module | Primary stack | NOTEBOOK ref |
|------------|---------------|--------------|
| `src/glossary.py` | PyYAML + Pydantic | §1 |
| `src/memory.py` | sqlite3 (WAL) | §2 |
| `src/cli.py` | Typer + Rich | §3 |
| `src/validator.py` | stdlib re/dataclasses | §6 |
| `src/jobs.py` | asyncio.Queue + SSE | §5 |
| `src/config.py` | pydantic-settings + PyYAML | §8, §13 |
| `static/js/preview.js` | marked + DOMPurify | §4 |
| `static/js/progress.js` | EventSource API | §5 |
| `Dockerfile` | uv + python:3.12-slim | §11 |

Extend existing modules rather than replace:

- `parser.py` → PyYAML frontmatter, more comment languages
- `translator.py` → glossary injection, TM lookup/store, provider fallback
- `main.py` → SSE routes, estimate endpoint, multi-target

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| CLI | **Typer** | Click | More boilerplate; Typer aligns with FastAPI stack |
| CLI | **Typer** | argparse | Fine for tiny scripts; subcommands/CI UX worse at NOTEBOOK scale |
| TM storage | **sqlite3 stdlib** | aiosqlite | Extra dep; executor pattern already established |
| TM storage | **sqlite3 stdlib** | JSON files per lang-pair | No indexing; poor performance on large batches |
| TM storage | **sqlite3 stdlib** | SQLModel/SQLAlchemy | ORM overhead for 1-table KV cache |
| TM storage | **sqlite3 stdlib** | Redis | Violates local-first; ops burden for solo dev |
| Progress | **SSE + in-memory queue** | WebSocket | Bidirectional not needed; more client complexity |
| Progress | **SSE** | Redis pub/sub | Overkill for single-process app |
| Frontend | **CDN marked+DOMPurify** | npm + Vite + react-markdown | Breaks zero-build static architecture |
| Preview | **marked (client)** | Python `markdown` server-side | Extra round-trip; preview is UI-only |
| Lockfile | **uv.lock** | poetry.lock | Project already pip/pyproject; uv is faster, 2025 default |
| Lockfile | **uv.lock** | pip-tools only | No cross-platform universal lock |
| Docker base | **python:3.12-slim** | python:3.12-alpine | musl breaks some wheels; slim is safer |
| Docker base | **python:3.12-slim** | distroless | Good for hardened prod; harder debug for local-first tool |
| Watch | **watchdog** | polling loop | CPU waste; watchdog uses native OS APIs |
| Config | **pydantic-settings** | raw os.environ | Scales as env vars multiply in NOTEBOOK |

---

## Installation

### Development (uv — recommended)

```bash
# Install uv if missing
curl -LsSf https://astral.sh/uv/install.sh | sh

# Sync environment from lockfile
uv sync --group dev

# Add NOTEBOOK milestone dependencies
uv add typer pyyaml pydantic-settings
uv add --group dev pytest httpx pytest-asyncio

# Bump FastAPI for SSE
uv add "fastapi>=0.135.0"

# Optional Phase E
uv add watchdog
```

### Development (pip — fallback)

```bash
pip install -r requirements.txt
pip install typer pyyaml pydantic-settings watchdog
pip install pytest httpx pytest-asyncio
```

### Docker

```bash
docker compose up --build
# API at http://localhost:8000
# Health: GET /api/languages
```

---

## Dependency Additions Summary

**Phase A (immediate):**

```
typer>=0.21.0
pyyaml>=6.0.2
pydantic-settings>=2.0
fastapi>=0.135.0   # bump
```

**Phase B–C:**

```
# No new runtime deps — validator is stdlib; SSE is FastAPI built-in
httpx>=0.28        # dev/test only
```

**Phase D:**

```
# Docker: uv in Dockerfile only (not a Python dep)
```

**Phase E:**

```
watchdog>=6.0.0
# weasyprint>=62  — defer until PDF export committed
```

---

## Sources

| Source | Confidence | Used for |
|--------|------------|----------|
| [FastAPI SSE tutorial](https://fastapi.tiangolo.com/tutorial/server-sent-events/) | HIGH | EventSourceResponse, ServerSentEvent |
| [Typer docs / Context7 `/fastapi/typer`](https://github.com/fastapi/typer) | HIGH | CLI entry points, subcommands |
| [aiosqlite Context7 `/omnilib/aiosqlite`](https://github.com/omnilib/aiosqlite) | HIGH | Evaluated; rejected in favor of stdlib + executor |
| [uv Docker integration](https://docs.astral.sh/uv/guides/integration/docker/) | HIGH | Multi-stage build, lockfile |
| [uv project layout](https://docs.astral.sh/uv/concepts/projects/layout/) | HIGH | uv.lock as source of truth |
| [marked.js security warning](https://marked.js.org/) | HIGH | DOMPurify requirement |
| [watchdog GitHub](https://github.com/gorakhargosh/watchdog) | HIGH | File watch (v6.0, Python 3.9+) |
| FoundryL10n, TransDuck (GitHub) | MEDIUM | Local-first SQLite TM patterns |
| Typer vs Click comparisons (2025–2026) | MEDIUM | CLI framework choice |

---

*Stack research for NOTEBOOK milestone — extends `.planning/codebase/STACK.md` brownfield baseline.*
