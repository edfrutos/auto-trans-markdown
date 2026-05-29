"""Tests CLI Typer."""

from __future__ import annotations

import zipfile
from pathlib import Path
from unittest.mock import MagicMock

import pytest
from typer.testing import CliRunner

from src.cli import app
from src.pipeline import TranslateResult
from src.validator import ValidationCheck, ValidationReport

runner = CliRunner()


@pytest.fixture
def mock_pipeline(monkeypatch):
    def _fake(content, options):
        if options.dry_run:
            return TranslateResult(
                content="",
                segments_total=1,
                segments_translated=1,
                dry_run_segments=[(0, "Hello")],
            )
        return TranslateResult(
            content=f"# TR\n{content}",
            segments_total=1,
            segments_translated=1,
            validation=ValidationReport(overall="pass", checks=[]),
        )

    monkeypatch.setattr("src.cli.translate_markdown", _fake)
    return _fake


@pytest.fixture
def mock_pipeline_validation_error(monkeypatch):
    def _fake(content, options):
        return TranslateResult(
            content=f"# TR\n{content}",
            segments_total=1,
            segments_translated=1,
            validation=ValidationReport(
                overall="error",
                checks=[
                    ValidationCheck(
                        id="fences",
                        status="error",
                        message="mismatch",
                    )
                ],
            ),
        )

    monkeypatch.setattr("src.cli.translate_markdown", _fake)
    return _fake


def test_file_dry_run(tmp_path, mock_pipeline):
    md = tmp_path / "doc.md"
    md.write_text("# Hello\n", encoding="utf-8")
    result = runner.invoke(
        app, ["file", str(md), "-t", "es", "--dry-run"], catch_exceptions=False
    )
    assert result.exit_code == 0
    assert "Hello" in result.stdout


def test_file_writes_output(tmp_path, mock_pipeline):
    md = tmp_path / "doc.md"
    md.write_text("# Hello\n", encoding="utf-8")
    out = tmp_path / "out.es.md"
    result = runner.invoke(
        app, ["file", str(md), "-t", "es", "-o", str(out)], catch_exceptions=False
    )
    assert result.exit_code == 0
    assert out.exists()
    assert "TR" in out.read_text(encoding="utf-8")


def test_memory_clear(tmp_path, monkeypatch):
    db = tmp_path / "tm.db"
    monkeypatch.setattr("src.cli.default_memory_path", lambda: db)
    from src.memory import TranslationMemory

    tm = TranslationMemory(db)
    tm.store_batch([(0, "a", "b")], None, "es")
    result = runner.invoke(app, ["memory", "clear"], catch_exceptions=False)
    assert result.exit_code == 0
    assert "eliminadas" in result.stdout.lower() or "vaciada" in result.stdout.lower()


def test_help_lists_commands():
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "file" in result.stdout
    assert "serve" in result.stdout
    assert "memory" in result.stdout


def test_invalid_target_exits_2(tmp_path, monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "openai")
    md = tmp_path / "doc.md"
    md.write_text("# Hi", encoding="utf-8")
    result = runner.invoke(
        app, ["file", str(md), "-t", "notalang"], catch_exceptions=False
    )
    assert result.exit_code == 2


def test_dir_recursive(tmp_path, mock_pipeline):
    root = tmp_path / "docs"
    sub = root / "sub"
    sub.mkdir(parents=True)
    (root / "a.md").write_text("# A", encoding="utf-8")
    (sub / "b.md").write_text("# B", encoding="utf-8")
    out = tmp_path / "out"
    result = runner.invoke(
        app,
        ["dir", str(root), "-o", str(out), "-t", "es", "--recursive"],
        catch_exceptions=False,
    )
    assert result.exit_code == 0
    assert (out / "a.es.md").exists()
    assert (out / "sub" / "b.es.md").exists()


def test_batch_zip(tmp_path, mock_pipeline):
    a = tmp_path / "a.md"
    b = tmp_path / "b.md"
    a.write_text("# A", encoding="utf-8")
    b.write_text("# B", encoding="utf-8")
    zpath = tmp_path / "out.zip"
    result = runner.invoke(
        app,
        ["batch", str(a), str(b), "-t", "es", "--zip", str(zpath)],
        catch_exceptions=False,
    )
    assert result.exit_code == 0
    with zipfile.ZipFile(zpath) as zf:
        names = zf.namelist()
        assert len([n for n in names if n.endswith(".es.md")]) == 2
        assert len([n for n in names if n.endswith(".validation.json")]) == 2


def test_file_strict_blocks_on_validation_error(
    tmp_path, mock_pipeline_validation_error
):
    md = tmp_path / "doc.md"
    out = tmp_path / "out.es.md"
    md.write_text("# Hello\n", encoding="utf-8")
    result = runner.invoke(
        app,
        ["file", str(md), "-t", "es", "-o", str(out), "--strict"],
        catch_exceptions=False,
    )
    assert result.exit_code == 1
    assert not out.exists()


