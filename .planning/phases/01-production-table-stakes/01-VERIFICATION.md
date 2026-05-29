---
status: passed
phase: 01-production-table-stakes
verified: 2026-05-28
score: 12/12
---

# Phase 1 Verification: Production Table Stakes

## Must-Haves

| ID | Criterio | Estado |
|----|----------|--------|
| PIPE-01 | `translate_markdown()` usada por API | PASS |
| TM-01 | SQLite persiste traducciones | PASS |
| TM-02 | Lookup antes de proveedor | PASS |
| TM-03 | Clear vía API, UI y CLI | PASS |
| GLOS-01 | glossary.yaml funcional | PASS |
| GLOS-02 | UI gestiona glosario | PASS |
| GLOS-03 | Pipeline aplica glosario | PASS |
| CLI-01 | `md-translate file` | PASS |
| CLI-02 | `md-translate dir` | PASS |
| CLI-03 | `md-translate batch` | PASS |
| CLI-04 | `--dry-run` | PASS |
| CLI-05 | Entry `src.cli:app` | PASS |

## Automated Checks

- `pytest tests/ -q` — 56 passed at phase close (137 at milestone end)

## Notes

- Servidor en ejecución debe reiniciarse para cargar nuevos módulos y rutas.
