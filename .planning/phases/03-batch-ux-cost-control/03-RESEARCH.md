# Phase 3 Research: Batch UX & Cost Control

**Researched:** 2026-05-29
**Confidence:** HIGH (ARCHITECTURE.md §7 + existing `on_progress` + FastAPI SSE patterns)

## Summary

Phase 3 adds three backend surfaces on top of the Phase 2 pipeline: **cost estimation** without API calls, **async batch jobs** with SSE progress and cooperative cancel, and **partial ZIP delivery** with `errors.json`. Frontend replaces the fake 30% progress bar in batch mode with `EventSource` and adds inline estimate in Batch + File tabs.

**Build order:** `estimate.py` + API → `batch_zip.py` + `jobs.py` + job endpoints → refactor sync batch to shared ZIP helper → UI (SSE + estimate + cancel) → integration tests.

---

## Cost estimation (`src/estimate.py`)

### API
```python
@dataclass
class EstimateResult:
    segments: int
    characters: int
    estimated_cost_usd: float
    provider: str
    model: str
    exceeds_threshold: bool
    threshold_usd: float

def estimate_markdown(content: str, *, use_memory: bool = True) -> EstimateResult: ...
def estimate_files(contents: list[str], ...) -> EstimateResult: ...  # aggregate
```

### Logic

1. `segment_markdown` → `collect_translatable` per file (same as pipeline, no translate).
2. **characters** = sum of `len(text)` for translatable segments (after TM partition if `use_memory` — count only cache misses for cost).
3. **Pricing table** in `src/estimate.py` constants (OpenAI: per-1M-input tokens heuristic from chars/4; DeepL: per-char rate). Read `OPENAI_MODEL`, `TRANSLATION_PROVIDER` from env.
4. **Threshold:** `ESTIMATE_WARN_USD` env (default `1.0`); `exceeds_threshold = estimated_cost_usd > threshold`.

### Endpoint
`POST /api/translate/estimate`

- JSON body: `{ "content": "..." }` OR multipart files (mirror batch upload)
- Response: `EstimateResult` as JSON (COST-01)

---

## Batch ZIP helper (`src/batch_zip.py`)

Extract from `main.translate_batch` into reusable builder:

```python
@dataclass
class BatchFileSuccess:
    filename: str
    out_name: str
    content: str
    validation: ValidationReport | None

@dataclass
class BatchFileError:
    filename: str
    message: str

def build_batch_zip(
    successes: list[BatchFileSuccess],
    errors: list[BatchFileError],
) -> bytes:
    """Write .md + validation.json per success; errors.json at ZIP root if errors non-empty."""
```

`errors.json` schema:
```json
[
  {"filename": "bad.md", "message": "Traducción incompleta: ..."},
  {"filename": "skip.md", "message": "Cancelado: job cancelado por el usuario"}
]
```

---

## Jobs (`src/jobs.py`)

### Registry

- Module-level `dict[str, BatchJob]` guarded by `asyncio.Lock` (single process, D-18).
- TTL cleanup optional (Claude discretion — evict completed jobs after 1h).

### BatchJob
```python
class JobState(str, Enum):
    pending = "pending"
    running = "running"
    completed = "completed"
    cancelled = "cancelled"

@dataclass
class BatchJob:
    id: str
    state: JobState
    target_lang: str
    source_lang: str
    file_entries: list[tuple[str, str]]  # (original_filename, content)
    cancel_requested: bool = False
    successes: list[BatchFileSuccess] = field(default_factory=list)
    errors: list[BatchFileError] = field(default_factory=list)
    event_queue: asyncio.Queue = field(default_factory=asyncio.Queue)
    zip_bytes: bytes | None = None
    task: asyncio.Task | None = None
```

### Worker loop (per job)
For each `(filename, content)`:

