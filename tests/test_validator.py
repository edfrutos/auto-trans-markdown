"""Tests del validador post-traducción."""

from src.validator import validate_translation, validation_to_dict


def test_identical_structure_passes():
    md = "# Title\n\n[link](https://x.com)\n\n`code`\n\n```py\nx=1\n```\n"
    report = validate_translation(md, md)
    assert report.overall == "pass"
    assert all(c.status == "pass" for c in report.checks)


def test_extra_fence_errors():
    orig = "# Hi\n\n```\na\n```\n"
    trans = "# Hi\n\n```\na\n```\n\n```\n"
    report = validate_translation(orig, trans)
    fences = next(c for c in report.checks if c.id == "fences")
    assert fences.status == "error"
    assert report.overall == "error"


def test_missing_link_errors():
    orig = "See [docs](https://example.com).\n"
    trans = "See docs.\n"
    report = validate_translation(orig, trans)
    links = next(c for c in report.checks if c.id == "links")
    assert links.status == "error"


def test_missing_image_errors():
    orig = "![alt](img.png)\n"
    trans = "alt\n"
    report = validate_translation(orig, trans)
    images = next(c for c in report.checks if c.id == "images")
    assert images.status == "error"


def test_inline_code_mismatch():
    orig = "Use `API_KEY` here.\n"
    trans = "Use API_KEY here.\n"
    report = validate_translation(orig, trans)
    inline = next(c for c in report.checks if c.id == "inline_code")
    assert inline.status == "error"


def test_heading_depth_mismatch():
    orig = "## Section\n\n### Sub\n"
    trans = "# Section\n\n## Sub\n"
    report = validate_translation(orig, trans)
    headings = next(c for c in report.checks if c.id == "headings")
    assert headings.status == "error"


def test_hash_in_fence_ignored_for_headings():
    orig = "# Title\n\n```python\n# not a heading\n```\n"
    trans = "# Title\n\n```python\n# not a heading\n```\n"
    report = validate_translation(orig, trans)
    headings = next(c for c in report.checks if c.id == "headings")
    assert headings.status == "pass"


def test_validation_to_dict_serializable():
    report = validate_translation("# A\n", "# A\n")
    data = validation_to_dict(report)
    assert data["overall"] == "pass"
    assert isinstance(data["checks"], list)
    assert data["checks"][0]["id"] == "fences"
