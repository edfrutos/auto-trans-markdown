"""Tests de filtro .gitignore."""

from __future__ import annotations

from pathlib import Path

from src.gitignore_filter import is_ignored, iter_markdown_files, load_gitignore_patterns


def test_builtin_ignores_node_modules(tmp_path):
    nm = tmp_path / "node_modules" / "pkg" / "doc.md"
    nm.parent.mkdir(parents=True)
    nm.write_text("# Hi", encoding="utf-8")
    assert is_ignored(nm, tmp_path, []) is True


def test_gitignore_pattern(tmp_path):
    (tmp_path / ".gitignore").write_text("secret/\n", encoding="utf-8")
    secret = tmp_path / "secret" / "doc.md"
    secret.parent.mkdir()
    secret.write_text("# X", encoding="utf-8")
    ok = tmp_path / "doc.md"
    ok.write_text("# Y", encoding="utf-8")
    patterns = load_gitignore_patterns(tmp_path)
    assert is_ignored(secret, tmp_path, patterns) is True
    assert is_ignored(ok, tmp_path, patterns) is False


def test_iter_markdown_files(tmp_path):
    (tmp_path / "a.md").write_text("# A", encoding="utf-8")
    nm = tmp_path / "node_modules" / "b.md"
    nm.parent.mkdir()
    nm.write_text("# B", encoding="utf-8")
    files = iter_markdown_files(tmp_path, recursive=True)
    assert len(files) == 1
    assert files[0].name == "a.md"
