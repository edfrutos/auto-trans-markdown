"""Modo revisión: borrador segmentado y reensamblado."""

from __future__ import annotations

import re
from dataclasses import dataclass

from .parser import collect_translatable, reassemble, segment_markdown
from .pipeline import TranslateOptions, TranslateResult, translate_markdown
from .validator import ValidationReport, validate_translation

_ALPHA = re.compile(r"[A-Za-zÁ-Úá-ú]")


@dataclass
class DraftSegment:
    index: int
    original: str
    translated: str
    doubtful: bool


@dataclass
class DraftResult:
    content: str
    segments: list[DraftSegment]
    segments_total: int
    segments_translated: int
    validation: ValidationReport | None
    provider_used: str | None = None


def score_doubtful(
    original: str,
    translated: str,
    *,
    doc_validation: ValidationReport | None = None,
) -> bool:
    """Heurística para marcar segmentos que conviene revisar."""
    alpha_count = len(_ALPHA.findall(original))
    if alpha_count > 20 and original.strip() == translated.strip():
        return True
    if original.strip():
        ratio = len(translated) / max(len(original), 1)
        if ratio < 0.3 or ratio > 3.0:
            return True
    if doc_validation and doc_validation.overall in ("error", "warning"):
        if original.strip() and len(translated.strip()) < max(3, len(original.strip()) // 4):
            return True
    return False


def build_draft(content: str, options: TranslateOptions) -> DraftResult:
    """Traduce y devuelve segmentos editables con flags doubtful."""
    result = translate_markdown(content, options)
    translatable = collect_translatable(segment_markdown(content))
    translations = result.segment_translations or {}
    segments: list[DraftSegment] = []
    for idx, original in translatable:
        translated = translations.get(idx, original)
        segments.append(
            DraftSegment(
                index=idx,
                original=original,
                translated=translated,
                doubtful=score_doubtful(
                    original,
                    translated,
                    doc_validation=result.validation,
                ),
            )
        )
    return DraftResult(
        content=result.content,
        segments=segments,
        segments_total=result.segments_total,
        segments_translated=result.segments_translated,
        validation=result.validation,
        provider_used=result.provider_used,
    )


def finalize_draft(content: str, edits: dict[int, str]) -> TranslateResult:
    """Reensambla Markdown con traducciones editadas por el usuario."""
    segments = segment_markdown(content)
    translatable = collect_translatable(segments)
    translations = {idx: text for idx, text in translatable}
    translations.update(edits)
    output = reassemble(segments, translations)
    validation = validate_translation(content, output)
    return TranslateResult(
        content=output,
        segments_total=len(segments),
        segments_translated=len(translatable),
        validation=validation,
        segment_translations=translations,
    )
