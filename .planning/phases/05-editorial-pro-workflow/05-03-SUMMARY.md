# 05-03 Summary

**Plan:** Modo revisión draft/finalize (REV-01, REV-02)

## Entregado

- `src/review.py` — `build_draft`, `score_doubtful`, `finalize_draft`
- API: `POST /api/translate/draft`, `POST /api/translate/finalize`
- UI: modo revisión, panel segmentos editables, segmentos dudosos resaltados
- Tests: `tests/test_review.py`, draft/finalize en `tests/test_api.py`

## Verificación

`pytest tests/test_review.py tests/test_api.py -q -k "draft or finalize or review"` — passed
