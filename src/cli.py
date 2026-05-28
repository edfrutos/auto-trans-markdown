"""CLI Typer: md-translate file|dir|batch|serve|memory."""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

import typer
from dotenv import load_dotenv

from .memory import TranslationMemory, default_memory_path
from .pipeline import TranslateOptions, translate_markdown
from .translator import (
    IncompleteTranslationError,
    is_valid_source_lang,
    is_valid_target_lang,
)

load_dotenv()

app = typer.Typer(
    name="md-translate",
    help="Traduce Markdown preservando formato y bloques de código",
    no_args_is_help=True,
)
memory_app = typer.Typer(help="Gestión de memoria de traducción")
app.add_typer(memory_app, name="memory")

MD_EXTENSIONS = {".md", ".markdown", ".mdx"}


def _exit_config(msg: str) -> None:
    typer.echo(msg, err=True)
    raise typer.Exit(2)


def _exit_translation(msg: str) -> None:
    typer.echo(msg, err=True)
    raise typer.Exit(1)


def _build_options(
    target: str,
    source: str,
    dry_run: bool,
    no_memory: bool,
    no_glossary: bool,
    glossary_path: Path | None,
) -> TranslateOptions:
    if not is_valid_target_lang(target):
        _exit_config(f"Idioma destino no soportado: {target}")
    if source != "auto" and not is_valid_source_lang(source):
        _exit_config(f"Idioma origen no soportado: {source}")
    return TranslateOptions(
        target_lang=target,
        source_lang=None if source == "auto" else source,
        dry_run=dry_run,
        use_memory=not no_memory,
        use_glossary=not no_glossary,
        glossary_path=glossary_path,
    )


def _translate_content(content: str, options: TranslateOptions):
    try:
        return translate_markdown(content, options)
    except ValueError as e:
        _exit_config(str(e))
    except IncompleteTranslationError as e:
        _exit_translation(str(e))
    except RuntimeError as e:
        _exit_translation(str(e))


def _is_markdown(path: Path) -> bool:
    return path.suffix.lower() in MD_EXTENSIONS


@memory_app.command("clear")
def memory_clear() -> None:
    """Vacía la memoria de traducción SQLite."""
    tm = TranslationMemory(default_memory_path())
    deleted = tm.clear()
    typer.echo(f"Memoria vaciada: {deleted} entradas eliminadas")


@app.command("serve")
def serve_cmd(
    host: str | None = typer.Option(None, help="Host (default desde .env)"),
    port: int | None = typer.Option(None, help="Puerto (default desde .env)"),
) -> None:
    """Arranca el servidor web FastAPI."""
    import os

    from .main import run

    if host:
        os.environ["HOST"] = host
    if port:
        os.environ["PORT"] = str(port)
    run()


@app.command("file")
def file_cmd(
    input_path: Path = typer.Argument(..., exists=True, readable=True),
    target: str = typer.Option(..., "--target", "-t", help="Idioma destino"),
    output: Path | None = typer.Option(None, "--output", "-o", help="Archivo salida"),
    source: str = typer.Option("auto", "--source", "-s", help="Idioma origen"),
    dry_run: bool = typer.Option(False, "--dry-run", help="Listar segmentos sin traducir"),
    no_memory: bool = typer.Option(False, "--no-memory"),
    no_glossary: bool = typer.Option(False, "--no-glossary"),
    glossary_path: Path | None = typer.Option(None, "--glossary-path"),
) -> None:
    """Traduce un archivo Markdown."""
    content = input_path.read_text(encoding="utf-8")
    options = _build_options(
        target, source, dry_run, no_memory, no_glossary, glossary_path
    )
    result = _translate_content(content, options)

    if dry_run:
        for idx, text in result.dry_run_segments or []:
            typer.echo(json.dumps({"index": idx, "text": text}, ensure_ascii=False))
        return

    out_path = output or input_path.with_name(
        f"{input_path.stem}.{target}{input_path.suffix or '.md'}"
    )
    out_path.write_text(result.content, encoding="utf-8")
    typer.echo(f"Traducido → {out_path}")


