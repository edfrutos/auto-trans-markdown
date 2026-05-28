"""Tests del segmentador Markdown."""

from src.parser import (
    SegmentKind,
    collect_translatable,
    reassemble,
    segment_markdown,
)


def test_preserves_code_fence():
    md = "# Title\n\n```python\nprint('hello')\n```\n\nSome text.\n"
    segments = segment_markdown(md)
    protected_text = "".join(s.text for s in segments if s.kind == SegmentKind.PROTECTED)
    assert "print('hello')" in protected_text
    assert "```python" in protected_text
    translatable = collect_translatable(segments)
    texts = [t for _, t in translatable]
    assert any("Title" in t for t in texts)
    assert any("Some text" in t for t in texts)
    assert not any("print" in t for t in texts)


def test_preserves_inline_code():
    md = "Use the `API_KEY` variable here.\n"
    segments = segment_markdown(md)
    assert any(s.kind == SegmentKind.PROTECTED and "API_KEY" in s.text for s in segments)
    assert any(s.kind == SegmentKind.TRANSLATABLE and "Use the" in s.text for s in segments)


def test_reassemble_with_translation():
    md = "# Hello\n\nWorld\n"
    segments = segment_markdown(md)
    translatable = collect_translatable(segments)
    translations = {
        idx: text.replace("Hello", "Hola").replace("World", "Mundo")
        for idx, text in translatable
    }
    out = reassemble(segments, translations)
    assert "# Hola" in out
    assert "Mundo" in out


def test_no_duplicate_blank_lines():
    md = "# Hello\n\nWorld line\n\nAnother para\n"
    segments = segment_markdown(md)
    indices = [s.index for s in segments if s.kind == SegmentKind.TRANSLATABLE]
    assert len(indices) == len(set(indices)), "Cada segmento debe tener índice único"

    translations = {idx: f"TX-{idx}" for idx, _ in collect_translatable(segments)}
    out = reassemble(segments, translations)
    assert out.count("TX-") == 3
    assert "\n\n" in out


def test_bash_comments_are_translatable():
    md = "```bash\n# Install dependencies\nnpm install\n```\n"
    segments = segment_markdown(md)
    translatable = [s for s in segments if s.kind == SegmentKind.TRANSLATABLE]
    protected = [s for s in segments if s.kind == SegmentKind.PROTECTED]

    assert any("Install dependencies" in s.text for s in translatable)
    assert any("npm install" in s.text for s in protected)
    assert any(s.text == "# " for s in protected)


def test_bash_comment_translation_reassembly():
    md = "```bash\n# Hello world\n```\n"
    segments = segment_markdown(md)
    translatable = collect_translatable(segments)
    translations = {idx: "Hola mundo\n" for idx, _ in translatable}
    out = reassemble(segments, translations)
    assert "# Hola mundo" in out
    assert "Hello world" not in out
