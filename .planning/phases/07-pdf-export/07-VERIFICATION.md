---
status: passed
phase: 07-pdf-export
verified: 2026-05-29
requirements:
  - PDF-01
  - PDF-02
  - PDF-03
  - PDF-04
---

# Phase 7 Verification

## Must-haves

| Criterio | Estado | Evidencia |
|----------|--------|-----------|
| MD → PDF vía WeasyPrint opcional | PASS | `src/pdf_export.py`, mock tests |
| CLI `--format pdf` | PASS | `src/cli.py`, `test_export_pdf` |
| UI Export PDF + API | PASS | `/api/export/pdf`, `#btn-export-pdf` |
| README deps opcionales | PASS | README sección Export PDF |

## Automated checks

- `pytest tests/ -q` — 148 passed

## Human verification (recommended)

1. `pip install weasyprint` → `md-translate export doc.md -o doc.pdf --format pdf`
2. UI: traducir → Export PDF → abrir archivo
3. Sin WeasyPrint: API 503, CLI exit 2 con mensaje claro
