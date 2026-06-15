# Phase 2: Trust & QA - Pattern Map

**Mapped:** 2026-05-28
**Files analyzed:** 13 new/modified
**Analogs found:** 11 / 13

## File Classification

| New/Modified File         | Role      | Data Flow                         | Closest Analog                                  | Match Quality                |
| ------------------------- | --------- | --------------------------------- | ----------------------------------------------- | ---------------------------- |
| `src/validator.py`        | utility   | transform                         | `src/glossary.py` + `src/parser.py`             | exact (dataclass API + `re`) |
| `tests/test_validator.py` | test      | transform                         | `tests/test_glossary.py`                        | exact                        |
| `src/parser.py`           | utility   | transform                         | `src/parser.py` (shell comments)                | exact                        |
| `src/pipeline.py`         | service   | batch                             | `src/pipeline.py`                               | exact                        |
| `src/main.py`             | route     | request-response, file-I/O, batch | `src/main.py`                                   | exact                        |
| `src/cli.py`              | route     | file-I/O, batch                   | `src/cli.py`                                    | exact                        |
| `static/js/app.js`        | component | request-response                  | `static/js/app.js` (glosario + translate)       | exact                        |
| `static/index.html`       | config    | —                                 | `static/index.html` (glossary-section)          | exact                        |
| `static/css/app.css`      | config    | —                                 | `static/css/app.css` (`.glossary-chevron`)      | role-match                   |
| `tests/test_parser.py`    | test      | transform                         | `tests/test_parser.py` (`test_bash_*`)          | exact                        |
| `tests/test_pipeline.py`  | test      | batch                             | `tests/test_pipeline.py`                        | exact                        |
| `tests/test_api.py`       | test      | request-response, batch           | `tests/test_api.py` (`test_translate_batch_*`)  | exact                        |
| `tests/test_cli.py`       | test      | file-I/O                          | `tests/test_cli.py` (`test_file_writes_output`) | exact                        |

---

## Pattern Assignments

### `src/validator.py` (utility, transform)

**Analog:** `src/glossary.py` (módulo puro con `@dataclass` y API pública) + `src/parser.py` (heurísticas `re` sin I/O)

**Imports / cabecera** (glossary.py líneas 1-9, parser.py líneas 1-7):
```python
"""Validador post-traducción: compara original vs traducido."""

from __future__ import annotations

import re
from dataclasses import dataclass
```

**Dataclasses de dominio** (glossary.py líneas 14-29):
```python
@dataclass
class ValidationCheck:
    id: str
    status: str  # pass | warn | error
    message: str
    expected: int | None = None
    actual: int | None = None

@dataclass
class ValidationReport:
    overall: str
    checks: list[ValidationCheck]
```

**Función pública sin efectos secundarios** (parser.py `collect_translatable` líneas 225-231):
```python
def validate_translation(original: str, translated: str) -> ValidationReport:
    """Compara estructura Markdown; no llama APIs externas."""
    checks: list[ValidationCheck] = []
    # ... helpers _strip_fenced_blocks, _count_*, etc.
    overall = _aggregate_status(checks)
    return ValidationReport(overall=overall, checks=checks)
```

**Agregación de estado** (convención implícita en traductor; aplicar en validator):
```python
def _aggregate_status(checks: list[ValidationCheck]) -> str:
    if any(c.status == "error" for c in checks):
        return "error"
    if any(c.status == "warn" for c in checks):
        return "warn"
    return "pass"
```

**Serialización para API/ZIP** (glossary `save_glossary` usa estructuras planas; preferir helper dedicado):
```python
def validation_to_dict(report: ValidationReport) -> dict:
    return {
        "overall": report.overall,
        "checks": [
            {
                "id": c.id,
                "status": c.status,
                "message": c.message,
                **({"expected": c.expected, "actual": c.actual} if c.expected is not None else {}),
            }
            for c in report.checks
        ],
    }
```

---

### `tests/test_validator.py` (test, transform)

**Analog:** `tests/test_glossary.py`

**Cabecera y imports** (líneas 1-17):
```python
"""Tests del validador post-traducción."""

from __future__ import annotations

import pytest

from src.validator import ValidationReport, validate_translation
```

