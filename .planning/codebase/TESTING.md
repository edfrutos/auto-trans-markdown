# Testing Patterns

**Analysis Date:** 2026-05-28

## Test Framework

**Runner:**

- pytest (instalación manual; no está en `requirements.txt` ni en `[project.optional-dependencies]`)
- Config: `[tool.pytest.ini_options]` en `pyproject.toml`

**Assertion Library:**

- `assert` nativo de Python (sin pytest helpers tipo `assert_equal` salvo los implícitos de pytest)

**Run Commands:**
```bash
pip install pytest
pytest tests/ -q              # Todos los tests (salida mínima)
pytest tests/ -v              # Verbose, nombres de tests
pytest tests/test_parser.py -q   # Un solo módulo
pytest tests/ --co -q         # Solo colección (conteo sin ejecutar)
```

Desde el README del proyecto (`README.md`, sección Tests): mismo flujo `pip install pytest` + `pytest tests/ -q`.

## Test File Organization

**Location:**

- Directorio dedicado `tests/` en la raíz del proyecto
- Un único módulo de pruebas: `tests/test_parser.py`
- Sin `tests/__init__.py` ni `conftest.py`

**Naming:**

- Archivos: `test_<área>.py` → `test_parser.py`
- Funciones: `test_<comportamiento>` → `test_preserves_code_fence`, `test_bash_comments_are_translatable`

**Structure:**
```text
auto-trans-markdown/
├── pyproject.toml          # testpaths = ["tests"], pythonpath = ["."]
├── tests/
│   └── test_parser.py      # Tests unitarios del segmentador
└── src/
    ├── parser.py           # Código bajo prueba
    ├── translator.py       # Sin tests
    └── main.py             # Sin tests
```

## Test Structure

**Suite Organization:**

- Módulo autocontenido sin clases ni fixtures pytest
- Docstring de módulo + funciones `test_*` planas
- Imports al inicio del archivo de test

```python
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
    # ...
```

**Patterns:**

- **Setup:** strings Markdown inline en cada test (sin archivos fixture en disco)
- **Teardown:** no aplica (funciones puras, sin estado global)
- **Assertion:** `assert` booleano; a veces mensaje custom en tercer argumento: `assert len(indices) == len(set(indices)), "Cada segmento debe tener índice único"`
- **Act:** llamar `segment_markdown` → opcionalmente `collect_translatable` → opcionalmente `reassemble` con diccionario de traducciones simuladas

## Mocking

**Framework:** No detectado en el proyecto (sin `unittest.mock`, `pytest-mock`, ni `responses`)

**Patterns actuales:**

- No hay mocks; los tests evitan red y APIs externas limitándose a `src/parser.py`
- Traducciones simuladas con `.replace()` o diccionarios `{idx: "texto"}` pasados a `reassemble`

**What to Mock (al ampliar cobertura):**

- `openai.OpenAI` / `client.chat.completions.create` en tests de `src/translator.py`
- `deepl.Translator.translate_text` cuando `TRANSLATION_PROVIDER=deepl`
- `os.getenv` solo si hace falta aislar configuración; preferir `monkeypatch.setenv` de pytest

**What NOT to Mock:**

- Lógica de `segment_markdown`, `collect_translatable`, `reassemble` en tests de parser (comportamiento real)
- Al testear integración parser + traductor con fake, inyectar `client` opcional en `translate_segments(..., client=...)` en lugar de parchear imports globales cuando sea posible

## Fixtures and Factories

**Test Data:**

- Markdown mínimo embebido por caso en `tests/test_parser.py`
- Ejemplos cubiertos: fences `python`, código inline, reensamblado con traducción, líneas en blanco, bloques `bash` con comentarios `#`

**Location:**

- No hay directorio `tests/fixtures/` ni `tests/data/`
- Para nuevos casos, seguir el patrón de string multilínea en el propio `test_*`

