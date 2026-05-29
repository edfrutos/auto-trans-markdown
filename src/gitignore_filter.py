"""Filtrado de rutas según .gitignore y exclusiones built-in."""

from __future__ import annotations

import fnmatch
from pathlib import Path

BUILTIN_IGNORED_DIRS = frozenset(
    {".git", "node_modules", ".venv", "__pycache__", ".pytest_cache"}
)


def load_gitignore_patterns(root: Path) -> list[str]:
    """Lee patrones de .gitignore en la raíz del proyecto."""
    path = root / ".gitignore"
    if not path.is_file():
        return []
    patterns: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        patterns.append(line)
    return patterns


def _pattern_matches(rel_posix: str, name: str, pattern: str) -> bool:
    pat = pattern.rstrip("/")
    if pat.startswith("/"):
        pat = pat[1:]
        return fnmatch.fnmatch(rel_posix, pat) or rel_posix == pat
    if "/" in pat:
        return fnmatch.fnmatch(rel_posix, pat) or rel_posix.endswith("/" + pat)
    return fnmatch.fnmatch(name, pat) or pat in rel_posix.split("/")


def is_ignored(
    path: Path,
    root: Path,
    patterns: list[str] | None = None,
) -> bool:
    """True si la ruta debe omitirse (built-in + .gitignore)."""
    try:
        rel = path.relative_to(root)
    except ValueError:
        return False
    for part in rel.parts:
        if part in BUILTIN_IGNORED_DIRS:
            return True
    if patterns is None:
        patterns = load_gitignore_patterns(root)
    rel_posix = rel.as_posix()
    name = path.name
    ignored = False
    for pattern in patterns:
        if pattern.startswith("!"):
            if _pattern_matches(rel_posix, name, pattern[1:].lstrip("/")):
                ignored = False
        elif _pattern_matches(rel_posix, name, pattern):
            ignored = True
    return ignored


def iter_markdown_files(
    root: Path,
    *,
    recursive: bool = True,
    respect_gitignore: bool = True,
) -> list[Path]:
    """Lista archivos Markdown no ignorados bajo root."""
    patterns = load_gitignore_patterns(root) if respect_gitignore else []
    globber = root.rglob if recursive else root.glob
    files: list[Path] = []
    for path in sorted(globber("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() not in {".md", ".markdown", ".mdx"}:
            continue
        if respect_gitignore and is_ignored(path, root, patterns):
            continue
        files.append(path)
    return files
