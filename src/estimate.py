"""Estimación de coste pre-traducción sin llamar al proveedor."""

from __future__ import annotations

import os
from dataclasses import dataclass

from .memory import TranslationMemory, default_memory_path
from .parser import collect_translatable, segment_markdown
from .translator import get_provider

# Tarifas aproximadas (actualizables) — OpenAI input gpt-4o-mini; DeepL ~$20/M chars
OPENAI_INPUT_USD_PER_1M = 0.15
DEEPL_USD_PER_MILLION_CHARS = 20.0


@dataclass
class EstimateResult:
    segments: int
    characters: int
    estimated_cost_usd: float
    provider: str
    model: str
    exceeds_threshold: bool
    threshold_usd: float
    language_count: int = 1


def _threshold_usd() -> float:
    raw = os.getenv("ESTIMATE_WARN_USD", "1.0")
    try:
        return float(raw)
    except ValueError:
        return 1.0


def _resolve_source(source_lang: str | None) -> str | None:
    if not source_lang or source_lang == "auto":
        return None
    return source_lang


def _billable_segments(
    content: str,
    *,
    target_lang: str,
    source_lang: str | None,
    use_memory: bool,
    memory_path=None,
) -> list[tuple[int, str]]:
    translatable = collect_translatable(segment_markdown(content))
    if not translatable:
        return []
    if not use_memory:
        return translatable
    source = _resolve_source(source_lang)
    tm = TranslationMemory(memory_path or default_memory_path())
    _hits, misses = tm.lookup(translatable, source, target_lang)
    return misses


def _compute_cost(characters: int, provider: str) -> tuple[float, str]:
    if provider == "deepl":
        cost = characters / 1_000_000 * DEEPL_USD_PER_MILLION_CHARS
        return cost, "deepl"
    model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    # Aproximación tokens ≈ chars/4 para input
    cost = (characters / 4) / 1_000_000 * OPENAI_INPUT_USD_PER_1M
    return cost, model


def estimate_markdown(
    content: str,
    *,
    target_lang: str,
    source_lang: str | None = None,
    use_memory: bool = True,
    memory_path=None,
) -> EstimateResult:
    """Cuenta segmentos traducibles y estima coste sin llamar al proveedor."""
    billable = _billable_segments(
        content,
        target_lang=target_lang,
        source_lang=source_lang,
        use_memory=use_memory,
        memory_path=memory_path,
    )
    characters = sum(len(text) for _, text in billable)
    segments = len(billable)
    provider = get_provider()
    estimated_cost_usd, model = _compute_cost(characters, provider)
    threshold = _threshold_usd()
    return EstimateResult(
        segments=segments,
        characters=characters,
        estimated_cost_usd=estimated_cost_usd,
        provider=provider,
        model=model,
        exceeds_threshold=estimated_cost_usd > threshold,
        threshold_usd=threshold,
    )


def estimate_for_langs(
    contents: list[str],
    *,
    target_langs: list[str],
    source_lang: str | None = None,
    use_memory: bool = True,
    memory_path=None,
) -> EstimateResult:
    """Agrega estimación para varios archivos × varios idiomas destino."""
    total_segments = 0
    total_chars = 0
    total_cost = 0.0
    provider = get_provider()
    model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    if provider == "deepl":
        model = "deepl"

    for lang in target_langs:
        for content in contents:
            result = estimate_markdown(
                content,
                target_lang=lang,
                source_lang=source_lang,
                use_memory=use_memory,
                memory_path=memory_path,
            )
            total_segments += result.segments
            total_chars += result.characters
            total_cost += result.estimated_cost_usd
            provider = result.provider
            model = result.model

    threshold = _threshold_usd()
    return EstimateResult(
        segments=total_segments,
        characters=total_chars,
        estimated_cost_usd=total_cost,
        provider=provider,
        model=model,
        exceeds_threshold=total_cost > threshold,
        threshold_usd=threshold,
        language_count=len(target_langs),
    )


def estimate_files(
    contents: list[str],
    *,
    target_lang: str,
    target_langs: list[str] | None = None,
    source_lang: str | None = None,
    use_memory: bool = True,
    memory_path=None,
) -> EstimateResult:
    """Agrega estimación de varios archivos Markdown."""
    langs = target_langs if target_langs else [target_lang]
    return estimate_for_langs(
        contents,
        target_langs=langs,
        source_lang=source_lang,
        use_memory=use_memory,
        memory_path=memory_path,
    )
