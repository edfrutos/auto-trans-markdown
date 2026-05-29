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
    assert data["validation"] is not None
    assert len(data["validation"]["checks"]) >= 1


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


def test_clear_memory(client, tmp_path, monkeypatch):
    db = tmp_path / "tm.db"
    monkeypatch.setattr("src.main.default_memory_path", lambda: db)
    from src.memory import TranslationMemory

    tm = TranslationMemory(db)
    tm.store_batch([(0, "a", "b")], None, "es")
    res = client.delete("/api/memory")
    assert res.status_code == 200
    assert res.json()["deleted"] >= 1


def test_glossary_get_put(client, tmp_path, monkeypatch):
    gpath = tmp_path / "glossary.yaml"
    monkeypatch.setattr("src.main.DEFAULT_GLOSSARY_PATH", gpath)
    monkeypatch.setattr("src.pipeline.DEFAULT_GLOSSARY_PATH", gpath)

    res = client.get("/api/glossary")
    assert res.status_code == 200
    assert "version" in res.json()

    res2 = client.put(
        "/api/glossary",
        json={
            "version": 1,
            "do_not_translate": ["Foo"],
            "pairs": {"en-es": {"bar": "baz"}},
        },
    )
    assert res2.status_code == 200
    assert res2.json()["do_not_translate"] == ["Foo"]


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
    assert any(name.endswith(".validation.json") for name in names)


