"""API FastAPI para traducción de archivos Markdown."""

from __future__ import annotations

import asyncio
import io
import json
import logging
import os
import uuid
import zipfile
from functools import partial
from pathlib import Path

from dotenv import load_dotenv
from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .deployment import (
    check_upload_limits,
    get_cors_origins,
    output_sweep_interval_hours,
    output_ttl_hours,
    sweep_output_dir,
    verify_api_token_auth,
)
from .estimate import EstimateResult, estimate_files, estimate_markdown
from .glossary import glossary_from_dict, glossary_to_dict, load_glossary, save_glossary
from .jobs import JobState, cancel_job, create_batch_job, get_job, start_batch_job
from .memory import TranslationMemory, default_memory_path
from .pipeline import DEFAULT_GLOSSARY_PATH, TranslateOptions, translate_markdown
from .review import build_draft, finalize_draft
from .target_langs import (
    out_name_for_lang,
    parse_target_langs,
    validate_target_langs_http,
    validation_sidecar_name,
)
from .translator import (
    IncompleteTranslationError,
    get_supported_languages,
    is_valid_source_lang,
)
from .validator import validation_to_dict

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
    allow_origins=get_cors_origins(),
    allow_methods=["*"],
    allow_headers=["*"],
)

if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


class TranslateTextRequest(BaseModel):
    content: str
    target_lang: str | None = None
    target_langs: list[str] | None = None
    source_lang: str = "auto"
    tone: str = "auto"


class DraftSegmentModel(BaseModel):
    index: int
    original: str
    translated: str
    doubtful: bool


class DraftResponse(BaseModel):
    content: str
    segments: list[DraftSegmentModel]
    segments_total: int
    segments_translated: int
    validation: ValidationReportModel | None = None
    provider_used: str | None = None


class FinalizeRequest(BaseModel):
    content: str
    segments: dict[int, str]
    source_lang: str = "auto"
    tone: str = "auto"


class MultiTranslateResponse(BaseModel):
    translations: dict[str, TranslateResponse]


class ValidationCheckModel(BaseModel):
    id: str
    status: str
    message: str
    expected: int | None = None
    actual: int | None = None


class ValidationReportModel(BaseModel):
    overall: str
    checks: list[ValidationCheckModel]


class TranslateResponse(BaseModel):
    content: str
    segments_total: int
    segments_translated: int
    validation: ValidationReportModel | None = None
    provider_used: str | None = None


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


class EstimateRequest(BaseModel):
    content: str | None = None
    target_lang: str | None = None
    target_langs: list[str] | None = None
    source_lang: str = "auto"


class EstimateResponse(BaseModel):
    segments: int
    characters: int
    estimated_cost_usd: float
    provider: str
    model: str
    exceeds_threshold: bool
    threshold_usd: float
    language_count: int = 1


class BatchJobCreateResponse(BaseModel):
    job_id: str


class BatchJobCancelResponse(BaseModel):
    cancelled: bool


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


def _require_api_token(
    authorization: str | None = Header(default=None),
    access_token: str | None = Query(default=None),
) -> None:
    if not verify_api_token_auth(authorization, access_token):
        raise HTTPException(401, "No autorizado")


def _resolve_target_langs(
    target_lang: str | None,
    target_langs: list[str] | None,
) -> list[str]:
    try:
        langs = parse_target_langs(target_lang, target_langs)
    except ValueError as e:
        raise HTTPException(400, str(e)) from e
    validate_target_langs_http(langs)
    return langs


def _langs_from_form(form) -> list[str]:
    target_lang = form.get("target_lang")
    tl = target_lang if isinstance(target_lang, str) else None
    multi: list[str] = []
    for key, value in form.multi_items():
        if key == "target_langs" and isinstance(value, str):
            multi.append(value)
    return _resolve_target_langs(tl, multi or None)


def _validate_languages_http(source_lang: str) -> None:
    if source_lang != "auto" and not is_valid_source_lang(source_lang):
        raise HTTPException(
            400,
            f"Idioma origen no soportado por el proveedor activo: {source_lang}",
        )


