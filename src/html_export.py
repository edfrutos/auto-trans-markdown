"""Export Markdown a HTML autocontenido.

Convierte un subconjunto de CommonMark a HTML con CSS embebido.
Soporta: headings h1–h6, párrafos, listas UL/OL, blockquotes,
reglas horizontales, bloques de código con resaltado de lenguaje,
código inline, negrita, cursiva, tachado, enlaces, imágenes e
imagen-como-enlace.  No usa dependencias externas.
"""

from __future__ import annotations

import html
import re

# ── CSS embebido ──────────────────────────────────────────────────────────────

_CSS = """
/* ── Pantalla ────────────────────────────────────────────────────────────── */
body { font-family: system-ui, -apple-system, sans-serif; line-height: 1.7;
       max-width: 48rem; margin: 2rem auto; padding: 0 1.5rem; color: #1e293b; }
h1 { font-size: 2em;   color: #0f766e; margin-top: 1em;   border-bottom: 2px solid #e2e8f0; padding-bottom: .3em; }
h2 { font-size: 1.5em; color: #0f766e; margin-top: 1.4em; border-bottom: 1px solid #e2e8f0; padding-bottom: .2em; }
h3,h4,h5,h6 { color: #0f766e; margin-top: 1.2em; }
p  { margin: .75em 0; }
a  { color: #0369a1; }
img { max-width: 100%; height: auto; vertical-align: middle; }
pre { background: #f1f5f9; padding: 1rem; overflow-x: auto;
      border-radius: .5rem; white-space: pre-wrap; word-break: break-word; }
code { background: #f1f5f9; padding: .1em .35em;
       border-radius: .25rem; font-size: .88em; font-family: ui-monospace, monospace; }
pre code { background: none; padding: 0; border-radius: 0; font-size: .9em; }
blockquote { border-left: 4px solid #14b8a6; margin: .75em 0;
             padding: .1em 1em; color: #475569; background: #f8fafc; }
ul, ol { padding-left: 1.5rem; margin: .75em 0; }
li { margin: .25em 0; }
hr { border: none; border-top: 1px solid #cbd5e1; margin: 1.5em 0; }
del { color: #94a3b8; }
table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: .95em; }
th, td { border: 1px solid #cbd5e1; padding: .45rem .75rem; text-align: left; }
th { background: #f1f5f9; font-weight: 600; }
tr:nth-child(even) { background: #f8fafc; }

/* ── Paginación PDF / impresión ──────────────────────────────────────────── */
@page {
  size: A4;
  margin: 18mm 20mm;
}
@media print {
  body {
    max-width: none;
    margin: 0;
    padding: 0;
    font-size: 11pt;
    color: #000;
  }
  a { color: #0369a1; text-decoration: underline; }
  pre {
    background: #f1f5f9;
    white-space: pre-wrap;
    word-break: break-word;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  h1, h2, h3, h4, h5, h6 {
    break-after: avoid;
    page-break-after: avoid;
  }
  table {
    break-inside: avoid;
    page-break-inside: avoid;
  }
  blockquote {
    break-inside: avoid;
    page-break-inside: avoid;
  }
  li { break-inside: avoid; page-break-inside: avoid; }
}
"""

# ── Patrones de bloque ────────────────────────────────────────────────────────

_FENCE_OPEN  = re.compile(r"^```([\w-]*)$")
_FENCE_CLOSE = re.compile(r"^```\s*$")
_HEADING     = re.compile(r"^(#{1,6})\s+(.*)")
_HR          = re.compile(r"^(?:-{3,}|\*{3,}|_{3,})\s*$")
_BLOCKQUOTE  = re.compile(r"^>\s?(.*)")
_UL          = re.compile(r"^(\s*)[-*+]\s+(.*)")
_OL          = re.compile(r"^(\s*)\d+\.\s+(.*)")
_TABLE_SEP   = re.compile(r"^\|[-:| ]+\|?\s*$")
_TABLE_ROW   = re.compile(r"^\|(.+)\|?\s*$")


# ── Helpers inline ────────────────────────────────────────────────────────────

def _inline(raw: str) -> str:
    """Convierte inline Markdown a HTML.

    Extrae primero los spans de código inline para protegerlos;
    escapa el texto plano con html.escape(); luego aplica los
    patrones de enlaces, imágenes, negrita, cursiva y tachado.
    """
    # 1. Proteger código inline `…` con placeholders
    codes: list[str] = []
    result: list[str] = []
    last = 0
    for m in re.finditer(r"`([^`]+)`", raw):
        result.append(html.escape(raw[last:m.start()], quote=False))
        codes.append(f"<code>{html.escape(m.group(1))}</code>")
        result.append(f"\x00CODE{len(codes) - 1}\x00")
        last = m.end()
    result.append(html.escape(raw[last:], quote=False))
    text = "".join(result)

    # 2. Imagen dentro de enlace: [![alt](src)](href)
    text = re.sub(
        r"\[!\[([^\]]*)\]\(([^)]*)\)\]\(([^)]*)\)",
        lambda m: (
            f'<a href="{m.group(3)}">'
            f'<img src="{m.group(2)}" alt="{m.group(1)}">'
            "</a>"
        ),
        text,
    )
    # 3. Imagen sola: ![alt](src)
    text = re.sub(
        r"!\[([^\]]*)\]\(([^)]*)\)",
        lambda m: f'<img src="{m.group(2)}" alt="{m.group(1)}">',
        text,
    )
    # 4. Enlace: [text](href)
    text = re.sub(
        r"\[([^\]]+)\]\(([^)]*)\)",
        lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>',
        text,
    )
    # 5. Negrita: **text** o __text__
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"__(.+?)__",     r"<strong>\1</strong>", text)
    # 6. Cursiva: *text*  (sin duplicar *)
    text = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)",       r"<em>\1</em>", text)
    # 7. Tachado: ~~text~~
    text = re.sub(r"~~(.+?)~~", r"<del>\1</del>", text)

    # 8. Restaurar códigos inline
    for idx, tag in enumerate(codes):
        text = text.replace(f"\x00CODE{idx}\x00", tag)

    return text


