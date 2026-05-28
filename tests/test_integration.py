"""Tests de integración del pipeline segment → translate → reassemble."""

from __future__ import annotations

from fastapi.testclient import TestClient

from src.parser import collect_translatable, reassemble, segment_markdown


def test_pipeline_segment_translate_reassemble(mock_translate_success):
    md = "# Hello\n\n```bash\nnpm install\n```\n\nWorld line\n"
    segments = segment_markdown(md)
    translatable = collect_translatable(segments)
    indices = [idx for idx, _ in translatable]

    translations = mock_translate_success(translatable, "es")
    assert len(translations) == len(translatable)
    assert set(translations.keys()) == set(indices)

    out = reassemble(segments, translations)
    assert "```bash" in out
    assert "npm install" in out
    assert "TR:" in out
    assert out.count("TR:") == len(translatable)


def test_api_translate_text_integration(client: TestClient, mock_translate_success):
    res = client.post(
        "/api/translate",
        json={
            "content": "# Title\n\nParagraph.\n",
            "target_lang": "es",
            "source_lang": "auto",
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert data["segments_total"] >= data["segments_translated"] >= 1
    assert "TR:" in data["content"]
