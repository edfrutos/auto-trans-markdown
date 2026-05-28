"""Tests HTTP de la API FastAPI."""

from __future__ import annotations

import io
import zipfile

import pytest

from tests.conftest import invalid_utf8_bytes, make_md_bytes


def test_decode_upload_valid_utf8():
    from src.main import _decode_upload

    assert _decode_upload(make_md_bytes("# Hola\n"), "doc.md") == "# Hola\n"


def test_decode_upload_invalid_utf8_raises():
    from src.main import _decode_upload

    with pytest.raises(ValueError, match="UTF-8"):
        _decode_upload(invalid_utf8_bytes(), "bad.md")


def test_translate_file_invalid_utf8_returns_400(client):
    res = client.post(
        "/api/translate/file",
        files={"file": ("bad.md", invalid_utf8_bytes(), "text/markdown")},
        data={"target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 400
    assert "UTF-8" in res.json()["detail"]


def test_translate_batch_invalid_utf8_returns_400(client):
    res = client.post(
        "/api/translate/batch",
        files={"files": ("bad.md", invalid_utf8_bytes(), "text/markdown")},
        data={"target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 400
    assert "UTF-8" in res.json()["detail"]


def test_translate_text_success(client, mock_translate_success):
    res = client.post(
        "/api/translate",
        json={"content": "# Hello\n", "target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 200
    data = res.json()
    assert "TR:" in data["content"]
    assert data["segments_translated"] >= 1


def test_translate_incomplete_returns_502(client, mock_translate_raises_incomplete):
    res = client.post(
        "/api/translate",
        json={"content": "# Hello\n\nWorld\n", "target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 502
    detail = res.json()["detail"]
    assert detail["expected"] >= 1
    assert detail["received"] >= 0
    assert "missing_indices" in detail
    assert "message" in detail


def test_languages_deepl_excludes_ca(client, monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "deepl")
    res = client.get("/api/languages")
    assert res.status_code == 200
    codes = {item["code"] for item in res.json()}
    assert "ca" not in codes
    assert "es" in codes


def test_translate_invalid_target_lang_deepl(client, monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "deepl")
    res = client.post(
        "/api/translate",
        json={"content": "# Hi", "target_lang": "ca", "source_lang": "auto"},
    )
    assert res.status_code == 400
    assert "no soportado" in res.json()["detail"]


def test_translate_file_invalid_source_lang(client, monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "openai")
    res = client.post(
        "/api/translate/file",
        files={"file": ("doc.md", make_md_bytes("# Hi"), "text/markdown")},
        data={"target_lang": "es", "source_lang": "xx"},
    )
    assert res.status_code == 400


def test_translate_batch_invalid_target_lang(client, monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "openai")
    res = client.post(
        "/api/translate/batch",
        files={"files": ("doc.md", make_md_bytes("# Hi"), "text/markdown")},
        data={"target_lang": "invalid", "source_lang": "auto"},
    )
    assert res.status_code == 400


def test_translate_batch_success(client, mock_translate_success):
    res = client.post(
        "/api/translate/batch",
        files={"files": ("doc.md", make_md_bytes("# Hello"), "text/markdown")},
        data={"target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 200
    zf = zipfile.ZipFile(io.BytesIO(res.content))
    names = zf.namelist()
    assert any(name.endswith(".es.md") for name in names)