**Factory pattern recomendado (no existe aún):**
```python
def _seg(md: str):
    return segment_markdown(md)
```
Colocar helpers compartidos en `conftest.py` solo si varios archivos de test los reutilizan.

## Coverage

**Requirements:** Ninguno enforced en CI ni en configuración del repo

**View Coverage:**
```bash
pip install pytest-cov
pytest tests/ --cov=src.parser --cov-report=term-missing
```
Ampliar a `--cov=src` cuando existan tests para `translator` y `main`.

**Gaps actuales (sin cobertura automatizada):**

- `src/translator.py` — lotes OpenAI/DeepL, reintentos, parsing JSON
- `src/main.py` — endpoints FastAPI, upload, ZIP batch, `HTTPException`
- `static/js/app.js` — sin tests frontend

## Test Types

**Unit Tests:**

- Único tipo implementado: 6 tests en `tests/test_parser.py`
- Alcance: segmentación, clasificación `PROTECTED` vs `TRANSLATABLE`, índices únicos, reensamblado con mapa de traducciones
- Ejecución verificada: 6 passed en ~0.02s (sin I/O de red)

**Integration Tests:**

- No usados
- Candidato natural: `httpx.AsyncClient` + `app` de FastAPI con traductor mockeado vía `dependency_overrides` o parche de `translate_segments`

**E2E Tests:**

- No usados
- No hay Playwright, Selenium ni tests contra DeepL/OpenAI reales (correcto para CI sin secretos)

## Common Patterns

**Async Testing:**

- No aplica en la suite actual (parser síncrono)
- Para endpoints en `src/main.py`, usar:

```python
from fastapi.testclient import TestClient
from src.main import app

client = TestClient(app)

def test_list_languages():
    r = client.get("/api/languages")
    assert r.status_code == 200
```

**Error Testing (recomendado al añadir tests de API/traductor):**
```python
import pytest
from src.translator import create_openai_client

def test_missing_api_key(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    with pytest.raises(RuntimeError, match="OPENAI_API_KEY"):
        create_openai_client()
```

**Parser regression pattern (seguir en nuevos tests):**
```python
def test_preserves_inline_code():
    md = "Use the `API_KEY` variable here.\n"
    segments = segment_markdown(md)
    assert any(s.kind == SegmentKind.PROTECTED and "API_KEY" in s.text for s in segments)
    assert any(s.kind == SegmentKind.TRANSLATABLE and "Use the" in s.text for s in segments)
```

**Reassembly with fake translations:**
```python
segments = segment_markdown(md)
translatable = collect_translatable(segments)
translations = {idx: "Hola mundo\n" for idx, _ in translatable}
out = reassemble(segments, translations)
assert "# Hola mundo" in out
```

## Adding New Tests

| Funcionalidad                 | Archivo sugerido                                      | Enfoque                                                                |
| ----------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------- |
| Nuevas reglas de segmentación | `tests/test_parser.py` o `tests/test_parser_shell.py` | Strings MD + asserts sobre `SegmentKind`                               |
| Lotes / proveedores           | `tests/test_translator.py`                            | `monkeypatch`, mock de cliente OpenAI/DeepL                            |
| API HTTP                      | `tests/test_main.py`                                  | `TestClient`, mock de `_translate_file_content` o `translate_segments` |
| Regresión de índices          | Mismo estilo que `test_no_duplicate_blank_lines`      | `len(indices) == len(set(indices))`                                    |

**Dependencias de test:** mantener pytest como dependencia de desarrollo documentada; opcional añadir en `pyproject.toml`:
```toml
[project.optional-dependencies]
dev = ["pytest>=8.0", "pytest-cov>=5.0", "httpx>=0.27"]
```

## CI / Hooks

- Pre-commit ejecuta `git secrets`, no pytest
- No hay workflow de GitHub Actions detectado en el análisis del repo para tests automáticos
- Ejecutar `pytest tests/ -q` localmente antes de PR que toque `src/parser.py`, `src/translator.py` o `src/main.py`

---

*Testing analysis: 2026-05-28*
