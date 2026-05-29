"""Tests de estimación de coste pre-traducción."""

from __future__ import annotations

import pytest

from src.estimate import estimate_markdown, estimate_files


def test_empty_markdown_zero_segments():
    result = estimate_markdown("", target_lang="es")
    assert result.segments == 0
    assert result.characters == 0
    assert result.estimated_cost_usd == 0.0
    assert result.exceeds_threshold is False


def test_fences_excluded_from_count():
    md = "# Title\n\n```python\nprint('hi')\n```\n\nParagraph text.\n"
    result = estimate_markdown(md, target_lang="es", use_memory=False)
    assert result.segments >= 1
    assert result.characters > 0


def test_threshold_flag(monkeypatch):
    monkeypatch.setenv("ESTIMATE_WARN_USD", "0.000001")
    md = "# Hello\n\n" + ("Word " * 500) + "\n"
    result = estimate_markdown(md, target_lang="es", use_memory=False)
    assert result.exceeds_threshold is True
    assert result.threshold_usd == pytest.approx(0.000001)


def test_estimate_files_aggregates():
    files = ["# One\n\nText.\n", "# Two\n\nMore.\n"]
    result = estimate_files(files, target_lang="es", use_memory=False)
    single = estimate_markdown(files[0], target_lang="es", use_memory=False)
    assert result.segments >= single.segments
    assert result.characters >= single.characters
