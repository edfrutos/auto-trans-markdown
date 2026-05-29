# Plan 07-03 Summary: API + UI + README PDF

**Completed:** 2026-05-29

## Delivered

- `POST /api/export/pdf` con auth opcional
- Botón `#btn-export-pdf` + `exportPdf()` vía apiFetch
- README sección WeasyPrint (macOS, Debian, Docker)

## Verification

`pytest tests/test_api.py -q -k export_pdf` — passed
