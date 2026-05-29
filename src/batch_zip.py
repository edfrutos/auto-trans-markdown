"""Construcción de ZIP de lote con validación y errors.json."""

from __future__ import annotations

import io
import json
import zipfile
from dataclasses import dataclass
from pathlib import Path

from .validator import ValidationReport, validation_to_dict


@dataclass
class BatchFileSuccess:
    filename: str
    out_name: str
    content: str
    validation: ValidationReport | None = None
    validation_name: str | None = None


@dataclass
class BatchFileError:
    filename: str
    message: str


def build_batch_zip(
    successes: list[BatchFileSuccess],
    errors: list[BatchFileError],
) -> bytes:
    """Genera bytes ZIP con traducciones, validation.json y errors.json si aplica."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for item in successes:
            zf.writestr(item.out_name, item.content.encode("utf-8"))
            if item.validation is not None:
                val_name = item.validation_name
                if not val_name:
                    rel = Path(item.filename)
                    val_name = rel.with_suffix(".validation.json").as_posix()
                zf.writestr(
                    val_name,
                    json.dumps(
                        validation_to_dict(item.validation),
                        ensure_ascii=False,
                        indent=2,
                    ).encode("utf-8"),
                )
        if errors:
            payload = [
                {"filename": e.filename, "message": e.message} for e in errors
            ]
            zf.writestr(
                "errors.json",
                json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8"),
            )
    buffer.seek(0)
    return buffer.read()
