# Phase 3 Pattern Map

**Mapped:** 2026-05-29

## New files → closest analogs

| New file           | Analog                               | Pattern to reuse                       |
| ------------------ | ------------------------------------ | -------------------------------------- |
| `src/estimate.py`  | `src/pipeline.py`                    | Same segment/TM path without translate |
| `src/batch_zip.py` | `src/main.py` `translate_batch` loop | Zip writestr + validation.json paths   |
| `src/jobs.py`      | `src/main.py` `_translate_content`   | run_in_executor + asyncio.Queue events |

## Integration points

| Location            | Change                                                |
| ------------------- | ----------------------------------------------------- |
| `src/main.py`       | Add estimate + job routes; keep sync batch            |
| `static/js/app.js`  | EventSource pattern new; estimate like glossary fetch |
| `static/index.html` | Collapsible/progress like validation panel            |

## PATTERN MAPPING COMPLETE
