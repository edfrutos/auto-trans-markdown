---
status: passed
phase: 03-batch-ux-cost-control
verified: 2026-05-29
requirements:

  - JOB-01
  - JOB-02
  - JOB-03
  - JOB-04
  - COST-01
  - COST-02

---

# Phase 3 Verification

## Must-haves

| Criterio   | Estado   | Evidencia   |
| ---------- | -------- | ----------- |

| Progreso real vía SSE (archivo, segmentos, %) | PASS | `src/jobs.py` eventos; UI EventSource |
| Cancelación desde UI                          | PASS | DELETE job + `cancelBatchJob()`       |
| ZIP parcial + errors.json                     | PASS | `build_batch_zip`, tests partial      |
| Estimación pre-traducción                     | PASS | `estimate.py`, UI estimate blocks     |

## Automated checks

- `pytest tests/ -q` — 94 passed

## Human verification (recommended)

1. Lote 3 archivos — barra y lista actualizan; descarga ZIP
2. Cancelar a mitad — confirm, ZIP parcial
3. Seleccionar archivo/lote — bloque estimate visible
