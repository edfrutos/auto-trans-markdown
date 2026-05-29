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


def test_python_comment_translatable():
    md = "```python\n# Install deps\nprint('x')\n```\n"
    segments = segment_markdown(md)
    translatable = [s.text for s in segments if s.kind == SegmentKind.TRANSLATABLE]
    protected = [s.text for s in segments if s.kind == SegmentKind.PROTECTED]
    assert any("Install deps" in t for t in translatable)
    assert any("print('x')" in t for t in protected)


def test_python_shebang_protected():
    md = "```python\n#!/usr/bin/env python\n# note\n```\n"
    segments = segment_markdown(md)
    protected = "".join(s.text for s in segments if s.kind == SegmentKind.PROTECTED)
    translatable = [s.text for s in segments if s.kind == SegmentKind.TRANSLATABLE]
    assert "#!/usr/bin/env python" in protected
    assert any("note" in t for t in translatable)


def test_javascript_comment_translatable():
    md = "```javascript\n// Setup API\nconst x = 1;\n```\n"
    segments = segment_markdown(md)
    translatable = [s.text for s in segments if s.kind == SegmentKind.TRANSLATABLE]
    assert any("Setup API" in t for t in translatable)


def test_typescript_fence_alias():
    md = "```ts\n// Type hint\nlet n: number;\n```\n"
    segments = segment_markdown(md)
    assert any(
        s.kind == SegmentKind.TRANSLATABLE and "Type hint" in s.text for s in segments
    )


def test_html_comment_translatable():
    md = "```html\n<!-- Page title -->\n<div></div>\n```\n"
    segments = segment_markdown(md)
    translatable = [s.text for s in segments if s.kind == SegmentKind.TRANSLATABLE]
    assert any("Page title" in t for t in translatable)


def test_frontmatter_title_translatable_slug_protected():
    md = "---\ntitle: Hello\nslug: my-post\n---\n\nBody\n"
    segments = segment_markdown(md)
    translatable = [s.text for s in segments if s.kind == SegmentKind.TRANSLATABLE]
    protected = "".join(s.text for s in segments if s.kind == SegmentKind.PROTECTED)
    assert any("Hello" in t for t in translatable)
    assert "slug: my-post" in protected or "my-post" in protected


def test_frontmatter_tags_list_translatable():
    md = "---\ntags:\n  - alpha\n  - beta\n---\n"
    segments = segment_markdown(md)
    translatable = [s.text for s in segments if s.kind == SegmentKind.TRANSLATABLE]
    assert "alpha" in translatable
    assert "beta" in translatable


def test_frontmatter_date_protected():
    md = "---\ntitle: Hi\ndate: 2024-01-01\n---\n"
    segments = segment_markdown(md)
    protected = "".join(s.text for s in segments if s.kind == SegmentKind.PROTECTED)
    assert "2024-01-01" in protected
    translatable = collect_translatable(segments)
    assert any("Hi" in t for _, t in translatable)


def test_invalid_frontmatter_fully_protected():
    md = "---\ntitle: [broken\n---\n"
    segments = segment_markdown(md)
    assert len(segments) == 1
    assert segments[0].kind == SegmentKind.PROTECTED
    assert segments[0].text.startswith("---")


def test_frontmatter_reassembly():
    md = "---\ntitle: Hello\nslug: post\n---\n"
    segments = segment_markdown(md)
    translatable = collect_translatable(segments)
    translations = {idx: "Hola" for idx, text in translatable if "Hello" in text}
    out = reassemble(segments, translations)
    assert "title: Hola" in out or "Hola" in out
    assert "slug: post" in out or "post" in out
