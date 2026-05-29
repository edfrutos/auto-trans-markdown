# 04-01 Summary

**Plan:** Backend multi-idioma (target_langs, jobs, estimate, API endpoints)

## Entregado

- `src/target_langs.py` — parse, validate, naming `stem.{lang}.md`
- `src/jobs.py` — loop file×lang, SSE con `target_lang`
- `src/estimate.py` — `estimate_for_langs`, `language_count`
- `src/main.py` — translate/file/batch/jobs/estimate multi-destino
- Tests: `test_target_langs.py`, `test_jobs.py` (multi), `test_api.py` (multi)

## Verificación

`pytest tests/test_target_langs.py tests/test_jobs.py tests/test_api.py -q -k multi` — PASS
