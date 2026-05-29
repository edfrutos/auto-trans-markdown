# 05-06 Summary

**Plan:** Historial opt-in + export HTML (HIST-01, EXPORT-01)

## Entregado

- `src/html_export.py` — `markdown_to_html` con CSS embebido
- CLI `export`; UI `exportHtml()`, historial localStorage (solo metadatos)
- README sección flujo editorial

## Verificación

`pytest tests/test_html_export.py -q` — passed  
UI: `#history-enabled`, `exportHtml` en `app.js`
