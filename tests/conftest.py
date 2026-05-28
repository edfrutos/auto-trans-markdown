"""Fixtures compartidas — tests sin OPENAI_API_KEY ni DEEPL_API_KEY."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from src.main import app
from src.translator import IncompleteTranslationError


@pytest.fixture(autouse=True)
def isolated_memory_db(tmp_path, monkeypatch):
    """Evita que tests compartan la TM en data/translation_memory.db."""
    db = tmp_path / "test_tm.db"

    def _path():
        return db

    monkeypatch.setattr("src.memory.default_memory_path", _path)
    monkeypatch.setattr("src.pipeline.default_memory_path", _path)
    monkeypatch.setattr("src.main.default_memory_path", _path)
    monkeypatch.setattr("src.cli.default_memory_path", _path)


@pytest.fixture
def client():
    return TestClient(app)


def make_md_bytes(text: str) -> bytes:
    return text.encode("utf-8")


def invalid_utf8_bytes() -> bytes:
    return b"# Title\n\xff\xfe invalid\n"


@pytest.fixture
def mock_translate_success(monkeypatch):
    def _translate(items, target_lang, source_lang=None, **kwargs):
        return {idx: f"TR:{text}" for idx, text in items}

    monkeypatch.setattr("src.pipeline.translate_segments", _translate)
    return _translate


@pytest.fixture
def mock_translate_incomplete(monkeypatch):
    def _translate(items, target_lang, source_lang=None, **kwargs):
        if not items:
            return {}
        idx, text = items[0]
        return {idx: f"TR:{text}"}

    monkeypatch.setattr("src.pipeline.translate_segments", _translate)
    return _translate


@pytest.fixture
def mock_translate_raises_incomplete(monkeypatch):
    def _translate(items, target_lang, source_lang=None, **kwargs):
        raise IncompleteTranslationError(
            expected=len(items),
            received=max(0, len(items) - 1),
            missing_indices=[items[-1][0]] if items else [],
        )

    monkeypatch.setattr("src.pipeline.translate_segments", _translate)
    return _translate
