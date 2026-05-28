---
phase: 01-production-table-stakes
plan: 02
requirements-completed: [TM-01, TM-02, TM-03]
key-files:
  created: [src/memory.py, tests/test_memory.py]
  modified: [src/pipeline.py, src/main.py, .gitignore]
completed: 2026-05-28
---

# 01-02: Memoria SQLite

**TM con WAL en `data/`; lookup pre-glosario y store post-traducción; `DELETE /api/memory`.**

## Self-Check: PASSED

- `pytest tests/test_memory.py tests/test_pipeline.py -q` — verde
