"""Parsing y validación de idiomas destino múltiples."""

from __future__ import annotations

from pathlib import Path

from fastapi import HTTPException

from .translator import is_valid_target_lang

MAX_TARGET_LANGS = 10


def parse_target_langs(
    target_lang: str | None,
    target_langs: list[str] | None,
) -> list[str]:
    """Combina target_lang y target_langs; deduplica preservando orden."""
    langs: list[str] = []
    if target_langs:
        langs.extend(target_langs)
    elif target_lang:
        langs.append(target_lang)
    else:
        raise ValueError("Se requiere al menos un idioma destino")

    seen: set[str] = set()
    ordered: list[str] = []
    for raw in langs:
        code = raw.strip()
        if not code or code in seen:
            continue
        seen.add(code)
        ordered.append(code)

    if not ordered:
        raise ValueError("Se requiere al menos un idioma destino")
    if len(ordered) > MAX_TARGET_LANGS:
        raise ValueError(f"Máximo {MAX_TARGET_LANGS} idiomas destino por solicitud")
    return ordered


def validate_target_langs_http(target_langs: list[str]) -> None:
    for lang in target_langs:
        if not is_valid_target_lang(lang):
            raise HTTPException(
                400,
                f"Idioma destino no soportado por el proveedor activo: {lang}",
            )


def out_name_for_lang(filename: str, lang: str, used: set[str]) -> str:
    base = Path(filename).name
    stem = Path(base).stem or "documento"
    suffix = Path(base).suffix or ".md"
    out_name = f"{stem}.{lang}{suffix}"
    if out_name not in used:
        used.add(out_name)
        return out_name
    n = 2
    while True:
        candidate = f"{stem}_{n}.{lang}{suffix}"
        if candidate not in used:
            used.add(candidate)
            return candidate
        n += 1


def validation_sidecar_name(filename: str, lang: str) -> str:
    base = Path(filename).name
    stem = Path(base).stem or "documento"
    return f"{stem}.{lang}.validation.json"