def test_file_strict_allows_pass(tmp_path, mock_pipeline):
    md = tmp_path / "doc.md"
    out = tmp_path / "out.es.md"
    md.write_text("# Hello\n", encoding="utf-8")
    result = runner.invoke(
        app,
        ["file", str(md), "-t", "es", "-o", str(out), "--strict"],
        catch_exceptions=False,
    )
    assert result.exit_code == 0
    assert out.exists()


def test_parse_targets_comma_list(tmp_path, mock_pipeline):
    md = tmp_path / "doc.md"
    md.write_text("# Hello\n", encoding="utf-8")
    result = runner.invoke(
        app, ["file", str(md), "-t", "es,en"], catch_exceptions=False
    )
    assert result.exit_code == 0
    assert (tmp_path / "doc.es.md").exists()
    assert (tmp_path / "doc.en.md").exists()


def test_parse_targets_rejects_invalid(tmp_path, monkeypatch):
    monkeypatch.setenv("TRANSLATION_PROVIDER", "openai")
    md = tmp_path / "doc.md"
    md.write_text("# Hi", encoding="utf-8")
    result = runner.invoke(
        app, ["file", str(md), "-t", "es,notalang"], catch_exceptions=False
    )
    assert result.exit_code == 2


def test_batch_multi_lang_zip(tmp_path, mock_pipeline):
    md = tmp_path / "doc.md"
    md.write_text("# Doc", encoding="utf-8")
    zpath = tmp_path / "out.zip"
    result = runner.invoke(
        app,
        ["batch", str(md), "-t", "es,en", "--zip", str(zpath)],
        catch_exceptions=False,
    )
    assert result.exit_code == 0
    with zipfile.ZipFile(zpath) as zf:
        names = zf.namelist()
        assert "doc.es.md" in names
        assert "doc.en.md" in names


def test_batch_zip_passes_tone(tmp_path, monkeypatch):
    captured_tones: list[str] = []

    def _fake(content, options):
        captured_tones.append(options.tone)
        return TranslateResult(
            content=f"# TR\n{content}",
            segments_total=1,
            segments_translated=1,
            validation=ValidationReport(overall="pass", checks=[]),
        )

    monkeypatch.setattr("src.cli.translate_markdown", _fake)
    md = tmp_path / "doc.md"
    md.write_text("# Doc", encoding="utf-8")
    zpath = tmp_path / "out.zip"
    result = runner.invoke(
        app,
        ["batch", str(md), "-t", "es", "--zip", str(zpath), "--tone", "formal"],
        catch_exceptions=False,
    )
    assert result.exit_code == 0
    assert captured_tones
    assert all(t == "formal" for t in captured_tones)


def test_dir_respects_gitignore(tmp_path, mock_pipeline):
    root = tmp_path / "docs"
    root.mkdir()
    (root / ".gitignore").write_text("secret/\n", encoding="utf-8")
    (root / "ok.md").write_text("# OK", encoding="utf-8")
    secret = root / "secret"
    secret.mkdir()
    (secret / "skip.md").write_text("# Skip", encoding="utf-8")
    out = tmp_path / "out"
    result = runner.invoke(
        app,
        ["dir", str(root), "-o", str(out), "-t", "es", "--respect-gitignore"],
        catch_exceptions=False,
    )
    assert result.exit_code == 0
    assert (out / "ok.es.md").exists()
    assert not (out / "secret" / "skip.es.md").exists()


def test_export_html(tmp_path):
    md = tmp_path / "doc.md"
    md.write_text("# Hello\n\n**World**", encoding="utf-8")
    html_out = tmp_path / "doc.html"
    result = runner.invoke(
        app, ["export", str(md), "-o", str(html_out)], catch_exceptions=False
    )
    assert result.exit_code == 0
    html = html_out.read_text(encoding="utf-8")
    assert "<h1>Hello</h1>" in html
    assert "<title>doc</title>" in html


def test_export_pdf(tmp_path, monkeypatch):
    monkeypatch.setattr(
        "src.cli.markdown_to_pdf",
        lambda content, title="Document": b"%PDF-test-content",
    )
    md = tmp_path / "doc.md"
    md.write_text("# Hello", encoding="utf-8")
    pdf_out = tmp_path / "doc.pdf"
    result = runner.invoke(
        app,
        ["export", str(md), "-o", str(pdf_out), "--format", "pdf"],
        catch_exceptions=False,
    )
    assert result.exit_code == 0
    assert pdf_out.read_bytes().startswith(b"%PDF")


def test_export_invalid_format(tmp_path):
    md = tmp_path / "doc.md"
    md.write_text("# Hi", encoding="utf-8")
    result = runner.invoke(
        app,
        ["export", str(md), "-o", str(tmp_path / "out.bin"), "--format", "docx"],
        catch_exceptions=False,
    )
    assert result.exit_code == 2


def test_help_lists_watch_and_export():
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "watch" in result.stdout
    assert "export" in result.stdout