def _validation_model(result) -> ValidationReportModel | None:
    if result.validation is None:
        return None
    data = validation_to_dict(result.validation)
    return ValidationReportModel.model_validate(data)


async def _translate_content(
    content: str,
    target_lang: str,
    source_lang: str,
    tone: str = "auto",
):
    source = None if source_lang == "auto" else source_lang
    options = TranslateOptions(
        target_lang=target_lang,
        source_lang=source,
        tone=tone,
    )
    loop = asyncio.get_running_loop()
    try:
        return await loop.run_in_executor(
            None,
            partial(translate_markdown, content, options),
        )
    except IncompleteTranslationError:
        raise
    except ValueError as e:
        raise HTTPException(400, str(e)) from e


def _to_response(result) -> TranslateResponse:
    return TranslateResponse(
        content=result.content,
        segments_total=result.segments_total,
        segments_translated=result.segments_translated,
        validation=_validation_model(result),
        provider_used=getattr(result, "provider_used", None),
    )


def _estimate_response(result: EstimateResult) -> EstimateResponse:
    return EstimateResponse(
        segments=result.segments,
        characters=result.characters,
        estimated_cost_usd=result.estimated_cost_usd,
        provider=result.provider,
        model=result.model,
        exceeds_threshold=result.exceeds_threshold,
        threshold_usd=result.threshold_usd,
        language_count=result.language_count,
    )


async def _decode_batch_uploads(
    files: list[UploadFile],
) -> list[tuple[str, str]]:
    if not files:
        raise HTTPException(400, "No se enviaron archivos")
    if len(files) > 20:
        raise HTTPException(400, "Máximo 20 archivos por lote")
    entries: list[tuple[str, str]] = []
    batch_bytes = 0
    for upload in files:
        if not upload.filename:
            continue
        if not upload.filename.lower().endswith((".md", ".markdown", ".mdx")):
            raise HTTPException(
                400,
                f"Formato no válido: {upload.filename}. Usa .md, .markdown o .mdx",
            )
        raw = await upload.read()
        batch_bytes += len(raw)
        try:
            check_upload_limits(len(raw), batch_bytes)
        except ValueError as e:
            raise HTTPException(400, str(e)) from e
        try:
            content = _decode_upload(raw, upload.filename)
        except ValueError as e:
            raise HTTPException(400, str(e)) from e
        entries.append((upload.filename, content))
    if not entries:
        raise HTTPException(400, "No se procesó ningún archivo válido")
    return entries


async def _run_translate(
    content: str,
    target_lang: str,
    source_lang: str,
    tone: str = "auto",
) -> TranslateResponse:
    result = await _translate_content(content, target_lang, source_lang, tone)
    return _to_response(result)


def _write_zip_entries(
    zf: zipfile.ZipFile,
    filename: str,
    results: list[tuple[str, object]],
    used_names: set[str],
) -> None:
    for lang, result in results:
        out_name = out_name_for_lang(filename, lang, used_names)
        zf.writestr(out_name, result.content.encode("utf-8"))
        if result.validation is not None:
            val_name = validation_sidecar_name(filename, lang)
            zf.writestr(
                val_name,
                json.dumps(
                    validation_to_dict(result.validation),
                    ensure_ascii=False,
                    indent=2,
                ).encode("utf-8"),
            )


@app.on_event("startup")
async def startup_sweep_output():
    deleted = sweep_output_dir(OUTPUT_DIR)
    if deleted:
        logger.info("Limpieza output/: %s archivo(s) eliminado(s)", deleted)

    interval_h = output_sweep_interval_hours()
    if interval_h <= 0:
        return

    async def periodic_sweep():
        while True:
            await asyncio.sleep(interval_h * 3600)
            sweep_output_dir(OUTPUT_DIR)

    asyncio.create_task(periodic_sweep())


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


