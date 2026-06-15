# Phase 2 Research: Trust & QA

**Researched:** 2026-05-28
**Confidence:** HIGH (brownfield patterns verified; PyYAML already in requirements; marked/DOMPurify standard CDN stack)

## Summary

Phase 2 adds trust layers on top of the Phase 1 pipeline: structural validator (`src/validator.py`), selective frontmatter translation in `parser.py`, extended fence comment rules (python/js/ts/html/xml), UI preview with sanitization, and CLI `--strict`. Backend work precedes UI; parser/frontmatter can parallel validator module.

**Build order:** `validator.py` + tests → parser comment langs + frontmatter → pipeline/API/CLI integration → UI preview + validation panel.

---

## Validator (`src/validator.py`)

### API surface
```python
@dataclass
class ValidationCheck:
    id: str          # fences | links | images | inline_code | headings
    status: str      # pass | warn | error
    message: str
    expected: int | None = None
    actual: int | None = None

@dataclass
class ValidationReport:
    overall: str     # pass | warn | error (worst status wins)
    checks: list[ValidationCheck]

def validate_translation(original: str, translated: str) -> ValidationReport:
    ...
```

### Check implementations (regex/heuristic, no AST dependency)

| Check ID      | Method                                                                         | Error rule                   | Warn rule |
| ------------- | ------------------------------------------------------------------------------ | ---------------------------- | --------- |
| `fences`      | Count opening fence markers (triple backtick or tilde), strip-aware            | `abs(orig - trans) > 0`      | —         |
| `links`       | `re.findall(r'(?<!!)\[[^\]]*\]\([^)]+\)', text)`                               | count mismatch               | —         |
| `images`      | `re.findall(r'!\[[^\]]*\]\([^)]+\)', text)`                                    | count mismatch               | —         |
| `inline_code` | Count backtick runs (pairs of inline spans)                                    | count mismatch               | —         |
| `headings`    | Per-line `#` depth sequence (ignore `#` in fences via strip code blocks first) | any line index depth differs | —         |

**Strip fenced blocks before inline/heading checks:** Remove content between fence pairs to avoid false positives on `#` in code.

**Overall status:** `error` if any check is `error`; else `warn` if any `warn`; else `pass`.

**No length >300% check** in Phase 2 (deferred per D-03).

---

## Pipeline integration

Extend `TranslateResult`:
```python
@dataclass
class TranslateResult:
    content: str
    segments_total: int
    segments_translated: int
    cache_hits: int = 0
    cache_misses: int = 0
    dry_run_segments: list[tuple[int, str]] | None = None
    validation: ValidationReport | None = None  # NEW
```

In `translate_markdown()` after `reassemble`:
```python
validation = validate_translation(content, output)
return TranslateResult(..., validation=validation)
```

Add `TranslateOptions.strict: bool = False` — when True and `validation.overall == "error"`, raise `ValidationFailedError` before returning (CLI maps to exit 1; API can skip or use 422 — planner: raise in pipeline, catch in CLI only for write paths).

**Alternative for API:** Always return validation in response; never block HTTP (D-01). CLI `--strict` calls pipeline with `strict=True` or checks report before `write_text`.

---

## API contract

Extend `TranslateResponse`:
```python
class ValidationCheckModel(BaseModel):
    id: str
    status: str
    message: str

class ValidationReportModel(BaseModel):
    overall: str
    checks: list[ValidationCheckModel]

class TranslateResponse(BaseModel):
    content: str
    segments_total: int
    segments_translated: int
    validation: ValidationReportModel | None = None
```

Batch ZIP (`main.py`): for each translated file, add `{stem}.validation.json` alongside `{stem}.md` (or `{rel_path}.validation.json` preserving dirs).

Serialize with `dataclasses.asdict` or dedicated `validation_to_dict()`.

---

## CLI `--strict` (VAL-03)

Add to `file`, `dir`, `batch` commands:
```python
strict: bool = typer.Option(False, "--strict", help="No escribir salida si validación falla")
```

After `translate_markdown()`:
```python
if strict and result.validation and result.validation.overall == "error":
    typer.secho("Validación fallida — salida no escrita", fg=typer.colors.RED, err=True)
    raise typer.Exit(code=1)
```

Warnings do not block (D-01/D-02).

---

## Parser — fence comment languages (PARS-01, PARS-02)

### Registry pattern (extend shell)
```python
HASH_COMMENT_LANGS = frozenset({"python"})
SLASH_COMMENT_LANGS = frozenset({"javascript", "typescript", "js", "ts"})
HTML_COMMENT_LANGS = frozenset({"html", "xml"})

HASH_COMMENT = re.compile(r"^(\s*#\s?)(.*?)(\n?)$", re.DOTALL)
SLASH_COMMENT = re.compile(r"^(\s*//\s?)(.*?)(\n?)$", re.DOTALL)
HTML_COMMENT = re.compile(r"(^[\s]*)(<!--)(.*?)(-->)", re.DOTALL)
```

