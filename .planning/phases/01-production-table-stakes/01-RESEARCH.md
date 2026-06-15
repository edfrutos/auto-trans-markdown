# Phase 1 Research: Production Table Stakes

**Researched:** 2026-05-28
**Confidence:** HIGH (Typer, sqlite3 stdlib, PyYAML — patrones documentados; pipeline brownfield verificado)

## Summary

Phase 1 introduce cuatro módulos nuevos (`pipeline.py`, `memory.py`, `glossary.py`, `cli.py`) sin reescribir parser ni proveedores. La fachada `translate_markdown()` centraliza la lógica hoy duplicada en `_translate_file_content()` y handlers HTTP. TM y glosario se integran en el pipeline, no en `translator.py` ni `parser.py`.

**Build order:** `pipeline.py` → `memory.py` → `glossary.py` → API glossary/TM routes → glossary UI → CLI Typer.

---

## SQLite Translation Memory Schema

**Database path:** `data/translation_memory.db` (gitignored)

**Initialization (`memory.py`):**
```python
CREATE TABLE IF NOT EXISTS translation_memory (
    hash TEXT PRIMARY KEY,
    source_text TEXT NOT NULL,
    source_lang TEXT NOT NULL,      -- 'auto' when unknown
    target_lang TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_tm_langs ON translation_memory(source_lang, target_lang);
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
```

**Hash function:**
```python
def make_key(text: str, source_lang: str | None, target_lang: str) -> str:
    normalized = " ".join(text.split())  # collapse whitespace, strip via split/join
    src = source_lang or "auto"
    payload = f"{normalized}|{src}|{target_lang}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
```

**API surface (`memory.py`):**

- `TranslationMemory(db_path: Path)` context manager or lazy init
- `lookup(items: list[tuple[int, str]], source_lang, target_lang) -> tuple[dict[int, str], list[tuple[int, str]]]` — returns (hits, misses)
- `store(entries: list[tuple[str, str, str, str, str]])` — batch insert/replace (hash, source_text, source_lang, target_lang, translated_text)
- `clear() -> int` — DELETE all; returns row count
- `count() -> int` — for UI display optional

**Concurrency:** Single-process Uvicorn + WAL sufficient for local/CI; no Redis.

---

## Glossary YAML Schema

**Default path:** `glossary.yaml` at project root (configurable via `GLOSSARY_PATH` env or `TranslateOptions.glossary_path`).

**Schema (version 1):**
```yaml
version: 1
do_not_translate:
  - API Gateway
  - MarkDown Auto Translator
pairs:
  en-es:
    dashboard: panel
    "piece of cake": pan comido
  auto-es:
    dashboard: panel
```

**Rules:**

- `do_not_translate`: case-sensitive substring match on segment text before provider call; wrap matches to preserve literal (DeepL placeholders; OpenAI instruction).
- `pairs`: keyed by `{source}-{target}` where source may be `auto` for any detected source.
- Longest-match-first when applying replacements to avoid partial overlaps.
- Empty file or missing file → glossary disabled (no error); log info once.

**OpenAI integration:** Append to batch context:
```text
GLOSSARY RULES (mandatory):
- Do NOT translate: API Gateway, MarkDown Auto Translator
- en→es: "dashboard" → "panel"; "piece of cake" → "pan comido"
```

**DeepL integration:**

1. Pre: replace terms with `⟦GLO0⟧`, `⟦GLO1⟧`, …; store mapping.
2. Translate segment with placeholders.
3. Post: replace placeholders with fixed translation or original (DNT).

**Validation on PUT:** `version` must be 1; `pairs` values must be dict[str, str]; keys must match `^[a-z]{2}(-[A-Z]{2})?-(auto|[a-z]{2}(-[A-Z]{2})?)$`.

---

## Typer Entry Points

**pyproject.toml change (CLI-05):**
```toml
[project.scripts]
md-translate = "src.cli:app"
```

**src/cli.py structure:**
```python
import typer
app = typer.Typer(name="md-translate", help="Traduce Markdown preservando formato")

@app.command("file")
def file_cmd(input: Path, target: str = typer.Option(..., "-t"), ...): ...

@app.command("dir")
def dir_cmd(path: Path, ...): ...

@app.command("batch")
def batch_cmd(...): ...

memory_app = typer.Typer()
@memory_app.command("clear")
def memory_clear(): ...

app.add_typer(memory_app, name="memory")

@app.command("serve")
def serve_cmd(host: str = None, port: int = None):
    from src.main import run
    run()
```

