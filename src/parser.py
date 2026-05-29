"""Segmentador de Markdown que preserva bloques de código y sintaxis."""

from __future__ import annotations

import re

import yaml

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
HASH_COMMENT_LANGS = frozenset({"python"})
SLASH_COMMENT_LANGS = frozenset({"javascript", "typescript", "js", "ts"})
HTML_COMMENT_LANGS = frozenset({"html", "xml"})
HASH_COMMENT = re.compile(r"^(\s*#\s?)(.*?)(\n?)$", re.DOTALL)
SLASH_COMMENT = re.compile(r"^(\s*//\s?)(.*?)(\n?)$", re.DOTALL)
HTML_COMMENT = re.compile(r"(^[\s]*)(<!--)(.*?)(-->)([\s]*)", re.DOTALL)
FM_TRANSLATABLE_KEYS = frozenset({
    "title",
    "description",
    "summary",
    "tags",
    "categories",
    "keywords",
})
FM_PROTECTED_KEYS = frozenset({"date", "slug", "id", "layout", "author"})


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


def _fence_lang(info: str) -> str | None:
    if not info.strip():
        return None
    return info.strip().lower().split()[0]


def _comment_kind(lang: str | None) -> str | None:
    if not lang:
        return None
    if lang in SHELL_LANGS or lang in HASH_COMMENT_LANGS:
        return "hash"
    if lang in SLASH_COMMENT_LANGS:
        return "slash"
    if lang in HTML_COMMENT_LANGS:
        return "html"
    return None


def _is_url(value: str) -> bool:
    stripped = value.strip()
    return stripped.startswith("http://") or stripped.startswith("https://")


def _append_hash_comment_line(
    segments: list[Segment],
    line: str,
    idx: int,
) -> int:
    if line.lstrip().startswith("#!"):
        return _append_segment(segments, SegmentKind.PROTECTED, line, idx)
    match = HASH_COMMENT.match(line)
    if match and match.group(2).strip():
        idx = _append_segment(segments, SegmentKind.PROTECTED, match.group(1), idx)
        comment_text = match.group(2)
        if match.group(3):
            comment_text += match.group(3)
        idx = _append_segment(segments, SegmentKind.TRANSLATABLE, comment_text, idx)
        return idx
    return _append_segment(segments, SegmentKind.PROTECTED, line, idx)


def _append_slash_comment_line(
    segments: list[Segment],
    line: str,
    idx: int,
) -> int:
    match = SLASH_COMMENT.match(line)
    if match and match.group(2).strip():
        idx = _append_segment(segments, SegmentKind.PROTECTED, match.group(1), idx)
        comment_text = match.group(2)
        if match.group(3):
            comment_text += match.group(3)
        idx = _append_segment(segments, SegmentKind.TRANSLATABLE, comment_text, idx)
        return idx
    return _append_segment(segments, SegmentKind.PROTECTED, line, idx)


def _append_html_comment_line(
    segments: list[Segment],
    line: str,
    idx: int,
) -> int:
    match = HTML_COMMENT.match(line)
    if match and match.group(3).strip():
        idx = _append_segment(segments, SegmentKind.PROTECTED, match.group(1) + match.group(2), idx)
        idx = _append_segment(segments, SegmentKind.TRANSLATABLE, match.group(3), idx)
        idx = _append_segment(
            segments,
            SegmentKind.PROTECTED,
            match.group(4) + match.group(5),
            idx,
        )
        return idx
    return _append_segment(segments, SegmentKind.PROTECTED, line, idx)


def _append_comment_line(
    segments: list[Segment],
    line: str,
    idx: int,
    kind: str,
) -> int:
    if kind == "hash":
        return _append_hash_comment_line(segments, line, idx)
    if kind == "slash":
        return _append_slash_comment_line(segments, line, idx)
    if kind == "html":
        return _append_html_comment_line(segments, line, idx)
    return _append_segment(segments, SegmentKind.PROTECTED, line, idx)


def _append_yaml_value(
    segments: list[Segment],
    key: str,
    value,
    idx: int,
) -> int:
    if key in FM_PROTECTED_KEYS or key not in FM_TRANSLATABLE_KEYS:
        line = yaml.dump({key: value}, default_flow_style=True, allow_unicode=True).strip()
        return _append_segment(segments, SegmentKind.PROTECTED, line + "\n", idx)

    if isinstance(value, str):
        if _is_url(value):
            line = yaml.dump({key: value}, default_flow_style=True, allow_unicode=True).strip()
            return _append_segment(segments, SegmentKind.PROTECTED, line + "\n", idx)
        idx = _append_segment(segments, SegmentKind.PROTECTED, f"{key}: ", idx)
        idx = _append_segment(segments, SegmentKind.TRANSLATABLE, value, idx)
        return _append_segment(segments, SegmentKind.PROTECTED, "\n", idx)

    if isinstance(value, list):
        idx = _append_segment(segments, SegmentKind.PROTECTED, f"{key}:\n", idx)
        for item in value:
            if isinstance(item, str) and not _is_url(item):
                idx = _append_segment(segments, SegmentKind.PROTECTED, "  - ", idx)
                idx = _append_segment(segments, SegmentKind.TRANSLATABLE, item, idx)
                idx = _append_segment(segments, SegmentKind.PROTECTED, "\n", idx)
            else:
                line = yaml.dump([item], default_flow_style=True, allow_unicode=True).strip()
                idx = _append_segment(segments, SegmentKind.PROTECTED, "  " + line + "\n", idx)
        return idx

    line = yaml.dump({key: value}, default_flow_style=True, allow_unicode=True).strip()
    return _append_segment(segments, SegmentKind.PROTECTED, line + "\n", idx)


def _segment_frontmatter(block: str, segments: list[Segment], idx: int) -> int:
    """Segmenta frontmatter YAML con whitelist selectiva."""
    lines = block.splitlines(keepends=True)
    if len(lines) < 2:
        return _append_segment(segments, SegmentKind.PROTECTED, block, idx)

    inner = "".join(lines[1:-1]) if len(lines) > 2 else ""
    try:
        data = yaml.safe_load(inner)
    except yaml.YAMLError:
        return _append_segment(segments, SegmentKind.PROTECTED, block, idx)

    if not isinstance(data, dict):
        return _append_segment(segments, SegmentKind.PROTECTED, block, idx)

    idx = _append_segment(segments, SegmentKind.PROTECTED, lines[0], idx)
    for key, value in data.items():
        idx = _append_yaml_value(segments, key, value, idx)
    idx = _append_segment(segments, SegmentKind.PROTECTED, lines[-1], idx)
    return idx


def segment_markdown(content: str) -> list[Segment]:
    """
    Divide el documento en segmentos protegidos y traducibles.

    Protegido: metadatos YAML técnicos, bloques ```/~~~ (salvo comentarios en
    shell/python/js/html), bloques HTML <pre>/<code>, código inline e indentados.
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
            idx = _segment_frontmatter(block, segments, idx)
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
            comment_kind = _comment_kind(_fence_lang(fence_info))

            idx = _append_segment(segments, SegmentKind.PROTECTED, line, idx)
            i += 1

            while i < len(lines):
                inner = lines[i]
                close = FENCE_PATTERN.match(inner.strip())
                if close and close.group(1)[0] == fence_char and len(close.group(1)) >= fence_len:
                    idx = _append_segment(segments, SegmentKind.PROTECTED, inner, idx)
                    i += 1
                    break
                if comment_kind:
                    idx = _append_comment_line(segments, inner, idx, comment_kind)
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
