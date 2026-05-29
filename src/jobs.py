"""Jobs de traducción por lote con SSE in-memory (single-process)."""

from __future__ import annotations

import asyncio
import uuid
from dataclasses import dataclass, field
from enum import Enum
from functools import partial

from .batch_zip import BatchFileError, BatchFileSuccess, build_batch_zip
from .pipeline import TranslateOptions, translate_markdown
from .target_langs import out_name_for_lang, validation_sidecar_name

_jobs: dict[str, BatchJob] = {}
_lock = asyncio.Lock()


class JobState(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


@dataclass
class BatchJob:
    id: str
    state: JobState
    target_langs: list[str]
    source_lang: str
    file_entries: list[tuple[str, str]]
    cancel_requested: bool = False
    successes: list[BatchFileSuccess] = field(default_factory=list)
    errors: list[BatchFileError] = field(default_factory=list)
    event_queue: asyncio.Queue = field(default_factory=asyncio.Queue)
    zip_bytes: bytes | None = None
    task: asyncio.Task | None = None


async def _emit(job: BatchJob, event: dict) -> None:
    await job.event_queue.put(event)


async def _run_job(job: BatchJob) -> None:
    job.state = JobState.RUNNING
    loop = asyncio.get_running_loop()
    total_files = len(job.file_entries)
    total_langs = len(job.target_langs)
    used_names: set[str] = set()

    for file_index, (filename, content) in enumerate(job.file_entries):
        if job.cancel_requested:
            job.errors.append(
                BatchFileError(
                    filename,
                    "Cancelado: job cancelado por el usuario",
                )
            )
            break

        for lang_index, lang in enumerate(job.target_langs):
            if job.cancel_requested:
                break

            await _emit(
                job,
                {
                    "type": "file_start",
                    "filename": filename,
                    "file_index": file_index,
                    "total_files": total_files,
                    "target_lang": lang,
                    "lang_index": lang_index,
                    "total_langs": total_langs,
                },
            )

            def make_progress_callback(fname: str, target: str):
                def callback(done: int, total: int) -> None:
                    asyncio.run_coroutine_threadsafe(
                        _emit(
                            job,
                            {
                                "type": "segment_progress",
                                "filename": fname,
                                "target_lang": target,
                                "done": done,
                                "total": total,
                            },
                        ),
                        loop,
                    )

                return callback

            source = None if job.source_lang == "auto" else job.source_lang
            options = TranslateOptions(
                target_lang=lang,
                source_lang=source,
                on_progress=make_progress_callback(filename, lang),
            )

            try:
                result = await loop.run_in_executor(
                    None,
                    partial(translate_markdown, content, options),
                )
            except Exception as e:
                msg = f"{filename} ({lang}): {e}"
                job.errors.append(BatchFileError(filename, msg))
                await _emit(
                    job,
                    {
                        "type": "error",
                        "filename": filename,
                        "target_lang": lang,
                        "message": str(e),
                    },
                )
                continue

            out_name = out_name_for_lang(filename, lang, used_names)
            job.successes.append(
                BatchFileSuccess(
                    filename=filename,
                    out_name=out_name,
                    content=result.content,
                    validation=result.validation,
                    validation_name=validation_sidecar_name(filename, lang),
                )
            )
            await _emit(
                job,
                {
                    "type": "file_done",
                    "filename": filename,
                    "target_lang": lang,
                    "out_name": out_name,
                },
            )

        if job.cancel_requested:
            break

    job.zip_bytes = build_batch_zip(job.successes, job.errors)
    job.state = (
        JobState.CANCELLED if job.cancel_requested else JobState.COMPLETED
    )
    await _emit(
        job,
        {
            "type": "complete",
            "ok_count": len(job.successes),
            "error_count": len(job.errors),
            "total_files": total_files,
            "total_langs": total_langs,
            "cancelled": job.cancel_requested,
        },
    )


async def create_batch_job(
    file_entries: list[tuple[str, str]],
    *,
    target_langs: list[str],
    source_lang: str = "auto",
    start: bool = True,
) -> str:
    job_id = uuid.uuid4().hex
    job = BatchJob(
        id=job_id,
        state=JobState.PENDING,
        target_langs=target_langs,
        source_lang=source_lang,
        file_entries=file_entries,
    )
    async with _lock:
        _jobs[job_id] = job
    if start:
        job.task = asyncio.create_task(_run_job(job))
    return job_id


async def start_batch_job(job_id: str) -> None:
    job = _jobs.get(job_id)
    if job is None:
        raise ValueError(f"Job no encontrado: {job_id}")
    if job.task is None:
        job.task = asyncio.current_task()
    await _run_job(job)


def get_job(job_id: str) -> BatchJob | None:
    return _jobs.get(job_id)


def cancel_job(job_id: str) -> bool:
    job = _jobs.get(job_id)
    if job is None:
        return False
    job.cancel_requested = True
    return True
