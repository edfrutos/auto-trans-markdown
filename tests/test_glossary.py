"""Tests del módulo de glosario."""

from __future__ import annotations

from pathlib import Path

import pytest

from src.glossary import (
    Glossary,
    GlossaryRules,
    apply_post,
    apply_pre,
    build_prompt_appendix,
    load_glossary,
    save_glossary,
)


def test_missing_file_returns_empty(tmp_path):
    g = load_glossary(tmp_path / "missing.yaml")
    assert g.do_not_translate == []
    assert g.pairs == {}


def test_save_load_roundtrip(tmp_path):
    path = tmp_path / "glossary.yaml"
    g = Glossary(
        do_not_translate=["API"],
        pairs={"en-es": {"dashboard": "panel"}},
    )
    save_glossary(path, g)
    loaded = load_glossary(path)
    assert loaded.do_not_translate == ["API"]
    assert loaded.pairs["en-es"]["dashboard"] == "panel"


def test_dnt_preserved_openai_post():
    rules = GlossaryRules(do_not_translate=["API Gateway"], pairs={})
    text, state = apply_pre("Use API Gateway here", rules, "openai")
    assert text == "Use API Gateway here"
    assert apply_post("Use API Gateway here", state, rules) == "Use API Gateway here"


def test_pair_rule_openai_post():
    rules = GlossaryRules(pairs={"dashboard": "panel"})
    text, state = apply_pre("Open dashboard", rules, "openai")
    out = apply_post("Open panel de control", state, rules)
    assert "panel" in out


def test_deepl_placeholder_cycle():
    rules = GlossaryRules(pairs={"dashboard": "panel"})
    text, state = apply_pre("Open dashboard now", rules, "deepl")
    assert "⟦GLO0⟧" in text
    restored = apply_post("Open ⟦GLO0⟧ now", state, rules)
    assert restored == "Open panel now"


def test_build_openai_appendix():
    rules = GlossaryRules(
        do_not_translate=["API"],
        pairs={"dashboard": "panel"},
    )
    block = build_prompt_appendix(rules)
    assert "API" in block
    assert "dashboard" in block


def test_file_size_limit(tmp_path):
    path = tmp_path / "big.yaml"
    path.write_bytes(b"x" * (256 * 1024 + 1))
    with pytest.raises(ValueError, match="256"):
        load_glossary(path)