**Invocation examples:**
```bash
md-translate file README.md -t es -o README.es.md
md-translate dir docs/ -t en -o docs-en/ --recursive
md-translate batch ./articles/*.md -t fr --zip out.zip
md-translate file doc.md -t es --dry-run
md-translate memory clear
md-translate serve
```

**Exit codes:** 0 success; 1 translation/provider error; 2 usage/config error.

**Dependencies:** Load `.env` via `load_dotenv()` at cli import (same as main).

---

## Pipeline Flow (prose diagram)

1. **Input:** `content: str` + `TranslateOptions`.
2. **Validate languages** via `is_valid_target_lang` / `is_valid_source_lang` (raise `ValueError` for CLI; HTTP layer maps to 400).
3. **Parse:** `segments = segment_markdown(content)`; `translatable = collect_translatable(segments)`.
4. **Dry-run branch:** If `options.dry_run`, return `TranslateResult` with `dry_run_segments=translatable`, empty content, no provider/TM calls.
5. **Memory partition:** If `use_memory`, `hits, misses = tm.lookup(translatable, source, target)`; else `hits={}, misses=translatable`.
6. **Glossary pre-process:** If `use_glossary`, transform `misses` segment texts (DNT wrap / placeholder); load rules from `glossary.yaml`.
7. **Translate:** `translate_segments(misses_processed, target, source, on_progress=options.on_progress)` — only uncached segments.
8. **Glossary post-process:** Restore placeholders / apply fixed translations on provider output for miss indices.
9. **Merge:** `translations = {**hits, **new_translations}` keyed by segment index.
10. **Memory store:** If `use_memory`, persist new translations (post-glossary text) for each miss.
11. **Reassemble:** `output = reassemble(segments, translations)`.
12. **Return:** `TranslateResult(content=output, segments_total=len(segments), segments_translated=len(translatable), cache_hits=len(hits), cache_misses=len(misses))`.

**Error propagation:** `IncompleteTranslationError` and `RuntimeError` bubble to callers unchanged; main.py maps to HTTP; CLI maps to exit code 1/2.

---

## API Additions (main.py)

| Method   | Path            | Purpose                       |
| -------- | --------------- | ----------------------------- |
| DELETE   | `/api/memory`   | Clear TM (TM-03)              |
| GET      | `/api/glossary` | Read glossary.yaml (GLOS-02)  |
| PUT      | `/api/glossary` | Write glossary.yaml (GLOS-02) |

Existing translate routes unchanged in contract; internally use pipeline.

---

## Security Considerations

| Area               | Risk                         | Mitigation                                                                  |
| ------------------ | ---------------------------- | --------------------------------------------------------------------------- |
| glossary.yaml PUT  | Path traversal / YAML bombs  | Write only to resolved project glossary path; `safe_load`; size limit 256KB |
| TM DB              | Local data leakage           | `data/` gitignored; no expose via static mount                              |
| CLI dir/batch      | Arbitrary file read          | Resolve paths; skip symlinks outside root optional                          |
| DeepL placeholders | Placeholder leaked in output | Post-process restore in finally block                                       |

---

## Testing Strategy

| Module        | Tests                                                           |
| ------------- | --------------------------------------------------------------- |
| `pipeline.py` | Unit: dry-run, delegates to parser/translator; mock TM/glossary |
| `memory.py`   | Unit: lookup/store/clear/hash normalization; temp DB            |
| `glossary.py` | Unit: DNT, pair rules, OpenAI prompt block, DeepL wrap/restore  |
| `cli.py`      | Typer `CliRunner`: file --dry-run, memory clear, exit codes     |
| Integration   | API uses pipeline; glossary applied in POST /api/translate      |

Extend `tests/conftest.py` with `tmp_glossary`, `tmp_memory_db` fixtures.

---

## Dependencies to Add

```toml
"typer>=0.21.0",
"pyyaml>=6.0.2",
```

Optional for CLI UX: `rich` (Typer default extra) — use if already pulled transitively.

---

## Architectural Responsibility Map

| Module          | Owns                                                                |
| --------------- | ------------------------------------------------------------------- |
| `parser.py`     | Segmentation only — NO glossary/TM                                  |
| `translator.py` | Provider batches — optional glossary prompt hook via caller         |
| `pipeline.py`   | Orchestration — ONLY place that sequences TM + glossary + translate |
| `memory.py`     | SQLite persistence                                                  |
| `glossary.py`   | YAML load/save/apply                                                |
| `main.py`       | HTTP routing, static, decode uploads                                |
| `cli.py`        | Typer commands, exit codes                                          |

---

*Research complete: 2026-05-28*
