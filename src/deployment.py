"""Configuración de despliegue: CORS, límites de upload y limpieza output/."""

from __future__ import annotations

import os
import time
from pathlib import Path


def get_cors_origins() -> list[str]:
    raw = os.getenv("CORS_ORIGINS", "").strip()
    if raw == "*":
        return ["*"]
    if raw:
        return [o.strip() for o in raw.split(",") if o.strip()]
    port = os.getenv("PORT", "5400")
    return [
        f"http://127.0.0.1:{port}",
        f"http://localhost:{port}",
    ]


def max_upload_bytes() -> int:
    mb = float(os.getenv("MAX_UPLOAD_MB", "10"))
    return int(mb * 1024 * 1024)


def max_batch_upload_bytes() -> int:
    mb = float(os.getenv("MAX_BATCH_UPLOAD_MB", "50"))
    return int(mb * 1024 * 1024)


def check_upload_limits(file_size: int, batch_total_bytes: int) -> None:
    limit = max_upload_bytes()
    if file_size > limit:
        raise ValueError(
            f"Archivo demasiado grande (máx {os.getenv('MAX_UPLOAD_MB', '10')} MB por archivo)"
        )
    batch_limit = max_batch_upload_bytes()
    if batch_total_bytes > batch_limit:
        raise ValueError(
            f"Lote demasiado grande (máx {os.getenv('MAX_BATCH_UPLOAD_MB', '50')} MB total)"
        )


def output_ttl_hours() -> float:
    try:
        return float(os.getenv("OUTPUT_TTL_HOURS", "24"))
    except ValueError:
        return 24.0


def output_sweep_interval_hours() -> float:
    try:
        return float(os.getenv("OUTPUT_SWEEP_INTERVAL_HOURS", "6"))
    except ValueError:
        return 6.0


def sweep_output_dir(output_dir: Path, ttl_hours: float | None = None) -> int:
    ttl = ttl_hours if ttl_hours is not None else output_ttl_hours()
    if ttl <= 0 or not output_dir.exists():
        return 0
    cutoff = time.time() - (ttl * 3600)
    deleted = 0
    for path in output_dir.iterdir():
        if path.is_file() and path.stat().st_mtime < cutoff:
            path.unlink(missing_ok=True)
            deleted += 1
    return deleted


def get_api_token() -> str | None:
    token = os.getenv("API_TOKEN", "").strip()
    return token or None


def verify_api_token(authorization: str | None) -> bool:
    expected = get_api_token()
    if not expected:
        return True
    if not authorization:
        return False
    if authorization.startswith("Bearer "):
        return authorization[7:].strip() == expected
    return authorization.strip() == expected
