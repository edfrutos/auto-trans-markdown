# Phase 7 Research — PDF Export

**Status:** Complete (brownfield + STACK.md)  
**Created:** 2026-05-29

## Existing patterns

| Patrón         | Ubicación                                 | Reutilizar                     |
| -------------- | ----------------------------------------- | ------------------------------ |
| MD → HTML      | `src/html_export.py` `markdown_to_html()` | Entrada directa a WeasyPrint   |
| CLI export     | `src/cli.py` `export_cmd`                 | Añadir `--format`              |
| UI export HTML | `static/js/app.js` `exportHtml()`         | Paralelo `exportPdf()` vía API |
| Optional dep   | `watchdog` en CLI con `_exit_config`      | `is_pdf_available()` + mensaje |

## WeasyPrint pipeline

```text
markdown_to_html(content, title) → str (HTML completo)
         ↓
WeasyPrint HTML(string=html).write_pdf() → bytes
```

**CSS:** Ya embebido en `_EMBEDDED_CSS` de `html_export.py` — PDF hereda tipografía, `pre`, headings teal.

**System deps (Linux/Docker):** `libpango`, `libcairo`, `libgdk-pixbuf`, `libffi` (documentar en README; no bloquear Dockerfile base).

## API design

```http
POST /api/export/pdf
Content-Type: application/json
Authorization: Bearer … (si API_TOKEN)

{"content": "# …", "title": "traduccion.es"}
→ application/pdf
```

503 si WeasyPrint no instalado (`RuntimeError` → HTTPException).

## CLI design

```bash
md-translate export README.es.md -o README.es.pdf --format pdf
md-translate export README.es.md -o README.es.html          # default html
```

Validar extensión `.pdf` / `.html` coherente con `--format` (warning o error amigable).

## Test strategy

| Test                   | Approach                                               |
| ---------------------- | ------------------------------------------------------ |
| `markdown_to_pdf` unit | Mock `weasyprint.HTML.write_pdf` retorna `b"%PDF-"`    |
| `is_pdf_available`     | True si import ok                                      |
| CLI `--format pdf`     | tmp_path + mock pdf_export                             |
| API `/api/export/pdf`  | TestClient + mock                                      |
| Integración real       | `@pytest.mark.skipif(not is_pdf_available())` opcional |

## Risks

| Risk                                    | Mitigation                                                                  |
| --------------------------------------- | --------------------------------------------------------------------------- |
| WeasyPrint falla en macOS sin brew deps | README sección macOS                                                        |
| PDF distinto a preview marked en UI     | Aceptado: PDF usa html_export (como CLI HTML), UI preview usa marked        |
| Imagen Docker sin PDF                   | Documentar `pip install weasyprint` + apt en README; no cambiar CMD default |