@app.post("/api/translate")
async def translate_text(
    body: TranslateTextRequest,
    _: None = Depends(_require_api_token),
):
    if not body.content.strip():
        raise HTTPException(400, "El contenido está vacío")
    langs = _resolve_target_langs(body.target_lang, body.target_langs)
    _validate_languages_http(body.source_lang)

    if len(langs) == 1:
        try:
            return await _run_translate(
                body.content, langs[0], body.source_lang, body.tone
            )
        except IncompleteTranslationError as e:
            raise _translation_http_exception(e) from e
        except RuntimeError as e:
            raise HTTPException(503, str(e)) from e
        except Exception as e:
            logger.exception("Error traduciendo texto")
            raise HTTPException(502, f"Error de traducción: {e}") from e

    translations: dict[str, TranslateResponse] = {}
    for lang in langs:
        try:
            translations[lang] = await _run_translate(
                body.content, lang, body.source_lang, body.tone
            )
        except IncompleteTranslationError as e:
            raise _translation_http_exception(e) from e
        except RuntimeError as e:
            raise HTTPException(503, str(e)) from e
        except Exception as e:
            logger.exception("Error traduciendo texto (%s)", lang)
            raise HTTPException(502, f"Error de traducción ({lang}): {e}") from e
    return MultiTranslateResponse(translations=translations)


@app.post("/api/translate/draft", response_model=DraftResponse)
async def translate_draft(
    body: TranslateTextRequest,
    _: None = Depends(_require_api_token),
):
    if not body.content.strip():
        raise HTTPException(400, "El contenido está vacío")
    langs = _resolve_target_langs(body.target_lang, body.target_langs)
    if len(langs) != 1:
        raise HTTPException(
            400,
            "El modo revisión requiere un único idioma destino",
        )
    _validate_languages_http(body.source_lang)
    source = None if body.source_lang == "auto" else body.source_lang
    options = TranslateOptions(
        target_lang=langs[0],
        source_lang=source,
        tone=body.tone,
    )
    loop = asyncio.get_running_loop()
    try:
        draft = await loop.run_in_executor(
            None, partial(build_draft, body.content, options)
        )
    except IncompleteTranslationError as e:
        raise _translation_http_exception(e) from e
    except RuntimeError as e:
        raise HTTPException(503, str(e)) from e
    except Exception as e:
        logger.exception("Error en borrador de traducción")
        raise HTTPException(502, f"Error de traducción: {e}") from e
    return DraftResponse(
        content=draft.content,
        segments=[
            DraftSegmentModel(
                index=s.index,
                original=s.original,
                translated=s.translated,
                doubtful=s.doubtful,
            )
            for s in draft.segments
        ],
        segments_total=draft.segments_total,
        segments_translated=draft.segments_translated,
        validation=_validation_model(draft),
        provider_used=draft.provider_used,
    )


@app.post("/api/translate/finalize", response_model=TranslateResponse)
async def translate_finalize(
    body: FinalizeRequest,
    _: None = Depends(_require_api_token),
):
    if not body.content.strip():
        raise HTTPException(400, "El contenido está vacío")
    loop = asyncio.get_running_loop()
    try:
        result = await loop.run_in_executor(
            None,
            partial(finalize_draft, body.content, body.segments),
        )
    except ValueError as e:
        raise HTTPException(400, str(e)) from e
    return _to_response(result)


