---
phase: 01-production-table-stakes
plan: 05
requirements-completed: [CLI-01, CLI-02, CLI-03, CLI-04, CLI-05]
key-files:
  created: [src/cli.py, tests/test_cli.py]
  modified: [pyproject.toml, requirements.txt, README.md]
completed: 2026-05-28
---

# 01-05: CLI Typer

**`md-translate` con file/dir/batch/serve/memory; entry point `src.cli:app`; dry-run JSON lines.**

## Self-Check: PASSED

- `pytest tests/test_cli.py tests/ -q` — 56 tests verde
