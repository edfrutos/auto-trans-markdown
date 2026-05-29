"""Tests export HTML."""

from __future__ import annotations

from src.html_export import markdown_to_html


def test_markdown_to_html_contains_title_and_body():
    html = markdown_to_html("# Hello\n\nWorld **bold**.", title="Doc")
    assert "<title>Doc</title>" in html
    assert "<h1>Hello</h1>" in html
    assert "<strong>bold</strong>" in html
    assert "<style>" in html
