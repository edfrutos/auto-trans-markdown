# Phase 6 Research — v1 Tech Debt Closure

**Status:** Complete (brownfield — codebase inspection, no external research)  
**Created:** 2026-05-29

## Findings

### DEBT-01: CLI batch ZIP tone gap

**Location:** `src/cli.py` ~296–298 vs ~328–329

```python
# ZIP branch — missing tone
options = _build_options(lang, source, dry_run, no_memory, no_glossary, glossary_path)
# output-dir branch — correct
options = _build_options(lang, source, dry_run, no_memory, no_glossary, glossary_path, tone)
```

**Fix:** One-line parity — pass `tone` in ZIP branch.  
**Test:** Extend `tests/test_cli.py` with mock capturing `options.tone`.

### DEBT-02: UI auth + SSE

**Server:** `src/deployment.py` — `verify_api_token`; `src/main.py` — `_require_api_token` on most POST routes but **not** on:

- `GET /api/translate/batch/jobs/{job_id}/events` (line 728)
- `GET .../download`, `DELETE .../cancel` (also unprotected)

**Client:** No `Authorization` header in any `fetch()` in `static/js/app.js`.

**SSE constraint:** Native `EventSource` does not support custom headers. Options:

| Approach | Pros | Cons |
|----------|------|------|
| Query `?access_token=` | Simple, works with EventSource | Token in URL/logs — mitigated: localhost deploy, optional feature |
| fetch + ReadableStream SSE polyfill | Headers supported | More JS complexity |
| Cookie session | Clean SSE | Requires server session — out of scope |

**Chosen:** D-01 — extend `_require_api_token` to accept `access_token` query param OR `Authorization` header; UI appends token to EventSource URL when set.

**UI pattern:** Collapsible settings block in header/footer: password input, Save/Clear, persisted in localStorage. Helper `apiFetch(url, init)` merges auth headers.

### DEBT-03: Editor multi-lang

**Current:** `translateEditor()` stores only primary lang in `els.outputMd`, `state.downloadBlob`, preview.

**API:** `POST /api/translate` with `target_langs` returns `{ translations: { es: {...}, en: {...} } }`.

**Fix:** `state.translationResults = data.translations`; `state.activeResultLang = primary`; tabs call `showTranslationForLang(lang)` updating output, preview, validation, download name.

**File mode:** Already returns ZIP for multi-lang — no change needed.

### DEBT-04: Missing 02-VERIFICATION.md

Phase 2 has `02-VALIDATION.md` (Nyquist map) but no sign-off `02-VERIFICATION.md`. Summaries 02-01…02-05 + test suite provide evidence for retroactive doc.

## Dependencies

- Phase 5 tone (`TranslateOptions.tone`) — shipped
- Phase 4 multi-target API — shipped
- Phase 4 deployment auth — shipped (partial wiring)

## Risks

| Risk | Mitigation |
|------|------------|
| Token in SSE URL logged by proxies | Document localhost/single-user; optional feature |
| Tab switch loses unsaved editor edits | Disable tabs during review mode or warn on switch |
| Retroactive verification inaccurate | Cross-check against summaries + pytest module list |
