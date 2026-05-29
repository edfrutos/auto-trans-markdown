# 05-05 Summary

**Plan:** CLI watch + gitignore tree (WATCH-01, TREE-01)

## Entregado

- `src/gitignore_filter.py` — built-ins, `.gitignore`, `iter_markdown_files`
- CLI `watch` con debounce 2s; `dir`/`batch` con `--respect-gitignore`
- `watchdog>=6.0.0` en `requirements.txt` y `pyproject.toml`
- Tests: `tests/test_gitignore_filter.py`, CLI gitignore/export help

## Verificación

`pytest tests/test_gitignore_filter.py tests/test_cli.py -q -k "gitignore or export or watch"` — passed
