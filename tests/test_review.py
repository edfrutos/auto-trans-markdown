"""Tests del modo revisión."""

from __future__ import annotations

from src.pipeline import TranslateOptions
from src.review import build_draft, finalize_draft, score_doubtful


def test_score_doubtful_identical_long_text():
    text = "This is a long segment that should be translated properly."
    assert score_doubtful(text, text) is True


def test_score_doubtful_ratio_outlier():
    assert score_doubtful("Hello world", "H") is True


def test_finalize_roundtrip(mock_translate_success, monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "openai")
    md = "# Title\n\nParagraph one.\n"
    options = TranslateOptions(target_lang="es", source_lang=None)
    draft = build_draft(md, options)
    assert draft.segments
    edits = {s.index: f"EDIT:{s.translated}" for s in draft.segments}
    result = finalize_draft(md, edits)
    assert "EDIT:" in result.content
    assert result.validation is not None
