"""Tests del builder ZIP de lote."""

from __future__ import annotations

import io
import json
import zipfile

from src.batch_zip import BatchFileError, BatchFileSuccess, build_batch_zip
from src.validator import validate_translation


def test_successes_only_no_errors_json():
    report = validate_translation("# Hi\n", "# Hola\n")
    successes = [
        BatchFileSuccess(
            filename="doc.md",
            out_name="doc.es.md",
            content="# Hola\n",
            validation=report,
        )
    ]
    data = build_batch_zip(successes, [])
    zf = zipfile.ZipFile(io.BytesIO(data))
    assert "doc.es.md" in zf.namelist()
    assert "doc.validation.json" in zf.namelist()
    assert "errors.json" not in zf.namelist()


def test_partial_includes_errors_json():
    successes = [
        BatchFileSuccess(
            filename="ok.md",
            out_name="ok.es.md",
            content="# OK\n",
            validation=None,
        )
    ]
    errors = [BatchFileError(filename="bad.md", message="falló")]
    data = build_batch_zip(successes, errors)
    zf = zipfile.ZipFile(io.BytesIO(data))
    assert "ok.es.md" in zf.namelist()
    assert "errors.json" in zf.namelist()
    payload = json.loads(zf.read("errors.json"))
    assert payload[0]["filename"] == "bad.md"