Replace `_is_shell_fence` / `_append_shell_line` with:

- `_fence_lang(info: str) -> str | None`
- `_is_comment_fence(info, registry) -> bool`
- `_append_comment_line(segments, line, idx, lang) -> int`

**Edge cases (tests required):**

- Shebang `#!/usr/bin/env python` — entire line PROTECTED
- `#` inside python string — line without leading `#` after strip stays PROTECTED (only match `^\s*#`)
- `//` in URL inside comment line — still translatable comment body (acceptable v1)
- HTML comment spanning one line only in v1 (multi-line `<!--` … `-->` as single PROTECTED block optional)

---

## Frontmatter selective translation (FM-01, FM-02)

### Whitelist (hardcoded)
```python
FM_TRANSLATABLE_KEYS = frozenset({
    "title", "description", "summary", "tags", "categories", "keywords"
})
FM_PROTECTED_KEYS = frozenset({"date", "slug", "id", "layout", "author"})
```

### Flow in `segment_markdown`

1. Detect frontmatter block (existing).
2. Try `yaml.safe_load(block_inner)` — on `YAMLError`, PROTECTED whole block (D-17).
3. Walk dict/list recursively; emit TRANSLATABLE segments for string values whose key path ends in whitelist key.
4. Store segment metadata to rebuild (index → yaml path) OR: translate in-place dict then `yaml.dump` with `allow_unicode=True, default_flow_style=False, sort_keys=False`.

**Recommended:** Segment individual string values with stable indices; on reassemble, rebuild YAML from original structure + translated values using `ruamel.yaml` OR manual walk + `yaml.dump`. **Use PyYAML** (already pinned): parse → mutate copy → dump; accept key reorder risk (warn in tests).

**Never translate:** numbers, bools, None, keys not in whitelist, nested keys under protected parents.

---

## Preview — marked + DOMPurify (PREV-01, PREV-02)

**CDN (index.html):**
```html
<script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/dompurify@3.2.4/dist/purify.min.js"></script>
```

**app.js helper:**
```javascript
function renderPreview(markdown, el) {
  if (!el || typeof marked === 'undefined' || typeof DOMPurify === 'undefined') return;
  const raw = marked.parse(markdown || '', { gfm: true, breaks: false });
  el.innerHTML = DOMPurify.sanitize(raw, { USE_PROFILES: { html: true }, FORBID_TAGS: ['script', 'iframe'] });
}
```

Call after successful translate and sample load only (D-09).

---

## Test strategy

| Module          | File                      | Coverage                                                            |
| --------------- | ------------------------- | ------------------------------------------------------------------- |
| validator       | `tests/test_validator.py` | each check pass/warn/error; overall aggregation                     |
| parser comments | `tests/test_parser.py`    | python `#`, js `//`, html `<!-- -->`; shebang protected             |
| frontmatter     | `tests/test_parser.py`    | whitelist translated; slug/date protected; invalid YAML protected   |
| pipeline        | `tests/test_pipeline.py`  | `validation` populated on translate                                 |
| API             | `tests/test_api.py`       | response includes validation; batch ZIP contains `.validation.json` |
| CLI             | `tests/test_cli.py`       | `--strict` exit 1 on error, writes on pass                          |

---

## Validation Architecture

Nyquist dimension mapping for Phase 2 plans:

| Plan focus          | Dimension        | Verification                                      |
| ------------------- | ---------------- | ------------------------------------------------- |
| validator.py        | Unit correctness | `pytest tests/test_validator.py`                  |
| parser extensions   | Regression       | `pytest tests/test_parser.py`                     |
| pipeline/API        | Integration      | `pytest tests/test_pipeline.py tests/test_api.py` |
| CLI strict          | CLI contract     | `pytest tests/test_cli.py --strict`               |
| UI preview          | XSS safety       | Manual + fixture `[x](javascript:alert(1))` inert |
| UI validation panel | API contract     | response.validation rendered                      |

Each PLAN.md task with logic changes MUST include `pytest` in acceptance_criteria.

---

## Risks (PITFALLS.md)

| Pitfall                         | Mitigation in Phase 2                             |
| ------------------------------- | ------------------------------------------------- |
| #1 Plain text translation       | Validator confirms structure preserved            |
| #2 Chunk desync                 | Fence count check catches gross breakage          |
| #4 XSS in preview               | DOMPurify mandatory (PITFALL #5)                  |
| #21 Frontmatter keys translated | Whitelist + protected keys                        |
| YAML reorder on dump            | Accept v1; document; test round-trip keys present |

---

## Dependencies

- `pyyaml>=6.0.2` — already in requirements.txt
- No new Python deps for validator (stdlib `re` only)
- CDN scripts only for preview (no npm)

---

## RESEARCH COMPLETE
