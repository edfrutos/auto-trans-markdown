# 04-04 Summary

**Plan:** CLI multi-idioma `-t es,en,fr`

## Entregado

- `src/cli.py` — `_parse_targets`, loops multi en file/dir/batch
- Sidecars `{stem}.{lang}.validation.json` en batch ZIP
- `tests/test_cli.py` — parse, multi file, multi batch

## Verificación

`pytest tests/test_cli.py -q -k "parse_target or multi"` — PASS
