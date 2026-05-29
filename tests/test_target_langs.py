"""Tests de parsing multi-idioma destino."""

from __future__ import annotations

import pytest
from fastapi import HTTPException

from src.target_langs import (
    out_name_for_lang,
    parse_target_langs,
    validate_target_langs_http,
    validation_sidecar_name,
)


def test_parse_single_target_lang():
    assert parse_target_langs("es", None) == ["es"]


def test_parse_target_langs_list():
    assert parse_target_langs(None, ["es", "en", "fr"]) == ["es", "en", "fr"]


def test_parse_dedupes():
    assert parse_target_langs("es", ["es", "en", "en"]) == ["es", "en"]


def test_parse_empty_raises():
    with pytest.raises(ValueError, match="al menos"):
        parse_target_langs(None, [])


def test_out_name_collision():
    used: set[str] = set()
    a = out_name_for_lang("doc.md", "es", used)
    b = out_name_for_lang("doc.md", "es", used)
    assert a == "doc.es.md"
    assert b == "doc_2.es.md"


def test_validation_sidecar():
    assert validation_sidecar_name("readme.md", "en") == "readme.en.validation.json"


def test_validate_invalid_lang():
    with pytest.raises(HTTPException, match="no soportado"):
        validate_target_langs_http(["invalid-lang-code"])
