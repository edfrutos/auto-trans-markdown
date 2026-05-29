"""Traducción contextual de segmentos Markdown (OpenAI o DeepL)."""

from __future__ import annotations

import json
import logging
import os
import time
from typing import Callable, Protocol

from openai import APIError, OpenAI, RateLimitError

logger = logging.getLogger(__name__)

LANGUAGE_NAMES: dict[str, str] = {
    "es": "español",
    "en": "inglés",
    "fr": "francés",
    "de": "alemán",
    "it": "italiano",
    "pt": "portugués",
    "pt-BR": "portugués brasileño",
    "ca": "catalán",
    "gl": "gallego",
    "eu": "euskera",
    "nl": "neerlandés",
    "pl": "polaco",
    "ru": "ruso",
    "uk": "ucraniano",
    "ja": "japonés",
    "ko": "coreano",
    "zh": "chino simplificado",
    "zh-TW": "chino tradicional",
    "ar": "árabe",
    "hi": "hindi",
    "tr": "turco",
    "sv": "sueco",
    "da": "danés",
    "no": "noruego",
    "fi": "finlandés",
    "cs": "checo",
    "ro": "rumano",
    "hu": "húngaro",
    "el": "griego",
    "he": "hebreo",
    "id": "indonesio",
    "vi": "vietnamita",
    "th": "tailandés",
}

# Códigos destino DeepL (idiomas no listados → no disponibles en DeepL)
DEEPL_TARGET_MAP: dict[str, str] = {
    "es": "ES",
    "en": "EN-US",
    "fr": "FR",
    "de": "DE",
    "it": "IT",
    "pt": "PT-PT",
    "pt-BR": "PT-BR",
    "nl": "NL",
    "pl": "PL",
    "ru": "RU",
    "uk": "UK",
    "ja": "JA",
    "ko": "KO",
    "zh": "ZH-HANS",
    "zh-TW": "ZH-HANT",
    "ar": "AR",
    "tr": "TR",
    "sv": "SV",
    "da": "DA",
    "no": "NB",
    "fi": "FI",
    "cs": "CS",
    "ro": "RO",
    "hu": "HU",
    "el": "EL",
    "id": "ID",
}

DEEPL_SOURCE_MAP: dict[str, str] = {
    **{k: v.split("-")[0] for k, v in DEEPL_TARGET_MAP.items()},
    "pt-BR": "PT",
    "zh-TW": "ZH",
}

SYSTEM_PROMPT = """Eres un traductor profesional especializado en documentación técnica Markdown.

REGLAS ESTRICTAS:
1. Traduce SOLO el texto visible al lector final al idioma destino indicado.
2. PRESERVA exactamente toda la sintaxis Markdown: encabezados (#), listas (- * 1.), enlaces [texto](url), imágenes ![alt](url), negrita **, cursiva *, citas >, tablas |, HTML inline si existe.
3. NO traduzcas URLs, rutas de archivo, nombres de variables, comandos CLI, identificadores técnicos ni contenido dentro de backticks (ya excluido del input).
4. Adapta expresiones coloquiales e idiomáticas al registro natural del idioma destino (localización, no traducción literal palabra a palabra).
5. Mantén el tono del original: formal/informal, técnico/divulgativo.
6. Conserva espacios iniciales/finales y saltos de línea exactos de cada segmento.
7. Si un segmento es solo puntuación o espacios, devuélvelo igual.
8. Responde ÚNICAMENTE con un JSON válido: {"translations": ["texto1", "texto2", ...]} con el mismo número de elementos que recibes, en el mismo orden."""

BATCH_SIZE = 15
DEEPL_BATCH_SIZE = 40
MAX_BATCH_CHARS = 4000
MAX_RETRIES = 3
DEEPL_CONTEXT = (
    "Technical documentation written in Markdown. "
    "Preserve all Markdown syntax (# headers, lists, links, bold, tables). "
    "Translate only user-facing prose; keep URLs and code identifiers unchanged."
)


class ProgressCallback(Protocol):
    def __call__(self, done: int, total: int) -> None: ...


class IncompleteTranslationError(ValueError):
    """Traducción con menos segmentos de los solicitados."""

    def __init__(self, expected: int, received: int, missing_indices: list[int]):
        self.expected = expected
        self.received = received
        self.missing_indices = missing_indices
        super().__init__(
            f"Traducción incompleta: faltan {len(missing_indices)} de {expected} segmentos"
        )