**Casos por check** (test_glossary.py líneas 38-49 — assert directo):
```python
def test_fences_mismatch_is_error():
    orig = "# T\n\n```py\nx\n```\n"
    trans = "# T\n\n```py\nx\n```\n\n```extra\n"
    report = validate_translation(orig, trans)
    fences = next(c for c in report.checks if c.id == "fences")
    assert fences.status == "error"
    assert report.overall == "error"


def test_identical_docs_pass():
    md = "# Hello\n\n[link](https://x.com)\n"
    report = validate_translation(md, md)
    assert report.overall == "pass"
    assert all(c.status == "pass" for c in report.checks)
```

**Tabla de fixtures** (test_parser.py `test_bash_comments_*` — un test por regla de negocio).

---

### `src/parser.py` (utility, transform) — modificaciones

**Analog:** bloque shell existente (`SHELL_LANGS`, `_append_shell_line`, líneas 24-96, 150-171)

**Registro de lenguajes** (extender líneas 24-25):
```python
HASH_COMMENT_LANGS = frozenset({"python"})
SLASH_COMMENT_LANGS = frozenset({"javascript", "typescript", "js", "ts"})
HTML_COMMENT_LANGS = frozenset({"html", "xml"})
HASH_COMMENT = re.compile(r"^(\s*#\s?)(.*?)(\n?)$", re.DOTALL)
SLASH_COMMENT = re.compile(r"^(\s*//\s?)(.*?)(\n?)$", re.DOTALL)
HTML_COMMENT = re.compile(r"(^[\s]*)(<!--)(.*?)(-->)", re.DOTALL)
```

**Helper de idioma en fence** (reemplazar `_is_shell_fence` líneas 77-79):
```python
def _fence_lang(info: str) -> str:
    return info.strip().lower().split()[0] if info.strip() else ""

def _is_comment_fence(info: str, langs: frozenset[str]) -> bool:
    return _fence_lang(info) in langs
```

**Línea de comentario traducible** (copiar estructura `_append_shell_line` líneas 82-96):
```python
def _append_comment_line(
    segments: list[Segment],
    line: str,
    idx: int,
    pattern: re.Pattern[str],
) -> int:
    match = pattern.match(line)
    if match and match.group(2).strip():
        idx = _append_segment(segments, SegmentKind.PROTECTED, match.group(1), idx)
        body = match.group(2)
        if match.lastindex and match.lastindex >= 3 and match.group(3):
            body += match.group(3)
        idx = _append_segment(segments, SegmentKind.TRANSLATABLE, body, idx)
        return idx
    return _append_segment(segments, SegmentKind.PROTECTED, line, idx)
```

**Bucle de fence** (líneas 150-171 — ramificar por lang):
```python
lang = _fence_lang(fence_info)
is_shell = lang in SHELL_LANGS
# ... en el while interno:
if is_shell:
    idx = _append_shell_line(segments, inner, idx)
elif lang in HASH_COMMENT_LANGS:
    idx = _append_comment_line(segments, inner, idx, HASH_COMMENT)
elif lang in SLASH_COMMENT_LANGS:
    idx = _append_comment_line(segments, inner, idx, SLASH_COMMENT)
# ...
```

**Frontmatter YAML** (analog `src/glossary.py` líneas 49-67 + bloque frontmatter líneas 118-128):
```python
import yaml
from yaml import YAMLError

FM_TRANSLATABLE_KEYS = frozenset({
    "title", "description", "summary", "tags", "categories", "keywords"
})

# En segment_markdown, tras detectar bloque ---:
try:
    inner = ...  # sin delimitadores
    data = yaml.safe_load(inner)
except YAMLError:
    idx = _append_segment(segments, SegmentKind.PROTECTED, block, idx)
else:
    # walk dict/list → segmentos TRANSLATABLE o PROTECTED por clave