@app.command("dir")
def dir_cmd(
    path: Path = typer.Argument(..., exists=True, file_okay=False),
    output_dir: Path = typer.Option(..., "--output-dir", "-o"),
    target: str = typer.Option(..., "--target", "-t"),
    source: str = typer.Option("auto", "--source", "-s"),
    recursive: bool = typer.Option(False, "--recursive", "-r"),
    dry_run: bool = typer.Option(False, "--dry-run"),
    no_memory: bool = typer.Option(False, "--no-memory"),
    no_glossary: bool = typer.Option(False, "--no-glossary"),
    glossary_path: Path | None = typer.Option(None, "--glossary-path"),
) -> None:
    """Traduce archivos .md en un directorio."""
    pattern = "**/*" if recursive else "*"
    files = sorted(
        p for p in path.glob(pattern) if p.is_file() and _is_markdown(p)
    )
    if not files:
        _exit_config("No se encontraron archivos Markdown")

    output_dir.mkdir(parents=True, exist_ok=True)
    options = _build_options(
        target, source, dry_run, no_memory, no_glossary, glossary_path
    )
    errors = 0
    for md_file in files:
        rel = md_file.relative_to(path)
        out_file = output_dir / rel.parent / f"{rel.stem}.{target}{rel.suffix}"
        out_file.parent.mkdir(parents=True, exist_ok=True)
        try:
            result = _translate_content(md_file.read_text(encoding="utf-8"), options)
            if dry_run:
                typer.echo(f"{rel}: {len(result.dry_run_segments or [])} segmentos")
            else:
                out_file.write_text(result.content, encoding="utf-8")
                typer.echo(f"✓ {rel}")
        except typer.Exit:
            errors += 1
    if errors:
        raise typer.Exit(1)


@app.command("batch")
def batch_cmd(
    paths: list[Path] = typer.Argument(..., exists=True),
    target: str = typer.Option(..., "--target", "-t"),
    source: str = typer.Option("auto", "--source", "-s"),
    zip_path: Path | None = typer.Option(None, "--zip"),
    output_dir: Path | None = typer.Option(None, "--output-dir"),
    dry_run: bool = typer.Option(False, "--dry-run"),
    no_memory: bool = typer.Option(False, "--no-memory"),
    no_glossary: bool = typer.Option(False, "--no-glossary"),
    glossary_path: Path | None = typer.Option(None, "--glossary-path"),
) -> None:
    """Traduce varios archivos a ZIP o directorio."""
    if bool(zip_path) == bool(output_dir):
        _exit_config("Indica exactamente uno: --zip o --output-dir")

    md_files: list[Path] = []
    for p in paths:
        if p.is_file() and _is_markdown(p):
            md_files.append(p)
        elif p.is_dir():
            md_files.extend(
                sorted(f for f in p.rglob("*") if f.is_file() and _is_markdown(f))
            )
    if not md_files:
        _exit_config("No hay archivos Markdown válidos")

    options = _build_options(
        target, source, dry_run, no_memory, no_glossary, glossary_path
    )
    errors = 0

    if zip_path:
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for md_file in md_files:
                try:
                    result = _translate_content(
                        md_file.read_text(encoding="utf-8"), options
                    )
                    if not dry_run:
                        name = f"{md_file.stem}.{target}{md_file.suffix}"
                        zf.writestr(name, result.content.encode("utf-8"))
                except typer.Exit:
                    errors += 1
        if not dry_run:
            typer.echo(f"ZIP → {zip_path}")
    else:
        assert output_dir is not None
        output_dir.mkdir(parents=True, exist_ok=True)
        for md_file in md_files:
            out = output_dir / f"{md_file.stem}.{target}{md_file.suffix}"
            try:
                result = _translate_content(
                    md_file.read_text(encoding="utf-8"), options
                )
                if not dry_run:
                    out.write_text(result.content, encoding="utf-8")
            except typer.Exit:
                errors += 1

    if errors:
        raise typer.Exit(1)


if __name__ == "__main__":
    app()
