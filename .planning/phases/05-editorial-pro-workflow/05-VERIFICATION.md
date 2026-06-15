---
status: passed
phase: 05-editorial-pro-workflow
verified: 2026-05-29
requirements:

  - REV-01
  - REV-02
  - FALL-01
  - DIFF-01
  - WATCH-01
  - TREE-01
  - TONE-01
  - HIST-01
  - EXPORT-01

---

# Phase 5 Verification

## Must-haves

| Criterio                            | Estado   | Evidencia                                                 |
| ----------------------------------- | -------- | --------------------------------------------------------- |
| Modo revisión con segmentos dudosos | PASS     | `review.py`, `/api/translate/draft`, UI `#review-section` |
| Fallback DeepL → OpenAI             | PASS     | `05-01-SUMMARY`, tests fallback                           |
| Diff original vs traducido          | PASS     | `renderDiff`, diff-match-patch CDN                        |
| Watch + árbol con gitignore         | PASS     | `watch` CLI, `gitignore_filter.py`                        |
| Tono formal/informal                | PASS     | `--tone`, API/UI selector                                 |
| Historial opt-in sin contenido      | PASS     | `localStorage` metadatos only                             |
| Export HTML autocontenido           | PASS     | `html_export.py`, CLI/UI export                           |

## Automated checks

- `pytest tests/ -q` — 137 passed

## Human verification (recommended)

1. Editor — activar modo revisión, traducir, editar segmento dudoso, Confirmar
2. Tab Diff — ver resaltado de cambios por segmento
3. `md-translate export doc.md -o doc.html` — abrir HTML offline
4. `md-translate dir docs/ --respect-gitignore` — omitir `node_modules/`