```

**Reconstrucción YAML:** mutar copia del dict y `yaml.safe_dump(..., allow_unicode=True, sort_keys=False)` como `save_glossary` (glossary.py líneas 70-79).

---

### `src/pipeline.py` (service, batch) — modificaciones

**Analog:** `src/pipeline.py` (`TranslateOptions`, `TranslateResult`, final de `translate_markdown`)

**Extender dataclasses** (líneas 30-49):
```python
from .validator import ValidationReport, validate_translation

@dataclass
class TranslateOptions:
    # ... campos existentes ...
    strict: bool = False

@dataclass
class TranslateResult:
    # ... campos existentes ...
    validation: ValidationReport | None = None
```

**Hook post-`reassemble`** (líneas 147-154):
```python
output = reassemble(segments, translations)
validation = validate_translation(content, output)
if options.strict and validation.overall == "error":
    raise ValidationFailedError("Validación estructural fallida")
return TranslateResult(
    content=output,
    segments_total=total,
    segments_translated=count,
    cache_hits=len(hits),
    cache_misses=miss_count,
    validation=validation,
)
```

**Excepción dedicada:** seguir `ValueError` en pipeline / `IncompleteTranslationError` en translator — nueva `ValidationFailedError` en `validator.py` o `pipeline.py`, mensaje en español.

**Dry-run:** no invocar validador (early return líneas 86-92).

---

### `src/main.py` (route, request-response + file-I/O + batch) — modificaciones

**Analog:** modelos Pydantic + `_run_translate` + `translate_batch` ZIP

**Modelos anidados** (líneas 64-67, 80-83 — patrón `GlossaryPayload`):
```python
class ValidationCheckModel(BaseModel):
    id: str
    status: str
    message: str

class ValidationReportModel(BaseModel):
    overall: str
    checks: list[ValidationCheckModel]

class TranslateResponse(BaseModel):
    content: str
    segments_total: int
    segments_translated: int
    validation: ValidationReportModel | None = None
```

**Mapeo resultado → respuesta** (`_run_translate` líneas 166-170):
```python
from .validator import validation_to_dict  # o model_validate

validation_model = None
if result.validation:
    validation_model = ValidationReportModel(**validation_to_dict(result.validation))
return TranslateResponse(
    content=result.content,
    segments_total=result.segments_total,
    segments_translated=result.segments_translated,
    validation=validation_model,
)
```

**Batch ZIP — segundo archivo por entrada** (líneas 324-326):
```python
import json

out_name = _unique_zip_name(upload.filename, target_lang, used_names)
zf.writestr(out_name, response.content.encode("utf-8"))
if response.validation:
    val_name = f"{Path(out_name).stem}.validation.json"
    zf.writestr(
        val_name,
        json.dumps(validation_to_dict(result.validation), ensure_ascii=False).encode("utf-8"),
    )
```

Nota: `_run_translate` debe devolver también el `TranslateResult` completo o el dict de validación — refactor mínimo: retornar tupla `(TranslateResponse, ValidationReport | None)` internamente o leer de `result` antes de construir solo `content`.

**HTTP:** no bloquear por validación (D-01); siempre incluir `validation` en JSON cuando exista.

---

### `src/cli.py` (route, file-I/O + batch) — modificaciones

**Analog:** `file_cmd` / `batch_cmd` + `_exit_translation`

**Opción Typer** (líneas 106-116 — junto a `dry_run`):
```python
strict: bool = typer.Option(
    False,
    "--strict",
    help="No escribir salida si la validación reporta error",
),
```

**Pasar a options** (`_build_options` líneas 44-63):
```python
return TranslateOptions(
    # ...
    strict=strict,
)
```

**Guard antes de escribir** (file_cmd líneas 129-133):
```python
if strict and result.validation and result.validation.overall == "error":
    typer.secho("Validación fallida — salida no escrita", fg=typer.colors.RED, err=True)
    raise typer.Exit(code=1)