# ── Renderizado de bloques ────────────────────────────────────────────────────

def _render(text: str) -> str:
    """Convierte el cuerpo Markdown a HTML (elementos de bloque)."""
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    n = len(lines)
    list_stack: list[str] = []   # 'ul' | 'ol'

    def close_lists() -> None:
        while list_stack:
            out.append(f"</{list_stack.pop()}>")

    while i < n:
        line = lines[i]

        # ── Bloque de código fenced ──────────────────────────────────────────
        fm = _FENCE_OPEN.match(line)
        if fm:
            close_lists()
            lang = fm.group(1)
            code_lines: list[str] = []
            i += 1
            while i < n and not _FENCE_CLOSE.match(lines[i]):
                code_lines.append(lines[i])
                i += 1
            code = html.escape("\n".join(code_lines))
            cls = f' class="language-{lang}"' if lang else ""
            out.append(f"<pre><code{cls}>{code}</code></pre>")
            i += 1
            continue

        # ── Regla horizontal ─────────────────────────────────────────────────
        if _HR.match(line):
            close_lists()
            out.append("<hr>")
            i += 1
            continue

        # ── Heading ──────────────────────────────────────────────────────────
        hm = _HEADING.match(line)
        if hm:
            close_lists()
            level = len(hm.group(1))
            out.append(f"<h{level}>{_inline(hm.group(2).strip())}</h{level}>")
            i += 1
            continue

        # ── Tabla (encabezado | separador | filas) ───────────────────────────
        if _TABLE_ROW.match(line) and i + 1 < n and _TABLE_SEP.match(lines[i + 1]):
            close_lists()
            headers = [c.strip() for c in line.strip("|").split("|")]
            i += 2  # saltar separador
            header_html = "".join(f"<th>{_inline(h)}</th>" for h in headers)
            rows_html: list[str] = []
            while i < n and _TABLE_ROW.match(lines[i]):
                cols = [c.strip() for c in lines[i].strip("|").split("|")]
                # Rellenar columnas faltantes
                while len(cols) < len(headers):
                    cols.append("")
                rows_html.append(
                    "<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in cols) + "</tr>"
                )
                i += 1
            out.append(
                f"<table><thead><tr>{header_html}</tr></thead>"
                f"<tbody>{''.join(rows_html)}</tbody></table>"
            )
            continue

        # ── Blockquote ───────────────────────────────────────────────────────
        bm = _BLOCKQUOTE.match(line)
        if bm:
            close_lists()
            bq_lines = [bm.group(1)]
            i += 1
            while i < n and (bm2 := _BLOCKQUOTE.match(lines[i])):
                bq_lines.append(bm2.group(1))
                i += 1
            out.append(f"<blockquote>{_render(chr(10).join(bq_lines))}</blockquote>")
            continue

        # ── Lista desordenada ────────────────────────────────────────────────
        ulm = _UL.match(line)
        if ulm:
            if not list_stack or list_stack[-1] != "ul":
                close_lists()
                list_stack.append("ul")
                out.append("<ul>")
            out.append(f"<li>{_inline(ulm.group(2).strip())}</li>")
            i += 1
            continue

        # ── Lista ordenada ───────────────────────────────────────────────────
        olm = _OL.match(line)
        if olm:
            if not list_stack or list_stack[-1] != "ol":
                close_lists()
                list_stack.append("ol")
                out.append("<ol>")
            out.append(f"<li>{_inline(olm.group(2).strip())}</li>")
            i += 1
            continue

        # ── Línea en blanco ──────────────────────────────────────────────────
        if not line.strip():
            close_lists()
            i += 1
            continue

        # ── Párrafo ──────────────────────────────────────────────────────────
        close_lists()
        para_lines = [line]
        i += 1
        while (
            i < n
            and lines[i].strip()
            and not _HEADING.match(lines[i])
            and not _HR.match(lines[i])
            and not _FENCE_OPEN.match(lines[i])
            and not _BLOCKQUOTE.match(lines[i])
            and not _UL.match(lines[i])
            and not _OL.match(lines[i])
            and not (_TABLE_ROW.match(lines[i]) and i + 1 < n and _TABLE_SEP.match(lines[i + 1]))
        ):
            para_lines.append(lines[i])
            i += 1
        out.append(f"<p>{_inline(' '.join(para_lines))}</p>")

    close_lists()
    return "\n".join(out)


# ── API pública ───────────────────────────────────────────────────────────────

def markdown_to_html(content: str, *, title: str = "Document") -> str:
    """Convierte Markdown a HTML autocontenido con CSS embebido."""
    body = _render(content)
    safe_title = html.escape(title)
    return (
        '<!DOCTYPE html><html lang="es"><head>'
        '<meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        f"<title>{safe_title}</title>"
        f"<style>{_CSS}</style>"
        f"</head><body>{body}</body></html>"
    )