def test_translate_file_includes_validation_header(client, mock_translate_success):
    res = client.post(
        "/api/translate/file",
        files={"file": ("doc.md", make_md_bytes("# Hello"), "text/markdown")},
        data={"target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 200
    assert "X-Validation-Report" in res.headers
    import json

    report = json.loads(res.headers["X-Validation-Report"])
    assert "overall" in report
    assert "checks" in report


def test_estimate_json_content(client):
    res = client.post(
        "/api/translate/estimate",
        json={
            "content": "# Hello\n\nWorld paragraph.\n",
            "target_lang": "es",
            "source_lang": "auto",
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert data["segments"] >= 1
    assert data["characters"] >= 1
    assert data["estimated_cost_usd"] >= 0
    assert "exceeds_threshold" in data
    assert "provider" in data
    assert "model" in data


def test_estimate_multipart_files(client):
    res = client.post(
        "/api/translate/estimate",
        files=[
            ("files", ("a.md", make_md_bytes("# A\n"), "text/markdown")),
            ("files", ("b.md", make_md_bytes("# B\n"), "text/markdown")),
        ],
        data={"target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 200
    data = res.json()
    assert data["segments"] >= 2


def test_batch_job_create_returns_id(client, mock_translate_success):
    res = client.post(
        "/api/translate/batch/jobs",
        files={"files": ("doc.md", make_md_bytes("# Hello"), "text/markdown")},
        data={"target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 200
    assert "job_id" in res.json()


def test_batch_job_events_content_type(client):
    from src.main import batch_job_events

    assert batch_job_events is not None
    res = client.get("/openapi.json")
    assert "/api/translate/batch/jobs/{job_id}/events" in res.json()["paths"]


def _wait_for_job(job_id: str, timeout: float = 5.0) -> None:
    import time

    from src.jobs import JobState, get_job

    deadline = time.time() + timeout
    while time.time() < deadline:
        job = get_job(job_id)
        if job and job.state in (JobState.COMPLETED, JobState.CANCELLED):
            return
        time.sleep(0.05)
    raise AssertionError(f"Job {job_id} did not finish in time")


def test_batch_job_download_after_complete(client, mock_translate_success):
    create = client.post(
        "/api/translate/batch/jobs",
        files={"files": ("doc.md", make_md_bytes("# Hello"), "text/markdown")},
        data={"target_lang": "es", "source_lang": "auto"},
    )
    job_id = create.json()["job_id"]
    _wait_for_job(job_id)
    dl = client.get(f"/api/translate/batch/jobs/{job_id}/download")
    assert dl.status_code == 200
    assert dl.headers.get("content-type", "").startswith("application/zip")
    zf = zipfile.ZipFile(io.BytesIO(dl.content))
    assert any(n.endswith(".es.md") for n in zf.namelist())


def test_batch_job_cancel(client, monkeypatch):
    import time

    def _slow(items, target_lang, source_lang=None, **kwargs):
        time.sleep(0.2)
        return {idx: f"TR:{text}" for idx, text in items}

    monkeypatch.setattr("src.pipeline.translate_segments", _slow)

    create = client.post(
        "/api/translate/batch/jobs",
        files=[
            ("files", ("a.md", make_md_bytes("# A\n\n" + ("word " * 50)), "text/markdown")),
            ("files", ("b.md", make_md_bytes("# B\n\n" + ("word " * 50)), "text/markdown")),
        ],
        data={"target_lang": "es", "source_lang": "auto"},
    )
    job_id = create.json()["job_id"]
    time.sleep(0.05)
    cancel = client.delete(f"/api/translate/batch/jobs/{job_id}")
    assert cancel.status_code == 200
    assert cancel.json()["cancelled"] is True
    _wait_for_job(job_id)
    dl = client.get(f"/api/translate/batch/jobs/{job_id}/download")
    assert dl.status_code == 200


def test_batch_zip_errors_json_in_partial(client, monkeypatch):
    call = {"n": 0}

    def _translate(items, target_lang, source_lang=None, **kwargs):
        call["n"] += 1
        if call["n"] == 1:
            raise RuntimeError("fail one")
        return {idx: f"TR:{text}" for idx, text in items}

    monkeypatch.setattr("src.pipeline.translate_segments", _translate)

    create = client.post(
        "/api/translate/batch/jobs",
        files=[
            ("files", ("bad.md", make_md_bytes("# Bad\n"), "text/markdown")),
            ("files", ("ok.md", make_md_bytes("# Ok\n"), "text/markdown")),
        ],
        data={"target_lang": "es", "source_lang": "auto"},
    )
    job_id = create.json()["job_id"]
    _wait_for_job(job_id)
    dl = client.get(f"/api/translate/batch/jobs/{job_id}/download")
    zf = zipfile.ZipFile(io.BytesIO(dl.content))
    assert "errors.json" in zf.namelist()


def test_translate_multi_target_langs_json(client, mock_translate_success):
    resp = client.post(
        "/api/translate",
        json={
            "content": "# Hello\n",
            "target_langs": ["es", "en"],
            "source_lang": "auto",
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "translations" in data
    assert "es" in data["translations"]
    assert "en" in data["translations"]


def test_batch_job_multi_lang_zip(client, mock_translate_success):
    create = client.post(
        "/api/translate/batch/jobs",
        files=[
            ("files", ("readme.md", make_md_bytes("# Hi\n"), "text/markdown")),
            ("target_langs", (None, "es")),
            ("target_langs", (None, "en")),
        ],
        data={"source_lang": "auto"},
    )
    assert create.status_code == 200
    job_id = create.json()["job_id"]
    _wait_for_job(job_id)
    dl = client.get(f"/api/translate/batch/jobs/{job_id}/download")
    zf = zipfile.ZipFile(io.BytesIO(dl.content))
    names = zf.namelist()
    assert "readme.es.md" in names
    assert "readme.en.md" in names


def test_oversized_upload_rejected(client, monkeypatch):
    monkeypatch.setenv("MAX_UPLOAD_MB", "0.001")
    big = b"# " + b"x" * 5000
    res = client.post(
        "/api/translate/file",
        files={"file": ("big.md", big, "text/markdown")},
        data={"target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 400
    assert "grande" in res.json()["detail"].lower()


def test_cors_header_present(client):
    from src.deployment import get_cors_origins

    origin = get_cors_origins()[0]
    res = client.get("/api/languages", headers={"Origin": origin})
    allowed = res.headers.get("access-control-allow-origin")
    assert allowed == origin or allowed == "*"