def _language_label(code: str) -> str:
    return LANGUAGE_NAMES.get(code, code)


def get_provider() -> str:
    return os.getenv("TRANSLATION_PROVIDER", "openai").strip().lower()


def get_fallback_provider() -> str | None:
    """Proveedor secundario si el primario falla (p. ej. deepl → openai)."""
    if get_provider() != "deepl":
        return None
    fallback = os.getenv("TRANSLATION_FALLBACK", "").strip().lower()
    if fallback != "openai":
        return None
    if not os.getenv("OPENAI_API_KEY", "").strip():
        return None
    return "openai"


_provider_used: str | None = None


def get_provider_used() -> str:
    """Proveedor efectivo de la última llamada a translate_segments."""
    return _provider_used or get_provider()


def _openai_fallback_available() -> bool:
    return get_fallback_provider() == "openai"


def _deepl_error_fallbackable(exc: BaseException) -> bool:
    if isinstance(exc, ValueError):
        return True
    msg = str(exc).lower()
    markers = (
        "429",
        "456",
        "quota",
        "too many",
        "limit",
        "not support",
        "no soporta",
        "unsupported",
    )
    return any(m in msg for m in markers)


def get_supported_language_codes(provider: str | None = None) -> frozenset[str]:
    provider = (provider or get_provider()).lower()
    if provider == "deepl":
        return frozenset(DEEPL_TARGET_MAP.keys())
    return frozenset(LANGUAGE_NAMES.keys())


def get_supported_languages(provider: str | None = None) -> dict[str, str]:
    codes = get_supported_language_codes(provider)
    return {code: LANGUAGE_NAMES[code] for code in sorted(codes, key=lambda c: LANGUAGE_NAMES[c])}


def is_valid_target_lang(code: str, provider: str | None = None) -> bool:
    return code in get_supported_language_codes(provider)


def is_valid_source_lang(code: str, provider: str | None = None) -> bool:
    if code == "auto":
        return True
    provider = (provider or get_provider()).lower()
    if provider == "deepl":
        return code in DEEPL_SOURCE_MAP
    return code in LANGUAGE_NAMES


def _validate_translation_completeness(
    items: list[tuple[int, str]],
    result: dict[int, str],
) -> None:
    expected = {idx for idx, _ in items}
    received = set(result.keys())
    if expected != received:
        missing_indices = sorted(expected - received)
        raise IncompleteTranslationError(
            expected=len(expected),
            received=len(result),
            missing_indices=missing_indices,
        )


def _build_user_prompt(
    segments: list[str],
    target_lang: str,
    source_lang: str | None,
    glossary_prompt: str | None = None,
    tone: str = "auto",
) -> str:
    target = _language_label(target_lang)
    source_hint = (
        f"El idioma origen es {_language_label(source_lang)}."
        if source_lang and source_lang != "auto"
        else "Detecta el idioma origen automáticamente."
    )
    numbered = json.dumps(segments, ensure_ascii=False)
    parts = [
        source_hint,
        f"Idioma destino: {target}.",
    ]
    tone_hint = _tone_openai_hint(tone)
    if tone_hint:
        parts.append(tone_hint)
    if glossary_prompt:
        parts.append(glossary_prompt)
    parts.append(f"Traduce estos segmentos Markdown (array JSON):\n{numbered}")
    return "\n".join(parts)


def _tone_openai_hint(tone: str) -> str | None:
    if tone == "formal":
        return "Usa registro formal (usted, tono profesional y técnico)."
    if tone == "informal":
        return "Usa registro informal y cercano (tú, tono natural y conversacional)."
    return None


def _deepl_formality(tone: str) -> str | None:
    if tone == "formal":
        return "more"
    if tone == "informal":
        return "less"
    return None


def _parse_openai_response(raw: str, expected_count: int) -> list[str]:
    text = raw.strip()
    if text.startswith("```"):
        lines = text.split("\n")
        text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
    data = json.loads(text)
    translations = data.get("translations", data)
    if not isinstance(translations, list):
        raise ValueError("La respuesta no contiene un array 'translations'")
    if len(translations) != expected_count:
        raise ValueError(
            f"Se esperaban {expected_count} traducciones, recibidas {len(translations)}"
        )
    return [str(t) for t in translations]