1. If `cancel_requested` before file: append error `{filename, "Cancelado: job cancelado por el usuario"}`; skip.
2. Emit `file_start`.
3. Define `on_progress(done, total)` → emit `segment_progress` with filename.
4. `await loop.run_in_executor(None, partial(translate_markdown, content, options))`.
5. On success: append success, emit `file_done`.
6. On `IncompleteTranslationError` / other: append error, emit `error`, **continue** (D-06).
7. If `cancel_requested` after current file completes: stop loop (D-12).
8. Build ZIP via `build_batch_zip`, emit `complete`.

### SSE events (NOTEBOOK §5, D-02)
| type               | payload fields                                               |
| ------------------ | ------------------------------------------------------------ |
| `file_start`       | `filename`, `file_index`, `total_files`                      |
| `segment_progress` | `filename`, `done`, `total`                                  |
| `file_done`        | `filename`, `file_index`                                     |
| `error`            | `filename`, `message`                                        |
| `complete`         | `ok_count`, `error_count`, `total_files`, `cancelled` (bool) |

Format: `data: {json}\n\n` (standard SSE).

### HTTP routes (main.py)
| Method   | Path                                          | Purpose                                     |
| -------- | --------------------------------------------- | ------------------------------------------- |
| POST     | `/api/translate/batch/jobs`                   | Create job, start worker, return `{job_id}` |
| GET      | `/api/translate/batch/jobs/{job_id}/events`   | `StreamingResponse` SSE                     |
| DELETE   | `/api/translate/batch/jobs/{job_id}`          | Set `cancel_requested=True`                 |
| GET      | `/api/translate/batch/jobs/{job_id}/download` | ZIP when state completed/cancelled          |

Keep `POST /api/translate/batch` synchronous — refactor internals to use `build_batch_zip` after per-file try/except for partial support (optional improvement) or leave sync fail-fast; **jobs path is primary for partial** (D-19).

---

## FastAPI SSE pattern

```python
async def event_generator(job_id: str):
    job = get_job(job_id)
    if not job:
        yield f"data: {json.dumps({'type':'error','message':'Job no encontrado'})}\n\n"
        return
    while True:
        event = await job.event_queue.get()
        yield f"data: {json.dumps(event)}\n\n"
        if event.get("type") == "complete":
            break

return StreamingResponse(event_generator(job_id), media_type="text/event-stream")
```

Send heartbeat comment `: keepalive\n\n` every 15s if queue idle (discretion).

---

## Frontend (`static/js/app.js`)

- `state.batchJobId`, `state.batchJobActive`, `state.eventSource`
- `translateBatch()`: POST jobs → open EventSource → update `#batch-progress-section`
- `cancelBatchJob()`: confirm → DELETE → close ES
- `fetchEstimate(mode)`: POST estimate for batch files or selected file
- Do **not** call `setLoading(true)` fake 30% for batch; use dedicated progress section

---

## Test strategy

| Module         | Tests                                                |
| -------------- | ---------------------------------------------------- |
| `estimate.py`  | segment count, cost math, threshold flag             |
| `batch_zip.py` | successes only; partial + errors.json                |
| `jobs.py`      | mock translate; cancel after file 1; error continues |
| `test_api.py`  | estimate endpoint; job create + SSE parse; download  |

Use `TestClient` + mock `translate_markdown` via dependency or patch.

---

## Validation Architecture

| Requirement   | Verification                                                         |
| ------------- | -------------------------------------------------------------------- |
| JOB-01        | `test_api.py -k job` creates job returns id; SSE stream emits events |
| JOB-02        | Manual UI or test parses segment_progress + file_start               |
| JOB-03        | DELETE sets cancel; worker stops after current file                  |
| JOB-04        | ZIP contains errors.json when errors list non-empty                  |
| COST-01       | `test_estimate.py` + API estimate returns segments/chars/cost        |
| COST-02       | Manual: estimate block visible in batch/file tabs                    |

**Quick run:** `pytest tests/test_estimate.py tests/test_batch_zip.py tests/test_jobs.py -q`
**Full:** `pytest tests/ -q`

---

## RESEARCH COMPLETE
