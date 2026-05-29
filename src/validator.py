"""Validación estructural post-traducción (original vs traducido)."""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass

FENCE_OPEN_PATTERN = re.compile(r"^(```+|~~~+)", re.MULTILINE)
LINK_PATTERN = re.compile(r"(?<!!)\[[^\]]*\]\([^)]+\)")
IMAGE_PATTERN = re.compile(r"!\[[^\]]*\]\([^)]+\)")
HEADING_PATTERN = re.compile(r"^(\s*)(#{1,6})\s", re.MULTILINE)


@dataclass
class ValidationCheck:
    id: str
    status: str
    message: str
    expected: int | None = None
    actual: int | None = None


@dataclass
class ValidationReport:
    overall: str
    checks: list[ValidationCheck]


def _strip_fenced_blocks(text: str) -> str:
    """Elimina contenido entre fences para checks de headings/inline."""
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    in_fence = False
    fence_char = ""
    fence_len = 0

    for line in lines:
        stripped = line.strip()
        match = FENCE_OPEN_PATTERN.match(stripped)
        if match:
            if not in_fence:
                in_fence = True
                fence_char = match.group(1)[0]
                fence_len = len(match.group(1))
                out.append("\n")
                continue
            if (
                match.group(1)[0] == fence_char
                and len(match.group(1)) >= fence_len
            ):
                in_fence = False
                out.append("\n")
                continue
        if not in_fence:
            out.append(line)
        else:
            out.append("\n")
    return "".join(out)


def _count_fence_opens(text: str) -> int:
    return len(FENCE_OPEN_PATTERN.findall(text))


def _count_inline_code_runs(text: str) -> int:
    stripped = _strip_fenced_blocks(text)
    count = 0
    i = 0
    while i < len(stripped):
        if stripped[i] == "`":
            end = i + 1
            while end < len(stripped) and stripped[end] == "`":
                end += 1
            tick_count = end - i
            close = stripped.find("`" * tick_count, end)
            if close == -1:
                break
            count += 1
            i = close + tick_count
        else:
            i += 1
    return count


def _heading_depths(text: str) -> list[int]:
    stripped = _strip_fenced_blocks(text)
    depths: list[int] = []
    for line in stripped.splitlines():
        match = HEADING_PATTERN.match(line)
        if match:
            depths.append(len(match.group(2)))
    return depths


def _aggregate_overall(checks: list[ValidationCheck]) -> str:
    if any(c.status == "error" for c in checks):
        return "error"
    if any(c.status == "warn" for c in checks):
        return "warn"
    return "pass"


def _check_count(
    check_id: str,
    label: str,
    unit: str,
    expected: int,
    actual: int,
) -> ValidationCheck:
    if expected == actual:
        return ValidationCheck(
            id=check_id,
            status="pass",
            message=f"{label}: {actual} {unit} (correcto)",
            expected=expected,
            actual=actual,
        )
    return ValidationCheck(
        id=check_id,
        status="error",
        message=f"{label}: {expected} esperados, {actual} encontrados",
        expected=expected,
        actual=actual,
    )


def validate_translation(original: str, translated: str) -> ValidationReport:
    """Compara estructura Markdown entre original y traducido."""
    checks: list[ValidationCheck] = []

    orig_fences = _count_fence_opens(original)
    trans_fences = _count_fence_opens(translated)
    checks.append(
        _check_count("fences", "Bloques de código", "bloques", orig_fences, trans_fences)
    )

    orig_links = len(LINK_PATTERN.findall(original))
    trans_links = len(LINK_PATTERN.findall(translated))
    checks.append(
        _check_count("links", "Enlaces", "enlaces", orig_links, trans_links)
    )

    orig_images = len(IMAGE_PATTERN.findall(original))
    trans_images = len(IMAGE_PATTERN.findall(translated))
    checks.append(
        _check_count("images", "Imágenes", "imágenes", orig_images, trans_images)
    )

    orig_inline = _count_inline_code_runs(original)
    trans_inline = _count_inline_code_runs(translated)
    checks.append(
        _check_count(
            "inline_code",
            "Código inline",
            "spans",
            orig_inline,
            trans_inline,
        )
    )

    orig_headings = _heading_depths(original)
    trans_headings = _heading_depths(translated)
    if orig_headings == trans_headings:
        checks.append(
            ValidationCheck(
                id="headings",
                status="pass",
                message="Encabezados: profundidad por línea coincide",
                expected=len(orig_headings),
                actual=len(trans_headings),
            )
        )
    else:
        checks.append(
            ValidationCheck(
                id="headings",
                status="error",
                message=(
                    f"Encabezados: secuencia de profundidad distinta "
                    f"({len(orig_headings)} vs {len(trans_headings)} líneas)"
                ),
                expected=len(orig_headings),
                actual=len(trans_headings),
            )
        )

    return ValidationReport(overall=_aggregate_overall(checks), checks=checks)


def validation_to_dict(report: ValidationReport) -> dict:
    """Serializa informe para JSON/API."""
    return asdict(report)