def create_openai_client() -> OpenAI:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError(
            "OPENAI_API_KEY no configurada. Usa TRANSLATION_PROVIDER=deepl "
            "con DEEPL_API_KEY, o añade OPENAI_API_KEY en .env"
        )
    return OpenAI(
        api_key=api_key,
        base_url=os.getenv("OPENAI_BASE_URL") or None,
    )


def create_deepl_client():
    try:
        import deepl
    except ImportError as e:
        raise RuntimeError(
            "Paquete 'deepl' no instalado. Ejecuta: pip install deepl"
        ) from e

    api_key = os.getenv("DEEPL_API_KEY")
    if not api_key:
        raise RuntimeError(
            "DEEPL_API_KEY no configurada. Obtén una en https://www.deepl.com/pro-api"
        )
    server_url = os.getenv("DEEPL_API_URL") or None
    return deepl.Translator(api_key, server_url=server_url)


def _deepl_target(code: str) -> str:
    target = DEEPL_TARGET_MAP.get(code)
    if not target:
        raise ValueError(
            f"DeepL no soporta el idioma destino '{_language_label(code)}'. "
            f"Usa TRANSLATION_PROVIDER=openai o elige otro idioma."
        )
    return target


def _deepl_source(code: str | None) -> str | None:
    if not code or code == "auto":
        return None
    source = DEEPL_SOURCE_MAP.get(code)
    if not source:
        raise ValueError(
            f"DeepL no soporta el idioma origen '{_language_label(code)}'."
        )
    return source


def _chunk_items(
    items: list[tuple[int, str]],
    max_items: int,
    max_chars: int,
) -> list[list[tuple[int, str]]]:
    """Agrupa segmentos limitando cantidad y tamaño total del lote."""
    chunks: list[list[tuple[int, str]]] = []
    current: list[tuple[int, str]] = []
    current_chars = 0

    for item in items:
        _, text = item
        if current and (
            len(current) >= max_items
            or current_chars + len(text) > max_chars
        ):
            chunks.append(current)
            current = []
            current_chars = 0
        current.append(item)
        current_chars += len(text)

    if current:
        chunks.append(current)
    return chunks


def _translate_openai_batch(
    texts: list[str],
    target_lang: str,
    source_lang: str | None,
    client: OpenAI | None = None,
    glossary_prompt: str | None = None,
    tone: str = "auto",
) -> list[str]:
    client = client or create_openai_client()
    model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

    for attempt in range(MAX_RETRIES):
        try:
            response = client.chat.completions.create(
                model=model,
                temperature=0.3,
                response_format={"type": "json_object"},
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": _build_user_prompt(
                            texts, target_lang, source_lang, glossary_prompt, tone
                        ),
                    },
                ],
            )
            raw = response.choices[0].message.content or ""
            return _parse_openai_response(raw, len(texts))
        except RateLimitError:
            if attempt == MAX_RETRIES - 1:
                raise
            wait = 2 ** (attempt + 1)
            logger.warning("Rate limit OpenAI, reintento en %ss", wait)
            time.sleep(wait)
        except (ValueError, json.JSONDecodeError) as exc:
            if len(texts) <= 1:
                raise ValueError(
                    f"Respuesta inválida del modelo para un segmento: {exc}"
                ) from exc
            mid = len(texts) // 2
            logger.warning(
                "Lote OpenAI incompleto (%d segmentos), dividiendo en %d + %d",
                len(texts),
                mid,
                len(texts) - mid,
            )
            left = _translate_openai_batch(
                texts[:mid], target_lang, source_lang, client, glossary_prompt, tone
            )
            right = _translate_openai_batch(
                texts[mid:], target_lang, source_lang, client, glossary_prompt, tone
            )
            return left + right
        except APIError as exc:
            if attempt == MAX_RETRIES - 1 or exc.status_code not in {429, 500, 502, 503}:
                raise
            wait = 2 ** (attempt + 1)
            logger.warning("Error API OpenAI %s, reintento en %ss", exc.status_code, wait)
            time.sleep(wait)

    raise RuntimeError("No se pudo completar la traducción tras varios intentos")


