"""API FastAPI para traducción de archivos Markdown."""

from __future__ import annotations

import asyncio
import io
import logging
import os
import uuid
import zipfile
from functools import partial
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .glossary import glossary_from_dict, glossary_to_dict, load_glossary, save_glossary
from .memory import TranslationMemory, default_memory_path
from .pipeline import DEFAULT_GLOSSARY_PATH, TranslateOptions, translate_markdown
from .translator import (
    IncompleteTranslationError,
    get_supported_languages,
    is_valid_source_lang,
    is_valid_target_lang,
)

load_dotenv()
logger = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent.parent
STATIC_DIR = ROOT / "static"
OUTPUT_DIR = ROOT / "output"
DATA_DIR = ROOT / "data"
OUTPUT_DIR.mkdir(exist_ok=True)
DATA_DIR.mkdir(exist_ok=True)

app = FastAPI(
    title="MarkDown Auto Translator",
    description="Traduce archivos Markdown preservando formato y bloques de código",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


class TranslateTextRequest(BaseModel):
    content: str
    target_lang: str
    source_lang: str = "auto"


class TranslateResponse(BaseModel):
    content: str
    segments_total: int
    segments_translated: int


class LanguageItem(BaseModel):
    code: str
    name: str


class ProgressEvent(BaseModel):
    done: int
    total: int


class GlossaryPayload(BaseModel):
    version: int = Field(1, ge=1, le=1)
    do_not_translate: list[str] = Field(default_factory=list)
    pairs: dict[str, dict[str, str]] = Field(default_factory=dict)


def _decode_upload(raw: bytes, filename: str) -> str:
    """Decodifica uploads multipart como UTF-8 estricto (editor JSON usa str nativo)."""
    if not raw:
        raise ValueError(f"{filename}: archivo vacío")
    sample = raw[:4096]
    if b"\x00" in sample:
        raise ValueError(
            f"{filename}: parece un archivo binario, no Markdown de texto"
        )
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as e:
        raise ValueError(
            f"{filename}: el archivo no es UTF-8 válido. "
            "Guarda el archivo con codificación UTF-8 e inténtalo de nuevo."
        ) from e


def _translation_http_exception(exc: IncompleteTranslationError) -> HTTPException:
    return HTTPException(
        502,
        detail={
            "message": (
                f"Traducción incompleta: faltan {len(exc.missing_indices)} "
                f"de {exc.expected} segmentos"
            ),
            "expected": exc.expected,
            "received": exc.received,
            "missing_indices": exc.missing_indices,
        },
    )


def _validate_languages_http(target_lang: str, source_lang: str) -> None:
    if not is_valid_target_lang(target_lang):
        raise HTTPException(
            400,
            f"Idioma destino no soportado por el proveedor activo: {target_lang}",
        )
    if source_lang != "auto" and not is_valid_source_lang(source_lang):
        raise HTTPException(
            400,
            f"Idioma origen no soportado por el proveedor activo: {source_lang}",
        )


def _unique_zip_name(filename: str, target_lang: str, used: set[str]) -> str:
    base = Path(filename).name
    stem = Path(base).stem or "documento"
    suffix = Path(base).suffix or ".md"
    out_name = f"{stem}.{target_lang}{suffix}"
    if out_name not in used:
        used.add(out_name)
        return out_name
    n = 2
    while True:
        candidate = f"{stem}_{n}.{target_lang}{suffix}"
        if candidate not in used:
            used.add(candidate)
            return candidate
        n += 1


async def _run_translate(
    content: str,
    target_lang: str,
    source_lang: str,
) -> TranslateResponse:
    source = None if source_lang == "auto" else source_lang
    options = TranslateOptions(target_lang=target_lang, source_lang=source)
    loop = asyncio.get_running_loop()
    try:
        result = await loop.run_in_executor(
            None,
            partial(translate_markdown, content, options),
        )
    except IncompleteTranslationError:
        raise
    except ValueError as e:
        raise HTTPException(400, str(e)) from e
    return TranslateResponse(
        content=result.content,
        segments_total=result.segments_total,
        segments_translated=result.segments_translated,
    )


@app.get("/")
async def root():
    index = STATIC_DIR / "index.html"
    if index.exists():
        return FileResponse(
            index,
            media_type="text/html; charset=utf-8",
            headers={
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "Pragma": "no-cache",
            },
        )
    return {"message": "MarkDown Auto Translator API", "docs": "/docs"}


@app.get("/api/languages", response_model=list[LanguageItem])
async def list_languages():
    return [
        LanguageItem(code="auto", name="Detectar automáticamente"),
        *[
            LanguageItem(code=k, name=v)
            for k, v in get_supported_languages().items()
        ],
    ]


@app.get("/api/glossary")
async def get_glossary():
    glossary = load_glossary(DEFAULT_GLOSSARY_PATH)
    return glossary_to_dict(glossary)


@app.put("/api/glossary")
async def put_glossary(body: GlossaryPayload):
    try:
        glossary = glossary_from_dict(body.model_dump())
        save_glossary(DEFAULT_GLOSSARY_PATH, glossary)
    except ValueError as e:
        raise HTTPException(400, str(e)) from e
    return glossary_to_dict(glossary)


@app.delete("/api/memory")
async def clear_memory():
    tm = TranslationMemory(default_memory_path())
    deleted = tm.clear()
    return {"deleted": deleted}


@app.post("/api/translate", response_model=TranslateResponse)
async def translate_text(body: TranslateTextRequest):
    if not body.content.strip():
        raise HTTPException(400, "El contenido está vacío")
    _validate_languages_http(body.target_lang, body.source_lang)

    try:
        return await _run_translate(body.content, body.target_lang, body.source_lang)
    except IncompleteTranslationError as e:
        raise _translation_http_exception(e) from e
    except RuntimeError as e:
        raise HTTPException(503, str(e)) from e
    except Exception as e:
        logger.exception("Error traduciendo texto")
        raise HTTPException(502, f"Error de traducción: {e}") from e


@app.post("/api/translate/file")
async def translate_file(
    file: UploadFile = File(...),
    target_lang: str = Form(...),
    source_lang: str = Form("auto"),
):
    if not file.filename or not file.filename.lower().endswith((".md", ".markdown", ".mdx")):
        raise HTTPException(400, "Solo se aceptan archivos .md, .markdown o .mdx")

    _validate_languages_http(target_lang, source_lang)

    raw = await file.read()
    try:
        content = _decode_upload(raw, file.filename)
    except ValueError as e:
        raise HTTPException(400, str(e)) from e

    try:
        response = await _run_translate(content, target_lang, source_lang)
    except IncompleteTranslationError as e:
        raise _translation_http_exception(e) from e
    except RuntimeError as e:
        raise HTTPException(503, str(e)) from e
    except Exception as e:
        logger.exception("Error traduciendo archivo %s", file.filename)
        raise HTTPException(502, f"Error de traducción: {e}") from e

    stem = Path(file.filename).stem
    suffix = Path(file.filename).suffix or ".md"
    out_name = f"{stem}.{target_lang}{suffix}"
    out_path = OUTPUT_DIR / f"{uuid.uuid4().hex}_{out_name}"
    out_path.write_text(response.content, encoding="utf-8")

    return FileResponse(
        path=out_path,
        filename=out_name,
        media_type="text/markdown; charset=utf-8",
    )


@app.post("/api/translate/batch")
async def translate_batch(
    files: list[UploadFile] = File(...),
    target_lang: str = Form(...),
    source_lang: str = Form("auto"),
):
    if not files:
        raise HTTPException(400, "No se enviaron archivos")
    if len(files) > 20:
        raise HTTPException(400, "Máximo 20 archivos por lote")

    _validate_languages_http(target_lang, source_lang)

    zip_buffer = io.BytesIO()
    used_names: set[str] = set()
    translated_count = 0

    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for upload in files:
            if not upload.filename:
                continue
            if not upload.filename.lower().endswith((".md", ".markdown", ".mdx")):
                raise HTTPException(
                    400,
                    f"Formato no válido: {upload.filename}. Usa .md, .markdown o .mdx",
                )

            raw = await upload.read()
            try:
                content = _decode_upload(raw, upload.filename)
            except ValueError as e:
                raise HTTPException(400, str(e)) from e

            try:
                response = await _run_translate(content, target_lang, source_lang)
            except IncompleteTranslationError as e:
                raise _translation_http_exception(e) from e
            except RuntimeError as e:
                raise HTTPException(503, str(e)) from e
            except Exception as e:
                logger.exception("Error traduciendo lote: %s", upload.filename)
                raise HTTPException(
                    502, f"Error traduciendo {upload.filename}: {e}"
                ) from e

            out_name = _unique_zip_name(upload.filename, target_lang, used_names)
            zf.writestr(out_name, response.content.encode("utf-8"))
            translated_count += 1

    if translated_count == 0:
        raise HTTPException(400, "No se procesó ningún archivo válido")

    zip_buffer.seek(0)
    return StreamingResponse(
        zip_buffer,
        media_type="application/zip",
        headers={"Content-Disposition": 'attachment; filename="traducciones.zip"'},
    )


def run():
    import uvicorn

    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s: %(message)s",
    )
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("src.main:app", host=host, port=port, reload=True)


if __name__ == "__main__":
    run()