@app.post("/api/translate/file")
async def translate_file(
    file: UploadFile = File(...),
    target_lang: str | None = Form(None),
    target_langs: list[str] = Form(default=[]),
    source_lang: str = Form("auto"),
    tone: str = Form("auto"),
    _: None = Depends(_require_api_token),
):
    if not file.filename or not file.filename.lower().endswith((".md", ".markdown", ".mdx")):
        raise HTTPException(400, "Solo se aceptan archivos .md, .markdown o .mdx")

    langs = _resolve_target_langs(target_lang, target_langs or None)
    _validate_languages_http(source_lang)

    raw = await file.read()
    try:
        check_upload_limits(len(raw), len(raw))
    except ValueError as e:
        raise HTTPException(400, str(e)) from e
    try:
        content = _decode_upload(raw, file.filename)
    except ValueError as e:
        raise HTTPException(400, str(e)) from e

    if len(langs) == 1:
        lang = langs[0]
        try:
            result = await _translate_content(content, lang, source_lang, tone)
        except IncompleteTranslationError as e:
            raise _translation_http_exception(e) from e
        except RuntimeError as e:
            raise HTTPException(503, str(e)) from e
        except Exception as e:
            logger.exception("Error traduciendo archivo %s", file.filename)
            raise HTTPException(502, f"Error de traducción: {e}") from e

        out_name = out_name_for_lang(file.filename, lang, set())
        out_path = OUTPUT_DIR / f"{uuid.uuid4().hex}_{out_name}"
        out_path.write_text(result.content, encoding="utf-8")

        headers = {
            "Content-Disposition": f'attachment; filename="{out_name}"',
        }
        if result.validation is not None:
            headers["X-Validation-Report"] = json.dumps(
                validation_to_dict(result.validation),
                ensure_ascii=True,
            )

        return FileResponse(
            path=out_path,
            filename=out_name,
            media_type="text/markdown; charset=utf-8",
            headers=headers,
        )

    zip_buffer = io.BytesIO()
    used_names: set[str] = set()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        file_results: list[tuple[str, object]] = []
        for lang in langs:
            try:
                result = await _translate_content(content, lang, source_lang, tone)
            except IncompleteTranslationError as e:
                raise _translation_http_exception(e) from e
            except RuntimeError as e:
                raise HTTPException(503, str(e)) from e
            except Exception as e:
                logger.exception(
                    "Error traduciendo archivo %s (%s)", file.filename, lang
                )
                raise HTTPException(
                    502, f"Error de traducción ({lang}): {e}"
                ) from e
            file_results.append((lang, result))
        _write_zip_entries(zf, file.filename, file_results, used_names)

    stem = Path(file.filename).stem or "documento"
    zip_buffer.seek(0)
    return StreamingResponse(
        zip_buffer,
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{stem}.zip"',
        },
    )


@app.post("/api/translate/estimate", response_model=EstimateResponse)
async def translate_estimate(request: Request):
    """Estima segmentos, caracteres y coste antes de traducir."""
    content_type = request.headers.get("content-type", "")

    if content_type.startswith("multipart/form-data"):
        form = await request.form()
        source_lang = form.get("source_lang", "auto")
        if not isinstance(source_lang, str):
            source_lang = "auto"
        langs = _langs_from_form(form)
        _validate_languages_http(source_lang)

        uploads: list[UploadFile] = []
        for key, value in form.multi_items():
            if key == "files" and hasattr(value, "read"):
                uploads.append(value)  # type: ignore[arg-type]

        if not uploads:
            raise HTTPException(400, "No se enviaron archivos")
        entries = await _decode_batch_uploads(uploads)
        contents = [content for _, content in entries]
        loop = asyncio.get_running_loop()
        result = await loop.run_in_executor(
            None,
            partial(
                estimate_files,
                contents,
                target_lang=langs[0],
                target_langs=langs if len(langs) > 1 else None,
                source_lang=source_lang,
            ),
        )
        return _estimate_response(result)

    try:
        payload = await request.json()
    except Exception as e:
        raise HTTPException(400, "JSON inválido") from e

    body = EstimateRequest.model_validate(payload)
    if not body.content or not body.content.strip():
        raise HTTPException(400, "El contenido está vacío")
    langs = _resolve_target_langs(body.target_lang, body.target_langs)
    _validate_languages_http(body.source_lang)
    loop = asyncio.get_running_loop()
    if len(langs) == 1:
        result = await loop.run_in_executor(
            None,
            partial(
                estimate_markdown,
                body.content,
                target_lang=langs[0],
                source_lang=body.source_lang,
            ),
        )
    else:
        result = await loop.run_in_executor(
            None,
            partial(
                estimate_files,
                [body.content],
                target_lang=langs[0],
                target_langs=langs,
                source_lang=body.source_lang,
            ),
        )
    return _estimate_response(result)


