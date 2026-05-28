"""Tests del traductor y helpers de idioma."""

from __future__ import annotations

import json
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from src.parser import collect_translatable, reassemble, segment_markdown
from src.translator import (
    IncompleteTranslationError,
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

    def short_batch(texts, target_lang, source_lang, client=None):
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