def _translate_deepl_batch(
    texts: list[str],
    target_lang: str,
    source_lang: str | None,
    client=None,
    tone: str = "auto",
) -> list[str]:
    client = client or create_deepl_client()
    target = _deepl_target(target_lang)
    source = _deepl_source(source_lang)

    kwargs: dict = {
        "target_lang": target,
        "preserve_formatting": True,
        "context": DEEPL_CONTEXT,
    }
    if source:
        kwargs["source_lang"] = source
    formality = _deepl_formality(tone)
    if formality:
        kwargs["formality"] = formality

    for attempt in range(MAX_RETRIES):
        try:
            results = client.translate_text(texts, **kwargs)
            if isinstance(results, list):
                translated = [r.text for r in results]
            else:
                translated = [results.text]
            if len(translated) != len(texts):
                raise ValueError(
                    f"DeepL devolvió {len(translated)} traducciones, se esperaban {len(texts)}"
                )
            return translated
        except Exception as exc:
            msg = str(exc).lower()
            if "429" in msg or "too many" in msg or "456" in msg:
                if attempt == MAX_RETRIES - 1:
                    raise
                wait = 2 ** (attempt + 1)
                logger.warning("Rate limit DeepL, reintento en %ss", wait)
                time.sleep(wait)
                continue
            if len(texts) <= 1:
                raise
            mid = len(texts) // 2
            logger.warning("Lote DeepL fallido, dividiendo en %d + %d", mid, len(texts) - mid)
            left = _translate_deepl_batch(
                texts[:mid], target_lang, source_lang, client, tone
            )
            right = _translate_deepl_batch(
                texts[mid:], target_lang, source_lang, client, tone
            )
            return left + right

    raise RuntimeError("No se pudo completar la traducción DeepL")


def _translate_batch_with_fallback(
    texts: list[str],
    target_lang: str,
    source_lang: str | None,
    *,
    client=None,
    glossary_prompt: str | None = None,
    tone: str = "auto",
) -> list[str]:
    """DeepL con fallback opcional a OpenAI."""
    global _provider_used
    try:
        _provider_used = "deepl"
        return _translate_deepl_batch(
            texts, target_lang, source_lang, client=client, tone=tone
        )
    except Exception as exc:
        if not _openai_fallback_available() or not _deepl_error_fallbackable(exc):
            raise
        logger.warning(
            "DeepL falló (%s); reintentando con OpenAI (TRANSLATION_FALLBACK)",
            exc,
        )
        _provider_used = "openai"
        return _translate_openai_batch(
            texts,
            target_lang,
            source_lang,
            client=client,
            glossary_prompt=glossary_prompt,
            tone=tone,
        )


def translate_segments(
    items: list[tuple[int, str]],
    target_lang: str,
    source_lang: str | None = None,
    *,
    on_progress: Callable[[int, int], None] | None = None,
    glossary_prompt: str | None = None,
    tone: str = "auto",
    client=None,
) -> dict[int, str]:
    """Traduce segmentos en lotes y devuelve mapa index -> texto traducido."""
    global _provider_used
    if not items:
        return {}

    provider = get_provider()
    _provider_used = provider
    if provider == "deepl":
        max_items, max_chars = DEEPL_BATCH_SIZE, MAX_BATCH_CHARS
    else:
        max_items, max_chars = BATCH_SIZE, MAX_BATCH_CHARS

    result: dict[int, str] = {}
    total = len(items)
    chunks = _chunk_items(items, max_items, max_chars)

    for chunk in chunks:
        texts = [text for _, text in chunk]
        indices = [idx for idx, _ in chunk]

        if provider == "deepl":
            translations = _translate_batch_with_fallback(
                texts,
                target_lang,
                source_lang,
                client=client,
                glossary_prompt=glossary_prompt,
                tone=tone,
            )
        elif provider == "openai":
            translations = _translate_openai_batch(
                texts,
                target_lang,
                source_lang,
                client=client,
                glossary_prompt=glossary_prompt,
                tone=tone,
            )
        else:
            raise RuntimeError(
                f"TRANSLATION_PROVIDER desconocido: '{provider}'. "
                "Usa 'openai' o 'deepl'."
            )

        for idx, translated in zip(indices, translations):
            result[idx] = translated

        if on_progress:
            on_progress(len(result), total)

    _validate_translation_completeness(items, result)
    return result