@app.post("/api/translate/batch/jobs", response_model=BatchJobCreateResponse)
async def create_batch_translation_job(
    background_tasks: BackgroundTasks,
    files: list[UploadFile] = File(...),
    target_lang: str | None = Form(None),
    target_langs: list[str] = Form(default=[]),
    source_lang: str = Form("auto"),
    tone: str = Form("auto"),
    _: None = Depends(_require_api_token),
):
    langs = _resolve_target_langs(target_lang, target_langs or None)
    _validate_languages_http(source_lang)
    entries = await _decode_batch_uploads(files)
    job_id = await create_batch_job(
        entries,
        target_langs=langs,
        source_lang=source_lang,
        tone=tone,
        start=False,
    )
    background_tasks.add_task(start_batch_job, job_id)
    return BatchJobCreateResponse(job_id=job_id)


async def _job_event_stream(job_id: str):
    job = get_job(job_id)
    if job is None:
        raise HTTPException(404, "Job no encontrado")
    while True:
        event = await job.event_queue.get()
        yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
        if event.get("type") == "complete":
            break


@app.get("/api/translate/batch/jobs/{job_id}/events")
async def batch_job_events(
    job_id: str,
    _: None = Depends(_require_api_token),
):
    if get_job(job_id) is None:
        raise HTTPException(404, "Job no encontrado")
    return StreamingResponse(
        _job_event_stream(job_id),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        },
    )


@app.delete(
    "/api/translate/batch/jobs/{job_id}",
    response_model=BatchJobCancelResponse,
)
async def cancel_batch_translation_job(
    job_id: str,
    _: None = Depends(_require_api_token),
):
    if not cancel_job(job_id):
        raise HTTPException(404, "Job no encontrado")
    return BatchJobCancelResponse(cancelled=True)


@app.get("/api/translate/batch/jobs/{job_id}/download")
async def download_batch_translation_job(
    job_id: str,
    _: None = Depends(_require_api_token),
):
    job = get_job(job_id)
    if job is None:
        raise HTTPException(404, "Job no encontrado")
    if job.zip_bytes is None:
        raise HTTPException(404, "ZIP aún no disponible")
    if job.state not in (JobState.COMPLETED, JobState.CANCELLED):
        raise HTTPException(409, "El job aún está en curso")
    return StreamingResponse(
        io.BytesIO(job.zip_bytes),
        media_type="application/zip",
        headers={"Content-Disposition": 'attachment; filename="traducciones.zip"'},
    )


@app.post("/api/translate/batch")
async def translate_batch(
    files: list[UploadFile] = File(...),
    target_lang: str | None = Form(None),
    target_langs: list[str] = Form(default=[]),
    source_lang: str = Form("auto"),
    tone: str = Form("auto"),
    _: None = Depends(_require_api_token),
):
    langs = _resolve_target_langs(target_lang, target_langs or None)
    _validate_languages_http(source_lang)
    entries = await _decode_batch_uploads(files)

    zip_buffer = io.BytesIO()
    used_names: set[str] = set()
    translated_count = 0

    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for filename, content in entries:
            file_results: list[tuple[str, object]] = []
            for lang in langs:
                try:
                    result = await _translate_content(content, lang, source_lang, tone)
                except IncompleteTranslationError as e:
                    raise _translation_http_exception(e) from e
                except RuntimeError as e:
                    raise HTTPException(503, str(e)) from e
                except Exception as e:
                    logger.exception(
                        "Error traduciendo lote: %s (%s)", filename, lang
                    )
                    raise HTTPException(
                        502, f"Error traduciendo {filename} ({lang}): {e}"
                    ) from e
                file_results.append((lang, result))
            _write_zip_entries(zf, filename, file_results, used_names)
            translated_count += len(langs)

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
    port = int(os.getenv("PORT", "5400"))
    uvicorn.run("src.main:app", host=host, port=port, reload=True)


if __name__ == "__main__":
    run()
