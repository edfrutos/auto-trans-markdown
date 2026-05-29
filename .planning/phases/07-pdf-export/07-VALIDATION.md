---
phase: 7
slug: pdf-export
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-29
---

# Phase 7 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest |
| **Quick run** | `pytest tests/test_pdf_export.py tests/test_cli.py -q -k "pdf or export"` |
| **Full suite** | `pytest tests/ -q` |
| **Estimated runtime** | ~25 seconds |

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 07-01-01 | 01 | 1 | PDF-01 | unit | `pytest tests/test_pdf_export.py -q` | ⬜ pending |
| 07-02-01 | 02 | 2 | PDF-02 | unit | `pytest tests/test_cli.py -q -k export_pdf` | ⬜ pending |
| 07-03-01 | 03 | 3 | PDF-03 | integration | `pytest tests/test_api.py -q -k export_pdf` | ⬜ pending |
| 07-03-02 | 03 | 3 | PDF-03 | static | `grep -q 'exportPdf\|btn-export-pdf' static/js/app.js` | ⬜ pending |
| 07-03-03 | 03 | 3 | PDF-04 | manual | README sección PDF + optional deps | ⬜ pending |

## Manual-Only Verifications

| Behavior | Instructions |
|----------|--------------|
| PDF legible | Abrir `.pdf` generado; headings y bloque `pre` visibles |
| UI Export PDF | Traducir en editor → Export PDF → abrir archivo |
| Sin WeasyPrint | CLI/API mensaje 503/exit 2 claro |

## Validation Sign-Off

- [x] All tasks mapped
- [x] Wave 0 complete (html_export baseline exists)