out_path.write_text(result.content, encoding="utf-8")
```

Replicar en `dir_cmd`, `batch_cmd` (ZIP y directorio) — mismo patrón que `test_file_writes_output` en tests.

**Exit codes:** config → 2 (`_exit_config`), traducción/validación → 1 (`_exit_translation`).

---

### `static/index.html` (config) — modificaciones

**Analog:** sección Glosario (líneas 91-125) + CDN Tailwind (líneas 15-16)

**CDN antes de app.js** (UI-SPEC; patrón tailwind en head):
```html
<script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/dompurify@3.2.4/dist/purify.min.js"></script>
```

**Panel Validación** (clonar glossary-section; default `hidden` en section):
```html
<section id="validation-section" class="hidden mb-6" aria-labelledby="validation-heading">
  <button type="button" id="validation-toggle" class="flex w-full items-center justify-between rounded-xl border border-teal-100 bg-white px-4 py-3 text-left ..."
    aria-expanded="false" aria-controls="validation-panel">
    <span id="validation-heading" class="text-sm font-semibold text-ink">Validación</span>
    <svg id="validation-chevron" class="glossary-chevron w-5 h-5 text-ink-muted" ...></svg>
  </button>
  <div id="validation-panel" class="hidden mt-3 rounded-xl border border-teal-100 bg-white p-4" role="region">
    <p id="validation-summary" class="text-sm text-ink-muted"></p>
    <ul id="validation-checks" class="space-y-2 text-sm mt-3"></ul>
  </div>
</section>
```

**Preview row** (dentro `#panel-editor`, tras grid de textareas líneas 137-153):
```html
<div id="preview-row" class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
  <div>
    <p class="text-xs font-medium text-ink-muted mb-2">Vista previa — Original</p>
    <div id="preview-source" class="prose-preview rounded-xl border border-teal-100 bg-white p-4 max-h-96 overflow-y-auto" aria-label="Vista previa original"></div>
  </div>
  <div>
    <p class="text-xs font-medium text-ink-muted mb-2">Vista previa — Traducido</p>
    <div id="preview-result" class="prose-preview ..." aria-label="Vista previa traducido"></div>
  </div>
</div>
```

Ubicar `#validation-section` bajo botones de acción / status (UI-SPEC), no duplicar glosario.

---

### `static/js/app.js` (component, request-response) — modificaciones

**Analog:** glosario colapsable + `translateEditor` + `setHtml`

**Referencias DOM con guards** (líneas 46-81):
```javascript
validationSection: $('#validation-section'),
validationToggle: $('#validation-toggle'),
validationPanel: $('#validation-panel'),
validationChevron: $('#validation-chevron'),
validationSummary: $('#validation-summary'),
validationChecks: $('#validation-checks'),
previewSource: $('#preview-source'),
previewResult: $('#preview-result'),
```

**Toggle colapsable** (líneas 524-529):
```javascript
els.validationToggle?.addEventListener('click', () => {
  const isOpen = els.validationPanel.classList.toggle('hidden');
  els.validationToggle.setAttribute('aria-expanded', String(isOpen));
  els.validationChevron?.classList.toggle('expanded', isOpen);
});
```

**Render validación** (patrón `renderGlossaryTable` + `setHtml` líneas 176-201):
```javascript
const CHECK_LABELS = {
  fences: 'Bloques de código',
  links: 'Enlaces',
  images: 'Imágenes',
  inline_code: 'Código inline',
  headings: 'Encabezados',
};

function renderValidationPanel(validation) {
  if (!validation || !els.validationSection) return;
  const { overall, checks = [] } = validation;
  const pass = checks.filter((c) => c.status === 'pass').length;
  const warn = checks.filter((c) => c.status === 'warn').length;
  const err = checks.filter((c) => c.status === 'error').length;
  if (els.validationSummary) {
    els.validationSummary.textContent = `${pass} correctos · ${warn} avisos · ${err} errores`;
  }
  setHtml(
    els.validationChecks,
    checks
      .map(
        (c) => `<li class="flex gap-2 items-start">
          <span aria-hidden="true">${c.status === 'pass' ? '✓' : c.status === 'warn' ? '⚠' : '✗'}</span>
          <span><strong>${CHECK_LABELS[c.id] || c.id}</strong> — ${escapeHtml(c.message)}</span>
        </li>`
      )
      .join('')
  );
  els.validationSection.classList.remove('hidden');
}
```

