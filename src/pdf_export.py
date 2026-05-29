"""Export Markdown a PDF (WeasyPrint opcional)."""

from __future__ import annotations

from src.html_export import markdown_to_html

_PDF_EXTRA_CSS = """
@page { size: A4; margin: 2cm; }
body { max-width: none; margin: 0; }
"""

_UNAVAILABLE_MSG = (
    "WeasyPrint no está instalado. "
    'Instala con: pip install weasyprint o pip install -e ".[pdf]"'
)


class PdfExportError(RuntimeError):
    """WeasyPrint ausente o fallo al generar PDF."""


def is_pdf_available() -> bool:
    try:
        import weasyprint  # noqa: F401
    except ImportError:
        return False
    return True


def _html_for_pdf(content: str, *, title: str) -> str:
    html_doc = markdown_to_html(content, title=title)
    return html_doc.replace("</style>", f"{_PDF_EXTRA_CSS}</style>", 1)


def markdown_to_pdf(content: str, *, title: str = "Document") -> bytes:
    """Convierte Markdown a PDF vía HTML intermedio."""
    if not is_pdf_available():
        raise RuntimeError(_UNAVAILABLE_MSG)
    from weasyprint import HTML

    html_doc = _html_for_pdf(content, title=title)
    return HTML(string=html_doc).write_pdf()
