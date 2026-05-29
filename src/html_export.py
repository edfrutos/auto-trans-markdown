"""Export Markdown a HTML autocontenido."""

from __future__ import annotations

import html
import re

_HEADING = re.compile(r"^(#{1,6})\s+(.+)$", re.MULTILINE)
_BOLD = re.compile(r"\*\*(.+?)\*\*")
_CODE_FENCE = re.compile(r"```[\w]*\n(.*?)```", re.DOTALL)
_INLINE_CODE = re.compile(r"`([^`]+)`")

_EMBEDDED_CSS = """
body { font-family: system-ui, sans-serif; line-height: 1.6; max-width: 48rem; margin: 2rem auto; padding: 0 1rem; color: #1e293b; }
h1,h2,h3 { color: #0f766e; margin-top: 1.5em; }
pre { background: #f1f5f9; padding: 1rem; overflow-x: auto; border-radius: 0.5rem; }
code { background: #f1f5f9; padding: 0.1em 0.35em; border-radius: 0.25rem; font-size: 0.9em; }
blockquote { border-left: 4px solid #14b8a6; margin-left: 0; padding-left: 1rem; color: #475569; }
"""


def _escape_inline(text: str) -> str:
    text = html.escape(text)
    text = _INLINE_CODE.sub(r"<code>\1</code>", text)
    text = _BOLD.sub(r"<strong>\1</strong>", text)
    return text


def markdown_to_html(content: str, *, title: str = "Document") -> str:
    """Convierte Markdown básico a HTML con CSS embebido."""
    body_parts: list[str] = []
    last = 0
    for match in _CODE_FENCE.finditer(content):
        before = content[last : match.start()]
        body_parts.append(_render_block(before))
        code = html.escape(match.group(1).rstrip("\n"))
        body_parts.append(f"<pre><code>{code}</code></pre>")
        last = match.end()
    body_parts.append(_render_block(content[last:]))
    body = "\n".join(p for p in body_parts if p)
    safe_title = html.escape(title)
    return (
        f"<!DOCTYPE html><html lang=\"es\"><head>"
        f"<meta charset=\"utf-8\">"
        f"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        f"<title>{safe_title}</title>"
        f"<style>{_EMBEDDED_CSS}</style></head><body>{body}</body></html>"
    )


def _render_block(text: str) -> str:
    if not text.strip():
        return ""
    lines: list[str] = []
    para: list[str] = []
    for line in text.splitlines():
        hm = _HEADING.match(line)
        if hm:
            if para:
                lines.append(f"<p>{_escape_inline(' '.join(para))}</p>")
                para = []
            level = len(hm.group(1))
            lines.append(f"<h{level}>{_escape_inline(hm.group(2))}</h{level}>")
        elif line.startswith("> "):
            if para:
                lines.append(f"<p>{_escape_inline(' '.join(para))}</p>")
                para = []
            lines.append(f"<blockquote><p>{_escape_inline(line[2:])}</p></blockquote>")
        elif not line.strip():
            if para:
                lines.append(f"<p>{_escape_inline(' '.join(para))}</p>")
                para = []
        else:
            para.append(line.strip())
    if para:
        lines.append(f"<p>{_escape_inline(' '.join(para))}</p>")
    return "\n".join(lines)