**Preview sanitizada** (nunca `innerHTML` sin DOMPurify; usar `setHtml` solo con HTML ya sanitizado):
```javascript
function renderPreview(markdown, el) {
  if (!el || typeof marked === 'undefined' || typeof DOMPurify === 'undefined') {
    if (el) setHtml(el, '<p class="text-ink-muted text-sm">Vista previa no disponible</p>');
    return;
  }
  const raw = marked.parse(markdown || '', { gfm: true, breaks: false });
  const clean = DOMPurify.sanitize(raw, {
    USE_PROFILES: { html: true },
    FORBID_TAGS: ['script', 'iframe'],
  });
  setHtml(el, clean);
}
```

**Post-traducción** (translateEditor líneas 384-390 — NO en keyup):
```javascript
els.outputMd.value = data.content;
renderValidationPanel(data.validation);
renderPreview(els.inputMd.value, els.previewSource);
renderPreview(data.content, els.previewResult);
```

**Muestra** (línea 517): tras `SAMPLE_MD`, llamar `renderPreview(SAMPLE_MD, els.previewSource)`.

**Batch status** (translateBatch línea 452): mensaje «validation.json incluido en ZIP».

---

### `static/css/app.css` (config) — modificaciones

**Analog:** `.glossary-chevron` (líneas 117-123) + tokens `:root` / `html.dark` (líneas 3-21)

**Reutilizar chevron:** clase `.glossary-chevron` también en `#validation-chevron`.

**Nuevo bloque `.prose-preview`** (variables existentes):
```css
.prose-preview {
  color: var(--color-ink);
  font-size: 0.9375rem;
  line-height: 1.65;
}
.prose-preview h1, .prose-preview h2, .prose-preview h3 {
  color: var(--color-ink);
  font-weight: 600;
  margin-top: 1em;
}
.prose-preview a {
  color: var(--color-primary);
}
.prose-preview pre, .prose-preview code {
  background: rgba(13, 148, 136, 0.08);
  border-radius: 0.375rem;
}
html.dark .prose-preview pre,
html.dark .prose-preview code {
  background: rgba(20, 184, 166, 0.12);
}
```

---

### `tests/test_parser.py` (test, transform) — modificaciones

**Analog:** `test_bash_comments_are_translatable` / `test_bash_comment_translation_reassembly` (líneas 56-74)

**Nuevos tests (misma estructura):**
```python
def test_python_hash_comment_translatable():
    md = "```python\n# Install deps\npip install\n```\n"
    segments = segment_markdown(md)
    translatable = [s for s in segments if s.kind == SegmentKind.TRANSLATABLE]
    assert any("Install deps" in s.text for s in translatable)


def test_shebang_line_protected():
    md = "```python\n#!/usr/bin/env python3\n# comment\n```\n"
    protected = "".join(s.text for s in segments if s.kind == SegmentKind.PROTECTED)
    assert "#!/usr/bin/env python3" in protected
```

Añadir casos `javascript` `//`, `html` `<!-- -->`, frontmatter whitelist / slug protected / invalid YAML whole block protected.

---

### `tests/test_pipeline.py` (test, batch) — modificaciones

**Analog:** `test_translate_markdown_success` (líneas 14-21)

```python
def test_translate_markdown_includes_validation(mock_translate_segments):
    md = "# Hello\n\nWorld\n"
    result = translate_markdown(md, TranslateOptions(target_lang="es"))
    assert result.validation is not None
    assert result.validation.overall in ("pass", "warn", "error")
```

Opcional: `monkeypatch` validador para forzar `error` + `strict=True` → excepción.

---

### `tests/test_api.py` (test, request-response + batch) — modificaciones

**Analog:** `test_translate_text_success` (46-54) + `test_translate_batch_success` (142-151)

```python
def test_translate_text_includes_validation(client, mock_translate_success):
    res = client.post(
        "/api/translate",
        json={"content": "# Hello\n", "target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 200
    data = res.json()
    assert "validation" in data
    assert data["validation"]["overall"] in ("pass", "warn", "error")
    assert isinstance(data["validation"]["checks"], list)


def test_translate_batch_zip_contains_validation_json(client, mock_translate_success):
    res = client.post(
        "/api/translate/batch",
        files={"files": ("doc.md", make_md_bytes("# Hello"), "text/markdown")},
        data={"target_lang": "es", "source_lang": "auto"},
    )
    assert res.status_code == 200
    zf = zipfile.ZipFile(io.BytesIO(res.content))
    assert any(n.endswith(".validation.json") for n in zf.namelist())
```

