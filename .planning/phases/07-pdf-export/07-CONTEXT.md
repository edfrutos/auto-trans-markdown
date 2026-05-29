# Phase 7 Context — PDF Export

**Milestone:** v2.0 Production Polish & PDF  
**Depends on:** Phase 6 (tech debt closed)  
**Requirements:** PDF-01 … PDF-04

## Problem

v1.0 entrega export **HTML** (client-side UI + `html_export.py` CLI). v2.0 cierra el milestone con **PDF** desde Markdown ya traducido — mismo alcance que HTML (no traducir PDF de entrada).

## User stories

1. **CLI:** `md-translate export doc.es.md -o doc.es.pdf --format pdf` genera PDF legible offline.
2. **Web:** Tras traducir, botón «Export PDF» descarga PDF del contenido en `#output-md` (idioma activo si multi-destino).
3. **Ops:** WeasyPrint es dependencia **opcional**; sin ella, mensaje claro + README con deps sistema.

## Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| D-01 | WeasyPrint como motor principal | Reutiliza HTML de `html_export.markdown_to_html`; mismo look que HTML export |
| D-02 | Extra `[pdf]` en pyproject, no en deps core | Evita romper installs sin Cairo/Pango |
| D-03 | Extender `export` con `--format html\|pdf` (default `html`) | Compat con `md-translate export … -o out.html` existente |
| D-04 | UI vía `POST /api/export/pdf` | PDF server-side; HTML UI sigue client-side con marked |
| D-05 | Tests con mock de WeasyPrint | CI sin libs nativas; `importorskip` para test de integración opcional |
| D-06 | Sin pandoc en v2.0 | Menos superficie; README menciona pandoc solo como alternativa manual |

## Out of scope

- Traducción de PDF/DOCX de entrada
- Batch ZIP con PDFs embebidos
- Estilos PDF avanzados (TOC, portada, numeración)
- WeasyPrint en imagen Docker por defecto (documentar build opcional)

## Success (ROADMAP)

1. CLI genera PDF legible con código en `<pre>`
2. UI «Export PDF» tras traducción
3. Tests + skip si WeasyPrint ausente
4. README: instalación y limitaciones headless/Docker
