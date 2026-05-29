"""Tests de configuración de despliegue."""

from __future__ import annotations

import time
from pathlib import Path

import pytest

from src.deployment import (
    check_upload_limits,
    get_cors_origins,
    get_api_token,
    sweep_output_dir,
    verify_api_token,
    verify_api_token_auth,
)


def test_get_cors_origins_default(monkeypatch):
    monkeypatch.delenv("CORS_ORIGINS", raising=False)
    monkeypatch.setenv("PORT", "5400")
    origins = get_cors_origins()
    assert "http://127.0.0.1:5400" in origins
    assert "http://localhost:5400" in origins


def test_get_cors_origins_custom(monkeypatch):
    monkeypatch.setenv("CORS_ORIGINS", "https://app.example.com,https://docs.example.com")
    origins = get_cors_origins()
    assert origins == ["https://app.example.com", "https://docs.example.com"]


def test_get_cors_origins_wildcard(monkeypatch):
    monkeypatch.setenv("CORS_ORIGINS", "*")
    assert get_cors_origins() == ["*"]


def test_check_upload_limits_file(monkeypatch):
    monkeypatch.setenv("MAX_UPLOAD_MB", "1")
    monkeypatch.setenv("MAX_BATCH_UPLOAD_MB", "2")
    check_upload_limits(100, 100)
    with pytest.raises(ValueError, match="Archivo demasiado grande"):
        check_upload_limits(2 * 1024 * 1024, 100)


def test_check_upload_limits_batch(monkeypatch):
    monkeypatch.setenv("MAX_UPLOAD_MB", "10")
    monkeypatch.setenv("MAX_BATCH_UPLOAD_MB", "1")
    with pytest.raises(ValueError, match="Lote demasiado grande"):
        check_upload_limits(100, 2 * 1024 * 1024)


def test_sweep_output_dir(tmp_path):
    old = tmp_path / "old.txt"
    new = tmp_path / "new.txt"
    old.write_text("x", encoding="utf-8")
    new.write_text("y", encoding="utf-8")
    old.touch()
    new.touch()
    past = time.time() - 7200
    import os

    os.utime(old, (past, past))
    deleted = sweep_output_dir(tmp_path, ttl_hours=1)
    assert deleted == 1
    assert not old.exists()
    assert new.exists()


def test_api_token_optional(monkeypatch):
    monkeypatch.delenv("API_TOKEN", raising=False)
    assert get_api_token() is None
    assert verify_api_token(None) is True


def test_api_token_bearer(monkeypatch):
    monkeypatch.setenv("API_TOKEN", "secret-token")
    assert verify_api_token("Bearer secret-token") is True
    assert verify_api_token("Bearer wrong") is False
    assert verify_api_token(None) is False


def test_api_token_auth_query_param(monkeypatch):
    monkeypatch.setenv("API_TOKEN", "secret-token")
    assert verify_api_token_auth(None, "secret-token") is True
    assert verify_api_token_auth(None, "wrong") is False
    assert verify_api_token_auth("Bearer secret-token", None) is True
