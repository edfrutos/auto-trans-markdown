"""Tests export PDF."""

from __future__ import annotations

import sys
from unittest.mock import MagicMock

import pytest

from src.pdf_export import is_pdf_available, markdown_to_pdf


def test_is_pdf_available_false_when_missing(monkeypatch):
    monkeypatch.delitem(sys.modules, "weasyprint", raising=False)

    def _fail_import(name, *args, **kwargs):
        if name == "weasyprint":
            raise ImportError("no weasyprint")
        return orig_import(name, *args, **kwargs)

    orig_import = __import__
    monkeypatch.setattr("builtins.__import__", _fail_import)
    assert is_pdf_available() is False


def test_markdown_to_pdf_raises_without_weasyprint(monkeypatch):
    monkeypatch.setattr("src.pdf_export.is_pdf_available", lambda: False)
    with pytest.raises(RuntimeError, match="WeasyPrint"):
        markdown_to_pdf("# Hi")


def test_markdown_to_pdf_mock_weasyprint(monkeypatch):
    captured: dict[str, str] = {}

    class FakeHTML:
        def __init__(self, *, string: str):
            captured["html"] = string

        def write_pdf(self):
            return b"%PDF-1.4 mock"

    fake_module = MagicMock()
    fake_module.HTML = FakeHTML
    monkeypatch.setitem(sys.modules, "weasyprint", fake_module)
    monkeypatch.setattr("src.pdf_export.is_pdf_available", lambda: True)

    result = markdown_to_pdf("# Hello\n\n**bold**", title="Doc")
    assert result.startswith(b"%PDF")
    assert "<h1>Hello</h1>" in captured["html"]
    assert "<strong>bold</strong>" in captured["html"]
    assert "@page" in captured["html"]
