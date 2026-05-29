"""CLI Typer: md-translate file|dir|batch|serve|memory."""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

import typer
from dotenv import load_dotenv

from .gitignore_filter import iter_markdown_files
from .html_export import markdown_to_html
from .memory import TranslationMemory, default_memory_path
from .pipeline import TranslateOptions, translate_markdown
from .target_langs import out_name_for_lang, validation_sidecar_name
from .translator import (
    IncompleteTranslationError,
    is_valid_source_lang,
    is_valid_target_lang,
)
from .validator import validation_to_dict

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


def _parse_targets(target: str) -> list[str]:
    raw = [t.strip() for t in target.split(",") if t.strip()]
    if not raw:
        _exit_config("Se requiere al menos un idioma destino")
    seen: set[str] = set()
    langs: list[str] = []
    for code in raw:
        if code in seen:
            continue
        if not is_valid_target_lang(code):
            _exit_config(f"Idioma destino no soportado: {code}")
        seen.add(code)
        langs.append(code)
    return langs


def _build_options(
    target: str,
    source: str,
    dry_run: bool,
    no_memory: bool,
    no_glossary: bool,
    glossary_path: Path | None,
    tone: str = "auto",
) -> TranslateOptions:
    if not is_valid_target_lang(target):
        _exit_config(f"Idioma destino no soportado: {target}")
    if source != "auto" and not is_valid_source_lang(source):
        _exit_config(f"Idioma origen no soportado: {source}")
    if tone not in ("auto", "formal", "informal"):
        _exit_config("Tono debe ser auto, formal o informal")
    return TranslateOptions(
        target_lang=target,
        source_lang=None if source == "auto" else source,
        dry_run=dry_run,
        use_memory=not no_memory,
        use_glossary=not no_glossary,
        glossary_path=glossary_path,
        tone=tone,
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


def _strict_validation_failed(result, strict: bool) -> bool:
    if not strict:
        return False
    if result.validation is None:
        return False
    return result.validation.overall == "error"


def _abort_strict() -> None:
    typer.secho(
        "Validación fallida — salida no escrita",
        fg=typer.colors.RED,
        err=True,
    )
    raise typer.Exit(code=1)


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
    target: str = typer.Option(..., "--target", "-t", help="Idioma destino (es o es,en,fr)"),
    output: Path | None = typer.Option(None, "--output", "-o", help="Archivo salida"),
    source: str = typer.Option("auto", "--source", "-s", help="Idioma origen"),
    dry_run: bool = typer.Option(False, "--dry-run", help="Listar segmentos sin traducir"),
    no_memory: bool = typer.Option(False, "--no-memory"),
    no_glossary: bool = typer.Option(False, "--no-glossary"),
    glossary_path: Path | None = typer.Option(None, "--glossary-path"),
    strict: bool = typer.Option(False, "--strict"),
    tone: str = typer.Option("auto", "--tone", help="auto|formal|informal"),
) -> None:
    """Traduce un archivo Markdown."""
    targets = _parse_targets(target)
    if len(targets) > 1 and output is not None:
        _exit_config("Usa --output solo con un único idioma destino")

    content = input_path.read_text(encoding="utf-8")
    written = 0
    for lang in targets:
        options = _build_options(
            lang, source, dry_run, no_memory, no_glossary, glossary_path, tone
        )
        result = _translate_content(content, options)

        if dry_run:
            for idx, text in result.dry_run_segments or []:
                typer.echo(
                    json.dumps(
                        {"index": idx, "text": text, "target_lang": lang},
                        ensure_ascii=False,
                    )
                )
            continue

        if _strict_validation_failed(result, strict):
            _abort_strict()

        out_path = output or input_path.with_name(
            f"{input_path.stem}.{lang}{input_path.suffix or '.md'}"
        )
        out_path.write_text(result.content, encoding="utf-8")
        typer.echo(f"Traducido ({lang}) → {out_path}")
        written += 1

    if not dry_run and written == 0:
        _exit_config("No se generó ninguna salida")


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
    strict: bool = typer.Option(False, "--strict"),
    tone: str = typer.Option("auto", "--tone"),
    respect_gitignore: bool = typer.Option(
        True,
        "--respect-gitignore/--no-respect-gitignore",
        help="Omitir rutas en .gitignore",
    ),
) -> None:
    """Traduce archivos .md en un directorio."""
    files = iter_markdown_files(
        path, recursive=recursive, respect_gitignore=respect_gitignore
    )
    if not files:
        _exit_config("No se encontraron archivos Markdown")

    output_dir.mkdir(parents=True, exist_ok=True)
    targets = _parse_targets(target)
    errors = 0
    for md_file in files:
        rel = md_file.relative_to(path)
        content = md_file.read_text(encoding="utf-8")
        for lang in targets:
            options = _build_options(
                lang, source, dry_run, no_memory, no_glossary, glossary_path, tone
            )
            out_file = output_dir / rel.parent / f"{rel.stem}.{lang}{rel.suffix}"
            out_file.parent.mkdir(parents=True, exist_ok=True)
            try:
                result = _translate_content(content, options)
                if dry_run:
                    typer.echo(
                        f"{rel} ({lang}): {len(result.dry_run_segments or [])} segmentos"
                    )
                elif _strict_validation_failed(result, strict):
                    typer.secho(
                        f"✗ {rel} ({lang}) (validación fallida)",
                        fg=typer.colors.RED,
                        err=True,
                    )
                    errors += 1
                else:
                    out_file.write_text(result.content, encoding="utf-8")
                    typer.echo(f"✓ {rel} ({lang})")
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
    strict: bool = typer.Option(False, "--strict"),
    tone: str = typer.Option("auto", "--tone"),
    respect_gitignore: bool = typer.Option(True, "--respect-gitignore/--no-respect-gitignore"),
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
                iter_markdown_files(p, recursive=True, respect_gitignore=respect_gitignore)
            )
    if not md_files:
        _exit_config("No hay archivos Markdown válidos")

    targets = _parse_targets(target)
    errors = 0
    used_names: set[str] = set()

    if zip_path:
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for md_file in md_files:
                content = md_file.read_text(encoding="utf-8")
                for lang in targets:
                    options = _build_options(
                        lang, source, dry_run, no_memory, no_glossary, glossary_path, tone
                    )
                    try:
                        result = _translate_content(content, options)
                        if dry_run:
                            continue
                        if _strict_validation_failed(result, strict):
                            errors += 1
                            continue
                        name = out_name_for_lang(md_file.name, lang, used_names)
                        zf.writestr(name, result.content.encode("utf-8"))
                        if result.validation is not None:
                            val_name = validation_sidecar_name(md_file.name, lang)
                            zf.writestr(
                                val_name,
                                json.dumps(
                                    validation_to_dict(result.validation),
                                    ensure_ascii=False,
                                    indent=2,
                                ).encode("utf-8"),
                            )
                    except typer.Exit:
                        errors += 1
        if not dry_run:
            typer.echo(f"ZIP → {zip_path}")
    else:
        assert output_dir is not None
        output_dir.mkdir(parents=True, exist_ok=True)
        for md_file in md_files:
            content = md_file.read_text(encoding="utf-8")
            for lang in targets:
                options = _build_options(
                    lang, source, dry_run, no_memory, no_glossary, glossary_path, tone
                )
                out = output_dir / f"{md_file.stem}.{lang}{md_file.suffix}"
                try:
                    result = _translate_content(content, options)
                    if dry_run:
                        continue
                    if _strict_validation_failed(result, strict):
                        errors += 1
                        continue
                    out.write_text(result.content, encoding="utf-8")
                except typer.Exit:
                    errors += 1

    if errors:
        raise typer.Exit(1)


