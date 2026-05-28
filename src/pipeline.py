"""Fachada unificada: segmentar → TM → glosario → traducir → reensamblar."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .glossary import (
    Glossary,
    GlossaryPreState,
    apply_post,
    apply_pre,
    build_prompt_appendix,
    load_glossary,
)
from .memory import TranslationMemory, default_memory_path
from .parser import collect_translatable, reassemble, segment_markdown
from .translator import (
    ProgressCallback,
    get_provider,
    is_valid_source_lang,
    is_valid_target_lang,
    translate_segments,
)

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_GLOSSARY_PATH = ROOT / "glossary.yaml"


@dataclass
class TranslateOptions:
    target_lang: str
    source_lang: str | None = None
    dry_run: bool = False
    use_memory: bool = True
    use_glossary: bool = True
    glossary_path: Path | None = None
    memory_path: Path | None = None
    on_progress: ProgressCallback | None = None


@dataclass
class TranslateResult:
    content: str
    segments_total: int
    segments_translated: int
    cache_hits: int = 0
    cache_misses: int = 0
    dry_run_segments: list[tuple[int, str]] | None = None


def _resolve_source(source_lang: str | None) -> str | None:
    if not source_lang or source_lang == "auto":
        return None
    return source_lang


def _validate_languages(target_lang: str, source_lang: str | None) -> None:
    if not is_valid_target_lang(target_lang):
        raise ValueError(
            f"Idioma destino no soportado por el proveedor activo: {target_lang}"
        )
    if source_lang and source_lang != "auto" and not is_valid_source_lang(source_lang):
        raise ValueError(
            f"Idioma origen no soportado por el proveedor activo: {source_lang}"
        )


def _source_text_by_index(
    translatable: list[tuple[int, str]],
) -> dict[int, str]:
    return dict(translatable)


def translate_markdown(content: str, options: TranslateOptions) -> TranslateResult:
    """Orquesta parseo, memoria, glosario y traducción en un solo flujo."""
    _validate_languages(options.target_lang, options.source_lang)
    source = _resolve_source(options.source_lang)

    segments = segment_markdown(content)
    translatable = collect_translatable(segments)
    total = len(segments)
    count = len(translatable)
    originals = _source_text_by_index(translatable)

    if options.dry_run:
        return TranslateResult(
            content="",
            segments_total=total,
            segments_translated=count,
            dry_run_segments=translatable,
        )

    hits: dict[int, str] = {}
    misses: list[tuple[int, str]] = list(translatable)
    miss_count = len(misses)

    if options.use_memory and translatable:
        tm = TranslationMemory(options.memory_path or default_memory_path())
        hits, misses = tm.lookup(translatable, source, options.target_lang)
        miss_count = len(misses)

    glossary: Glossary | None = None
    glossary_appendix = ""
    provider = get_provider()
    pre_states: dict[int, GlossaryPreState | None] = {}
    rules = None

    if options.use_glossary and misses:
        glossary = load_glossary(options.glossary_path or DEFAULT_GLOSSARY_PATH)
        rules = glossary.get_rules(source, options.target_lang)
        if rules.has_rules:
            processed_misses: list[tuple[int, str]] = []
            for idx, text in misses:
                new_text, state = apply_pre(text, rules, provider)
                pre_states[idx] = state
                processed_misses.append((idx, new_text))
            misses = processed_misses
            if provider == "openai":
                glossary_appendix = build_prompt_appendix(rules)

    new_translations: dict[int, str] = {}
    if misses:
        new_translations = translate_segments(
            misses,
            options.target_lang,
            source,
            on_progress=options.on_progress,
            glossary_prompt=glossary_appendix or None,
        )
        if options.use_glossary and rules and rules.has_rules:
            for idx, translated in list(new_translations.items()):
                state = pre_states.get(idx)
                new_translations[idx] = apply_post(translated, state, rules)

    translations = {**hits, **new_translations}

    if options.use_memory and new_translations:
        tm = TranslationMemory(options.memory_path or default_memory_path())
        store_entries = [
            (idx, originals[idx], new_translations[idx])
            for idx in new_translations
            if idx in originals
        ]
        tm.store_batch(store_entries, source, options.target_lang)

    output = reassemble(segments, translations)
    return TranslateResult(
        content=output,
        segments_total=total,
        segments_translated=count,
        cache_hits=len(hits),
        cache_misses=miss_count,
    )
