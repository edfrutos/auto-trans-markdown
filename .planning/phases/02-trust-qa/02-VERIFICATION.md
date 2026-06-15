---
status: passed
phase: 02-trust-qa
verified: 2026-05-29
requirements:

  - VAL-01
  - VAL-02
  - VAL-03
  - PARS-01
  - PARS-02
  - FM-01
  - FM-02
  - PREV-01
  - PREV-02

---

# Phase 2 Verification

> Retroactive sign-off (DEBT-04) — fase ejecutada en v1.0; documento añadido en v2.0 fase 6.

## Must-haves

| Criterio                                                            | Estado   | Evidencia                                               |
| ------------------------------------------------------------------- | -------- | ------------------------------------------------------- |
| Validador post-traducción (fences, links, images, inline, headings) | PASS     | `src/validator.py`, `tests/test_validator.py`           |
| Informe validación en API JSON y ZIP lote                           | PASS     | `TranslateResult.validation`, `{name}.validation.json`  |
| CLI `--strict` bloquea export en error                              | PASS     | `tests/test_cli.py -k strict`                           |
| Comentarios traducibles Python/JS/HTML                              | PASS     | `src/parser.py`, `tests/test_parser.py`                 |
| Frontmatter YAML protegido                                          | PASS     | `tests/test_parser.py -k frontmatter`                   |
| Preview marked + DOMPurify                                          | PASS     | `static/js/app.js` `renderPreview`, CDN en `index.html` |
| Panel Validación colapsable en UI                                   | PASS     | `#validation-section`, plan 02-05                       |

## Automated checks

- `pytest tests/test_validator.py tests/test_parser.py tests/test_pipeline.py tests/test_api.py tests/test_cli.py -q` — green
- `pytest tests/ -q` — suite completa v1.0

## Human verification (recommended)

1. Traducir documento con fences/enlaces — panel Validación muestra checks
2. Fixture XSS en preview — contenido sanitizado (DOMPurify)
3. `md-translate file doc.md --strict` con validación error — exit code 1