@app.command("export")
def export_cmd(
    input_path: Path = typer.Argument(..., exists=True, readable=True),
    output: Path = typer.Option(..., "--output", "-o", help="Archivo .html salida"),
) -> None:
    """Exporta Markdown a HTML autocontenido."""
    content = input_path.read_text(encoding="utf-8")
    html = markdown_to_html(content, title=input_path.stem)
    output.write_text(html, encoding="utf-8")
    typer.echo(f"HTML → {output}")


@app.command("watch")
def watch_cmd(
    input_dir: Path = typer.Argument(..., exists=True, file_okay=False),
    output_dir: Path = typer.Option(..., "--output-dir", "-o"),
    target: str = typer.Option(..., "--target", "-t"),
    source: str = typer.Option("auto", "--source", "-s"),
    tone: str = typer.Option("auto", "--tone"),
    no_memory: bool = typer.Option(False, "--no-memory"),
    no_glossary: bool = typer.Option(False, "--no-glossary"),
    glossary_path: Path | None = typer.Option(None, "--glossary-path"),
) -> None:
    """Vigila una carpeta y traduce .md al guardar (debounce 2s)."""
    try:
        from watchdog.events import FileSystemEventHandler
        from watchdog.observers import Observer
    except ImportError:
        _exit_config("Instala watchdog: pip install watchdog")

    import threading

    output_dir.mkdir(parents=True, exist_ok=True)
    targets = _parse_targets(target)
    debounce_sec = 2.0
    timers: dict[str, threading.Timer] = {}
    lock = threading.Lock()

    def translate_path(md_path: Path) -> None:
        if not md_path.is_file() or not _is_markdown(md_path):
            return
        content = md_path.read_text(encoding="utf-8")
        for lang in targets:
            options = _build_options(
                lang, source, False, no_memory, no_glossary, glossary_path, tone
            )
            try:
                result = _translate_content(content, options)
            except typer.Exit:
                typer.secho(f"✗ {md_path.name} ({lang})", fg=typer.colors.RED, err=True)
                continue
            out = output_dir / f"{md_path.stem}.{lang}{md_path.suffix}"
            out.write_text(result.content, encoding="utf-8")
            typer.echo(f"✓ {md_path.name} → {out.name}")

    def schedule(path: Path) -> None:
        key = str(path.resolve())

        def run() -> None:
            with lock:
                timers.pop(key, None)
            translate_path(path)

        with lock:
            old = timers.pop(key, None)
            if old:
                old.cancel()
            timers[key] = threading.Timer(debounce_sec, run)
            timers[key].daemon = True
            timers[key].start()

    class Handler(FileSystemEventHandler):
        def on_modified(self, event):  # type: ignore[override]
            if event.is_directory:
                return
            schedule(Path(event.src_path))

        def on_created(self, event):  # type: ignore[override]
            if event.is_directory:
                return
            schedule(Path(event.src_path))

    observer = Observer()
    observer.schedule(Handler(), str(input_dir), recursive=True)
    observer.start()
    typer.echo(f"Vigilando {input_dir} → {output_dir} (Ctrl+C para salir)")
    try:
        observer.join()
    except KeyboardInterrupt:
        observer.stop()
        observer.join()
        typer.echo("Detenido.")


if __name__ == "__main__":
    app()
