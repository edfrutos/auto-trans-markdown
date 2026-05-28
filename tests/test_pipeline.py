"""Tests de la fachada translate_markdown."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock

import pytest

from src.pipeline import TranslateOptions, translate_markdown
from src.translator import IncompleteTranslationError


def test_translate_markdown_success(mock_translate_segments):
    md = "# Hello\n\nWorld\n"
    result = translate_markdown(
        md, TranslateOptions(target_lang="es", source_lang=None)
    )
    assert "TR:" in result.content
    assert result.segments_translated >= 1
    assert result.segments_translated >= 1
    mock_translate_segments.assert_called()


def test_translate_markdown_dry_run(mock_translate_segments):
    md = "# Hello\n"
    result = translate_markdown(
        md,
        TranslateOptions(target_lang="es", dry_run=True),
    )
    assert result.content == ""
    assert result.dry_run_segments is not None
    assert len(result.dry_run_segments) >= 1
    mock_translate_segments.assert_not_called()


def test_translate_markdown_invalid_target():
    with pytest.raises(ValueError, match="destino"):
        translate_markdown("# Hi", TranslateOptions(target_lang="invalid"))


def test_translate_markdown_incomplete_propagates(mock_translate_segments):
    mock_translate_segments.side_effect = IncompleteTranslationError(
        expected=2, received=1, missing_indices=[1]
    )
    with pytest.raises(IncompleteTranslationError):
        translate_markdown("# A\n\nB\n", TranslateOptions(target_lang="es"))


def test_translate_markdown_cache_hit(tmp_path, monkeypatch):
    db = tmp_path / "tm.db"
    md = "# Repeat\n"
    opts = TranslateOptions(
        target_lang="es",
        source_lang=None,
        use_glossary=False,
        memory_path=db,
    )

    calls = {"n": 0}

    def _translate(items, target_lang, source_lang=None, **kwargs):
        calls["n"] += 1
        return {idx: f"TR:{text}" for idx, text in items}

    monkeypatch.setattr("src.pipeline.translate_segments", _translate)

    translate_markdown(md, opts)
    result2 = translate_markdown(md, opts)
    assert calls["n"] == 1
    assert result2.cache_hits >= 1


def test_translate_markdown_use_memory_false(tmp_path, monkeypatch):
    db = tmp_path / "tm.db"
    calls = {"n": 0}

    def _translate(items, target_lang, source_lang=None, **kwargs):
        calls["n"] += 1
        return {idx: f"TR:{text}" for idx, text in items}

    monkeypatch.setattr("src.pipeline.translate_segments", _translate)
    md = "# Same\n"
    opts = TranslateOptions(
        target_lang="es",
        use_memory=False,
        use_glossary=False,
        memory_path=db,
    )
    translate_markdown(md, opts)
    translate_markdown(md, opts)
    assert calls["n"] == 2


@pytest.fixture
def mock_translate_segments(monkeypatch):
    mock = MagicMock(
        side_effect=lambda items, target_lang, source_lang=None, **kwargs: {
            idx: f"TR:{text}" for idx, text in items
        }
    )
    monkeypatch.setattr("src.pipeline.translate_segments", mock)
    return mock
