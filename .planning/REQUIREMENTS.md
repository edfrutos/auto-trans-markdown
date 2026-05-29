# Requirements — MarkDown Auto Translator (v2.0 milestone)

**Defined:** 2026-05-29  
**Milestone:** v2.0 Production Polish & PDF  
**Core value:** Traducir solo texto al usuario sin romper Markdown ni código, con coherencia y coste predecible.

## v2.0 Requirements

### Tech debt closure (Phase 6)

- [x] **DEBT-01**: CLI `batch --zip` propaga `--tone` a `_build_options` (paridad con dir/batch output-dir)
- [x] **DEBT-02**: UI web envía `Authorization: Bearer` en fetch/EventSource cuando el usuario configura token (localStorage opt-in, sin commitear secretos)
- [x] **DEBT-03**: Editor multi-idioma: selector o tabs para ver/descargar cada traducción cuando `target_langs` > 1
- [x] **DEBT-04**: Documento `02-VERIFICATION.md` retroactivo (artefacto GSD fase 2)

### PDF export (Phase 7)

- [ ] **PDF-01**: Módulo `pdf_export.py` convierte Markdown traducido a PDF (WeasyPrint o pandoc vía CLI documentado)
- [ ] **PDF-02**: CLI `md-translate export-pdf` (o subcomando `export --format pdf`) genera `.pdf` autocontenido
- [ ] **PDF-03**: Botón «Export PDF» en UI web (mismo flujo que export HTML)
- [ ] **PDF-04**: Tests unitarios del exportador + entrada en README (dependencias opcionales)

## Future Requirements (v2.1+)

- [ ] **V2-02**: Plugin Obsidian o VS Code
- [ ] **V2-03**: Multi-tenant con API key por usuario
- [ ] **V2-04**: Redis job store para despliegue multi-worker
- [ ] **LOCK-01**: Lockfile reproducible (`uv.lock` o pins exactos en requirements)

## Out of Scope (v2.0)

| Feature | Reason |
| ------- | ------ |
| Multi-tenant auth | Diferido V2-03; v2.0 solo Bearer UI para `API_TOKEN` existente |
| Redis jobs | Diferido V2-04 |
| Plugin editor | Diferido V2-02 |
| Traducción directa PDF/DOCX entrada | Pipeline distinto; solo export PDF desde MD ya traducido |

## Traceability

| Requirement | Phase | Status |
| ----------- | ----- | ------ |
| DEBT-01 | 6 | Complete |
| DEBT-02 | 6 | Complete |
| DEBT-03 | 6 | Complete |
| DEBT-04 | 6 | Complete |
| PDF-01 | 7 | Pending |
| PDF-02 | 7 | Pending |
| PDF-03 | 7 | Pending |
| PDF-04 | 7 | Pending |

---
*Requirements defined: 2026-05-29 — v2.0 focused milestone*
