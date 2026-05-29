# Phase 4 Research: Team Scale

**Researched:** 2026-05-29
**Confidence:** HIGH (CONTEXT.md locked + brownfield patterns from Phase 3)

## Summary

Phase 4 extends the translation surface to **multiple target languages per request**, adds **deployment hardening** (CORS, upload limits, output TTL), packages the app with **Docker**, and achieves **CLI parity** with `-t es,en,fr`.

**Build order:** `target_langs.py` + API/jobs/estimate/batch_zip → `deployment.py` security → UI chips + nested SSE progress → CLI multi-loop → Dockerfile/compose + integration tests.

---

## Multi-target parsing (`src/target_langs.py`)

### API
```python
def parse_target_langs(
    target_lang: str | None,
    target_langs: list[str] | None,
) -> list[str]:
    """Merge target_lang (single) and target_langs (list); dedupe; validate non-empty."""

def validate_target_langs_http(target_langs: list[str]) -> None:
    """HTTPException 400 if any lang unsupported by active provider."""
```

### Rules (D-05, D-06)
- If `target_langs` provided, use it; elif `target_lang`, wrap as one-element list.
- Reject empty list.
- Max languages: **10** (reasonable cap; document in README).
- Order preserved for UI progress.

### Output naming (D-07)
- Translated file: `{stem}.{lang}{suffix}` e.g. `README.es.md`
- Validation sidecar: `{stem}.{lang}.validation.json` (disambiguates multi-lang ZIP)

### Worker order (file_then_lang)
```python
for filename, content in file_entries:
    for lang in target_langs:
        translate_markdown(content, TranslateOptions(target_lang=lang, ...))
```

### Concurrency (D-08)
- `MULTI_LANG_CONCURRENCY` env, default `1`.
- When >1, use `asyncio.Semaphore` around per-lang translate in job worker only (keep sync endpoints serial for simplicity).

### SSE events (D-09)
Add `target_lang` to: `file_start`, `segment_progress`, `file_done`, `error`.
Optional `lang_index`, `total_langs` for UI nested progress.

---

## Estimate multi-target

Loop `target_langs`, sum `EstimateResult` fields (segments, characters, cost).
Response adds `language_count: int`.

---

## Deployment hardening (`src/deployment.py`)

| Env | Default | Purpose |
|-----|---------|---------|
| `CORS_ORIGINS` | `http://127.0.0.1:5400,http://localhost:5400` | Comma-separated; `*` only if explicit |
| `MAX_UPLOAD_MB` | `10` | Per-file upload cap |
| `MAX_BATCH_UPLOAD_MB` | `50` | Total bytes per batch/job request |
| `OUTPUT_TTL_HOURS` | `24` | Delete files in `output/` older than TTL |
| `OUTPUT_SWEEP_INTERVAL_HOURS` | `6` | Background periodic sweep |
| `API_TOKEN` | unset | If set, require `Authorization: Bearer {token}` on `/api/*` |

### Functions
- `get_cors_origins() -> list[str]`
- `check_upload_size(filename, size_bytes, batch_total)` → raise ValueError
- `sweep_output_dir(output_dir: Path)` → int deleted count
- `optional_api_token_middleware` or dependency for FastAPI

### Startup (main.py)
- `@app.on_event("startup")`: run sweep once
- `asyncio.create_task` periodic sweep loop (cancel on shutdown)

---

## Docker (NOTEBOOK §11, D-11–D-15)

### Dockerfile (multi-stage)
1. **builder:** `python:3.11-slim`, `pip install -r requirements.txt` to `/install`
2. **runtime:** copy site-packages, `src/`, `static/`, non-root user `appuser`, `WORKDIR /app`
3. `EXPOSE 5400`, `CMD uvicorn src.main:app --host 0.0.0.0 --port ${PORT:-5400}`

### docker-compose.yml
```yaml
services:
  md-translate:
    build: .
    ports: ["5400:5400"]
    env_file: .env
    volumes:
      - ./data:/app/data
      - ./output:/app/output
    healthcheck:
      test: ["CMD", "curl", "-f", "http://127.0.0.1:5400/api/languages"]
      interval: 30s
      timeout: 5s
      retries: 3
```

Use `python:3.11-slim` + install `curl` for healthcheck OR wget. Alternative: `CMD python -c "urllib.request.urlopen(...)"`.

### Profiles (Claude discretion)
- Default: prod (no reload)
- Document `docker compose --profile dev` with reload if added

**Note:** DOCKER-01 mentions `uv.lock`; CONTEXT D-12 uses `requirements.txt` — satisfy with pinned multi-stage pip install.

---

## UI multi-select (D-02, D-04)

- Keep `#target-lang` select as **picker to add** language chip.
- `#target-lang-chips` container with removable chips; `state.targetLangs: string[]`.
- FormData: repeat `target_langs` field per lang (FastAPI `list` form).
- JSON endpoints: `target_langs: ["es","en"]`.
- Progress list: `<li data-file>` with nested `<ul data-langs>` per file.

---

## CLI (D-20–D-22)

```python
def _parse_targets(target: str) -> list[str]:
    return [t.strip() for t in target.split(",") if t.strip()]
```

For `file` with multiple langs: write `{stem}.{lang}.md` for each.
For `dir`/`batch`: nested loop file × lang.

---

## Validation Architecture

| Requirement | Test approach |
|-------------|---------------|
| MULTI-01 | API + UI grep + CLI `-t es,en` |
| MULTI-02 | ZIP namelist `*.es.md`, `*.en.md` |
| DOCKER-01 | `docker build` succeeds; non-root user |
| DOCKER-02 | compose volumes documented |
| SEC-01 | CORS test with allowed/blocked Origin |
| SEC-02 | 413/400 on oversized upload; sweep tests |

---

## RESEARCH COMPLETE
