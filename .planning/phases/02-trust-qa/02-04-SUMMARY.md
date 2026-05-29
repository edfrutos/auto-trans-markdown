# Plan 02-04 Summary: CLI --strict

**Completed:** 2026-05-29

## Delivered

- Flag `--strict` en `file`, `dir`, `batch`
- Exit code 1 sin escribir salida cuando `validation.overall == error`
- Warnings no bloquean

## Verification

`pytest tests/test_cli.py -q -k strict` — passed
