"""Tests del worker de jobs de lote."""

from __future__ import annotations

import asyncio

import pytest

from src.jobs import JobState, cancel_job, create_batch_job, get_job


@pytest.fixture
def mock_translate_fast(monkeypatch):
    def _translate(content, options):
        from src.pipeline import TranslateResult
        from src.validator import validate_translation

        output = f"TR:{content[:20]}"
        return TranslateResult(
            content=output,
            segments_total=1,
            segments_translated=1,
            validation=validate_translation(content, output),
        )

    monkeypatch.setattr("src.jobs.translate_markdown", _translate)
    return _translate


async def _collect_until_complete(job_id: str):
    job = get_job(job_id)
    assert job is not None
    events = []
    while True:
        event = await asyncio.wait_for(job.event_queue.get(), timeout=5)
        events.append(event)
        if event.get("type") == "complete":
            break
    return job, events


def test_full_success_emits_complete(mock_translate_fast):
    async def _run():
        job_id = await create_batch_job(
            [("a.md", "# A\n"), ("b.md", "# B\n")],
            target_langs=["es"],
        )
        job, events = await _collect_until_complete(job_id)
        assert job.state == JobState.COMPLETED
        assert job.zip_bytes is not None
        assert any(e["type"] == "file_done" for e in events)

    asyncio.run(_run())


def test_one_file_raises_continues(mock_translate_fast, monkeypatch):
    call = {"n": 0}

    def _translate(content, options):
        call["n"] += 1
        if call["n"] == 1:
            raise RuntimeError("boom")
        from src.pipeline import TranslateResult

        return TranslateResult(content="ok", segments_total=1, segments_translated=1)

    monkeypatch.setattr("src.jobs.translate_markdown", _translate)

    async def _run():
        job_id = await create_batch_job(
            [("bad.md", "# X\n"), ("good.md", "# Y\n")],
            target_langs=["es"],
        )
        job, _ = await _collect_until_complete(job_id)
        assert len(job.errors) >= 1
        assert len(job.successes) >= 1

    asyncio.run(_run())


def test_cancel_after_first_file(mock_translate_fast, monkeypatch):
    def _slow(content, options):
        from src.pipeline import TranslateResult

        return TranslateResult(content="x", segments_total=1, segments_translated=1)

    monkeypatch.setattr("src.jobs.translate_markdown", _slow)

    async def _run():
        job_id = await create_batch_job(
            [("one.md", "# 1\n"), ("two.md", "# 2\n")],
            target_langs=["es"],
        )
        job = get_job(job_id)
        assert job is not None
        while True:
            event = await asyncio.wait_for(job.event_queue.get(), timeout=5)
            if event.get("type") == "file_done":
                cancel_job(job_id)
            if event.get("type") == "complete":
                break
        assert job.state == JobState.CANCELLED
        assert job.zip_bytes is not None

    asyncio.run(_run())


def test_multi_lang_one_file_two_successes(mock_translate_fast):
    async def _run():
        job_id = await create_batch_job(
            [("doc.md", "# Doc\n")],
            target_langs=["es", "en"],
        )
        job, events = await _collect_until_complete(job_id)
        assert job.state == JobState.COMPLETED
        assert len(job.successes) == 2
        assert job.zip_bytes is not None
        assert any(
            e.get("type") == "file_start" and e.get("target_lang") == "en"
            for e in events
        )
        import zipfile
        import io

        zf = zipfile.ZipFile(io.BytesIO(job.zip_bytes))
        names = zf.namelist()
        assert "doc.es.md" in names
        assert "doc.en.md" in names

    asyncio.run(_run())
