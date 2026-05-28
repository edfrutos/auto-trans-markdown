---
phase: 01-production-table-stakes
plan: 01
requirements-completed: [PIPE-01]
key-files:
  created: [src/pipeline.py, tests/test_pipeline.py]
  modified: [src/main.py]
completed: 2026-05-28
---

# 01-01: Fachada pipeline

**`translate_markdown()` unifica segment→translate→reassemble; API delega vía `run_in_executor`.**

## Self-Check: PASSED

- `pytest tests/test_pipeline.py tests/test_api.py -q` — verde
- `_translate_file_content` eliminado de `src/main.py`
