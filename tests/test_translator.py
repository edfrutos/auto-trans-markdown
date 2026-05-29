"""Tests del traductor y helpers de idioma."""

from __future__ import annotations

import json
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from src.parser import collect_translatable, reassemble, segment_markdown
from src.translator import (
    IncompleteTranslationError,
    get_fallback_provider,
    get_provider_used,
    get_supported_language_codes,
    is_valid_source_lang,
    is_valid_target_lang,
    translate_segments,
)


class _MockDeepLResult:
    def __init__(self, text: str):
        self.text = text


def _mock_openai_client(translations: list[str]):
    client = MagicMock()
    payload = json.dumps({"translations": translations})
    message = SimpleNamespace(content=payload)
    choice = SimpleNamespace(message=message)
    response = SimpleNamespace(choices=[choice])
    client.chat.completions.create.return_value = response
    return client


def _mock_deepl_client(texts: list[str], *, short: bool = False):
    client = MagicMock()
    source = texts[:-1] if short else texts
    client.translate_text.return_value = [_MockDeepLResult(f"TR:{t}") for t in source]
    return client


def test_openai_incomplete_raises(monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "openai")

    def short_batch(texts, target_lang, source_lang, client=None, glossary_prompt=None, tone="auto"):
        return [f"TR:{texts[0]}"]

    monkeypatch.setattr("src.translator._translate_openai_batch", short_batch)
    items = [(0, "Hello"), (1, "World")]
    with pytest.raises(IncompleteTranslationError) as exc:
        translate_segments(items, "es", client=MagicMock())
    assert exc.value.expected == 2
    assert exc.value.received == 1
    assert 1 in exc.value.missing_indices


def test_deepl_batch_length_mismatch_raises():
    from src.translator import _translate_deepl_batch

    client = MagicMock()
    client.translate_text.return_value = []
    with pytest.raises(ValueError, match="DeepL devolvió"):
        _translate_deepl_batch(["Hello"], "es", None, client=client)


def test_validate_translation_completeness_raises():
    from src.translator import _validate_translation_completeness

    with pytest.raises(IncompleteTranslationError) as exc:
        _validate_translation_completeness([(0, "a"), (1, "b")], {0: "A"})
    assert exc.value.missing_indices == [1]


def test_complete_openai_returns_all_indices(monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "openai")
    items = [(0, "Hello"), (1, "World")]
    client = _mock_openai_client(["Hola", "Mundo"])
    result = translate_segments(items, "es", client=client)
    assert set(result.keys()) == {0, 1}
    assert result[0] == "Hola"
    assert result[1] == "Mundo"


def test_round_trip_segment_translate_reassemble(monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "openai")
    md = "# Hello\n\n```python\nx = 1\n```\n\nWorld\n"
    segments = segment_markdown(md)
    translatable = collect_translatable(segments)
    client = _mock_openai_client([f"TR:{text}" for _, text in translatable])
    translations = translate_segments(translatable, "es", client=client)
    out = reassemble(segments, translations)
    assert "```python" in out
    assert "x = 1" in out
    assert "TR:" in out
    assert "Hello" not in out or "TR:" in out


@pytest.mark.parametrize(
    ("provider", "code", "expected"),
    [
        ("openai", "ca", True),
        ("deepl", "ca", False),
        ("deepl", "es", True),
    ],
)
def test_get_supported_language_codes(monkeypatch, provider, code, expected):
    monkeypatch.setenv("TRANSLATION_PROVIDER", provider)
    codes = get_supported_language_codes(provider)
    assert (code in codes) is expected


def test_is_valid_source_lang_auto():
    assert is_valid_source_lang("auto", "openai") is True
    assert is_valid_source_lang("auto", "deepl") is True


def test_is_valid_source_lang_invalid():
    assert is_valid_source_lang("xx", "openai") is False


def test_is_valid_target_lang_deepl_excludes_ca(monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "deepl")
    assert is_valid_target_lang("ca", "deepl") is False
    assert is_valid_target_lang("es", "deepl") is True


def test_deepl_fallback_to_openai(monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "deepl")
    monkeypatch.setenv("TRANSLATION_FALLBACK", "openai")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")

    def fail_deepl(texts, target_lang, source_lang, client=None, tone="auto"):
        raise ValueError("DeepL no soporta el idioma destino 'catalán'.")

    openai_calls: list[list[str]] = []

    def ok_openai(texts, target_lang, source_lang, client=None, glossary_prompt=None, tone="auto"):
        openai_calls.append(texts)
        return [f"TR:{t}" for t in texts]

    monkeypatch.setattr("src.translator._translate_deepl_batch", fail_deepl)
    monkeypatch.setattr("src.translator._translate_openai_batch", ok_openai)

    result = translate_segments([(0, "Hello")], "ca", None)
    assert result[0] == "TR:Hello"
    assert get_provider_used() == "openai"
    assert openai_calls == [["Hello"]]


def test_deepl_no_fallback_without_env(monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "deepl")
    monkeypatch.delenv("TRANSLATION_FALLBACK", raising=False)

    def fail_deepl(texts, target_lang, source_lang, client=None, tone="auto"):
        raise ValueError("DeepL no soporta el idioma destino.")

    monkeypatch.setattr("src.translator._translate_deepl_batch", fail_deepl)

    with pytest.raises(ValueError, match="no soporta"):
        translate_segments([(0, "Hi")], "ca", None)


def test_get_fallback_provider_requires_openai_key(monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "deepl")
    monkeypatch.setenv("TRANSLATION_FALLBACK", "openai")
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    assert get_fallback_provider() is None


def test_tone_formal_in_openai_prompt(monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "openai")
    captured: list[str] = []

    def fake_batch(texts, target_lang, source_lang, client=None, glossary_prompt=None, tone="auto"):
        from src.translator import _build_user_prompt

        captured.append(_build_user_prompt(texts, target_lang, source_lang, glossary_prompt, tone))
        return [f"TR:{t}" for t in texts]

    monkeypatch.setattr("src.translator._translate_openai_batch", fake_batch)
    translate_segments([(0, "Hi")], "es", tone="formal", client=object())
    assert "formal" in captured[0].lower()


def test_deepl_formality_kwarg(monkeypatch):
    from src.translator import _translate_deepl_batch

    monkeypatch.setenv("TRANSLATION_PROVIDER", "deepl")
    client = MagicMock()
    client.translate_text.return_value = [_MockDeepLResult("Hola")]
    _translate_deepl_batch(["Hi"], "es", None, client=client, tone="formal")
    kwargs = client.translate_text.call_args.kwargs
    assert kwargs.get("formality") == "more"