---

### `tests/test_cli.py` (test, file-I/O) — modificaciones

**Analog:** `test_file_writes_output` (48-57) + `mock_pipeline` fixture (18-35)

```python
def test_file_strict_blocks_on_validation_error(tmp_path, monkeypatch):
    from src.validator import ValidationCheck, ValidationReport

    def _fake(content, options):
        return TranslateResult(
            content="# TR",
            segments_total=1,
            segments_translated=1,
            validation=ValidationReport(
                overall="error",
                checks=[ValidationCheck("fences", "error", "mismatch", 1, 2)],
            ),
        )

    monkeypatch.setattr("src.cli.translate_markdown", _fake)
    md = tmp_path / "doc.md"
    md.write_text("# Hi", encoding="utf-8")
    out = tmp_path / "out.md"
    result = runner.invoke(
        app, ["file", str(md), "-t", "es", "-o", str(out), "--strict"],
        catch_exceptions=False,
    )
    assert result.exit_code == 1
    assert not out.exists()
```

---

## Shared Patterns

### Módulos Python (`src/`)
**Source:** convenciones del repo + todos los módulos `src/*.py`
**Apply to:** `validator.py`, cambios en `parser.py`, `pipeline.py`

```python
from __future__ import annotations
"""Docstring de módulo en español."""
# Imports absolutos: from src.X o from .X dentro del paquete
# Dataclasses para modelos de dominio; helpers con prefijo _
# ValueError / excepciones dedicadas con mensaje claro; sin HTTP aquí
```

### Errores HTTP (solo `main.py`)
**Source:** `src/main.py` líneas 119-129, 228-236

**Apply to:** endpoints de traducción — validación no bloquea; mantener 400/502/503 existentes.

```python
except ValueError as e:
    raise HTTPException(400, str(e)) from e
except RuntimeError as e:
    raise HTTPException(503, str(e)) from e
```

### Ejecutor async para pipeline
**Source:** `src/main.py` `_run_translate` líneas 149-161

**Apply to:** sin cambiar patrón — `translate_markdown` sigue en `run_in_executor`.

### UI: guards DOM y `setHtml`
**Source:** `static/js/app.js` líneas 46-49, 172-174

**Apply to:** validation panel, preview, cualquier nodo nuevo.

```javascript
function setHtml(el, html) {
  if (el) el.innerHTML = html;
}
function hasValidationUi() {
  return Boolean(els.validationSection);
}
```

### UI: panel colapsable + ARIA
**Source:** `static/index.html` glossary (92-105) + `app.js` (524-529)

**Apply to:** `#validation-section`, reutilizar `.glossary-chevron`.

### Tests: mocks de traducción
**Source:** `tests/conftest.py` `mock_translate_success` (39-45)

**Apply to:** `test_api`, `test_pipeline`, `test_cli` — no llamar APIs reales.

### Tests: aislamiento TM
**Source:** `tests/conftest.py` `isolated_memory_db` autouse (12-23)

**Apply to:** todos los tests que pasen por pipeline.

---

## No Analog Found

| File   | Role   | Data Flow   | Reason                                                |
| ------ | ------ | ----------- | ----------------------------------------------------- |
| —      | —      | —           | Todos los archivos previstos tienen analog en el repo |

**Nota planner:** `ValidationFailedError` y helper `validation_to_dict` no existen aún — crear siguiendo `IncompleteTranslationError` (`src/translator.py`) y `glossary_to_dict` (`src/glossary.py`) respectivamente.

---

## Metadata

**Analog search scope:** `src/`, `static/`, `tests/`, `.planning/phases/02-trust-qa/02-{CONTEXT,RESEARCH,UI-SPEC}.md`
**Files scanned:** 18
**Pattern extraction date:** 2026-05-28
