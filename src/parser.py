"""Segmentador de Markdown que preserva bloques de código y sintaxis."""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum


class SegmentKind(str, Enum):
    PROTECTED = "protected"
    TRANSLATABLE = "translatable"


@dataclass
class Segment:
    kind: SegmentKind
    text: str
    index: int


FENCE_PATTERN = re.compile(r"^(```+|~~~+)(.*)$")
FRONTMATTER_DELIM = re.compile(r"^---\s*$")
SHELL_LANGS = frozenset({"bash", "sh", "shell", "zsh", "fish"})
SHELL_COMMENT = re.compile(r"^(\s*#\s?)(.*?)(\n?)$", re.DOTALL)


def _split_inline_code(line: str) -> list[tuple[SegmentKind, str]]:
    """Divide una línea preservando spans de código inline."""
    parts: list[tuple[SegmentKind, str]] = []
    i = 0
    while i < len(line):
        if line[i] == "`":
            end = i + 1
            while end < len(line) and line[end] == "`":
                end += 1
            tick_count = end - i
            close = line.find("`" * tick_count, end)
            if close == -1:
                parts.append((SegmentKind.TRANSLATABLE, line[i:]))
                break
            parts.append((SegmentKind.PROTECTED, line[i : close + tick_count]))
            i = close + tick_count
        else:
            next_tick = line.find("`", i)
            if next_tick == -1:
                parts.append((SegmentKind.TRANSLATABLE, line[i:]))
                break
            parts.append((SegmentKind.TRANSLATABLE, line[i:next_tick]))
            i = next_tick
    return parts


def _append_segment(
    segments: list[Segment],
    kind: SegmentKind,
    text: str,
    idx: int,
) -> int:
    if not text:
        return idx
    segments.append(Segment(kind, text, idx))
    return idx + 1


def _append_inline_line(
    segments: list[Segment],
    line: str,
    idx: int,
) -> int:
    inline_parts = _split_inline_code(line)
    for kind, part in inline_parts:
        idx = _append_segment(segments, kind, part, idx)
    return idx


def _is_shell_fence(info: str) -> bool:
    lang = info.strip().lower().split()[0] if info.strip() else ""
    return lang in SHELL_LANGS


def _append_shell_line(
    segments: list[Segment],
    line: str,
    idx: int,
) -> int:
    """Traduce comentarios # en bloques shell; preserva comandos."""
    match = SHELL_COMMENT.match(line)
    if match and match.group(2).strip():
        idx = _append_segment(segments, SegmentKind.PROTECTED, match.group(1), idx)
        comment_text = match.group(2)
        if match.group(3):
            comment_text += match.group(3)
        idx = _append_segment(segments, SegmentKind.TRANSLATABLE, comment_text, idx)
        return idx
    return _append_segment(segments, SegmentKind.PROTECTED, line, idx)


def segment_markdown(content: str) -> list[Segment]:
    """
    Divide el documento en segmentos protegidos y traducibles.

    Protegido: frontmatter YAML, bloques ```/~~~ (salvo comentarios # en shell),
    bloques HTML <pre>/<code>, código inline y bloques indentados.
    """
    lines = content.splitlines(keepends=True)
    segments: list[Segment] = []
    idx = 0

    frontmatter_checked = False
    in_html_pre = False

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.lstrip()

        if not frontmatter_checked and i == 0 and FRONTMATTER_DELIM.match(line.strip()):
            frontmatter_checked = True
            block = line
            i += 1
            while i < len(lines):
                block += lines[i]
                if FRONTMATTER_DELIM.match(lines[i].strip()):
                    i += 1
                    break
                i += 1
            idx = _append_segment(segments, SegmentKind.PROTECTED, block, idx)
            continue

        frontmatter_checked = True

        lower = stripped.lower()
        if "<pre" in lower or "<code" in lower:
            in_html_pre = True
        if in_html_pre:
            block = line
            i += 1
            while i < len(lines):
                block += lines[i]
                l2 = lines[i].lower()
                if "</pre>" in l2 or "</code>" in l2:
                    in_html_pre = False
                    i += 1
                    break
                i += 1
            idx = _append_segment(segments, SegmentKind.PROTECTED, block, idx)
            continue

        fence_match = FENCE_PATTERN.match(line.strip())
        if fence_match:
            fence_char = fence_match.group(1)[0]
            fence_len = len(fence_match.group(1))
            fence_info = fence_match.group(2)
            is_shell = _is_shell_fence(fence_info)

            idx = _append_segment(segments, SegmentKind.PROTECTED, line, idx)
            i += 1

            while i < len(lines):
                inner = lines[i]
                close = FENCE_PATTERN.match(inner.strip())
                if close and close.group(1)[0] == fence_char and len(close.group(1)) >= fence_len:
                    idx = _append_segment(segments, SegmentKind.PROTECTED, inner, idx)
                    i += 1
                    break
                if is_shell:
                    idx = _append_shell_line(segments, inner, idx)
                else:
                    idx = _append_segment(segments, SegmentKind.PROTECTED, inner, idx)
                i += 1
            continue

        if (line.startswith("    ") or line.startswith("\t")) and not re.match(
            r"^[\s]*[-*+]\s", line
        ):
            block = line
            i += 1
            while i < len(lines) and (
                lines[i].startswith("    ")
                or lines[i].startswith("\t")
                or (
                    lines[i].strip() == ""
                    and i + 1 < len(lines)
                    and (
                        lines[i + 1].startswith("    ")
                        or lines[i + 1].startswith("\t")
                    )
                )
            ):
                block += lines[i]
                i += 1
            idx = _append_segment(segments, SegmentKind.PROTECTED, block, idx)
            continue

        idx = _append_inline_line(segments, line, idx)
        i += 1

    return segments


def _merge_translation(original: str, translated: str) -> str:
    """Conserva espacios/saltos de línea del segmento original."""
    if not translated:
        return original
    lead = original[: len(original) - len(original.lstrip())]
    trail = original[len(original.rstrip()) :]
    core = translated.strip()
    return f"{lead}{core}{trail}"


def reassemble(segments: list[Segment], translations: dict[int, str]) -> str:
    """Reconstruye el documento aplicando traducciones por índice."""
    out: list[str] = []
    for seg in segments:
        if seg.kind == SegmentKind.PROTECTED:
            out.append(seg.text)
        elif seg.index in translations:
            out.append(_merge_translation(seg.text, translations[seg.index]))
        else:
            out.append(seg.text)
    return "".join(out)


def collect_translatable(segments: list[Segment]) -> list[tuple[int, str]]:
    """Devuelve pares (index, text) solo para segmentos con texto traducible."""
    result: list[tuple[int, str]] = []
    for seg in segments:
        if seg.kind == SegmentKind.TRANSLATABLE and seg.text.strip():
            result.append((seg.index, seg.text))
    return result
