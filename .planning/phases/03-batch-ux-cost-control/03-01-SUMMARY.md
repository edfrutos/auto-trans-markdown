---
phase: 03-batch-ux-cost-control
plan: 01
status: complete
requirements:
  - COST-01
---

# Plan 03-01 Summary

## Objective
Estimación de coste pre-traducción (COST-01).

## Delivered
- `src/estimate.py` — `EstimateResult`, `estimate_markdown`, `estimate_files` con TM lookup y pricing OpenAI/DeepL
- `POST /api/translate/estimate` — JSON o multipart
- `ESTIMATE_WARN_USD` en `.env.example`
- `tests/test_estimate.py` + tests API estimate

## Self-Check: PASSED
- pytest tests/test_estimate.py tests/test_api.py -k estimate — green
