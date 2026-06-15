# Phase 4 Pattern Map

**Mapped:** 2026-05-29

## New files → closest analogs

| New file              | Analog                                     | Pattern to reuse                 |
| --------------------- | ------------------------------------------ | -------------------------------- |
| `src/target_langs.py` | `src/translator.py` `is_valid_target_lang` | Validation + HTTP errors in main |
| `src/deployment.py`   | `src/estimate.py` env helpers              | `_threshold_usd()` pattern       |
| Docker                | none in repo                               | Standard python slim multi-stage |

## Integration points

| Location           | Change                                                                                |
| ------------------ | ------------------------------------------------------------------------------------- |
| `src/main.py`      | parse_target_langs on all translate/estimate/job routes; CORS from env; startup sweep |
| `src/jobs.py`      | `target_langs: list[str]`; nested file×lang loop; SSE `target_lang`                   |
| `src/estimate.py`  | aggregate multi-lang                                                                  |
| `src/batch_zip.py` | `{stem}.{lang}.validation.json`                                                       |
| `static/js/app.js` | chips UI; nested progress; `target_langs` in FormData                                 |
| `src/cli.py`       | comma-split `-t`; multi output files                                                  |

## PATTERN MAPPING COMPLETE
