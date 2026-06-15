# Coding Conventions

**Analysis Date:** 2026-05-28

## Naming Patterns

**Files:**

- Módulos Python en `snake_case`: `parser.py`, `translator.py`, `main.py`
- Tests bajo `tests/` con prefijo `test_`: `tests/test_parser.py`
- Frontend estático: `static/js/app.js`, `static/index.html`

**Functions:**

- Funciones públicas y helpers en `snake_case`: `segment_markdown`, `collect_translatable`, `translate_segments`
- Helpers internos con prefijo `_`: `_decode_upload`, `_translate_openai_batch`, `_append_shell_line`
- Handlers FastAPI async sin prefijo `_`: `translate_text`, `translate_file`, `translate_batch`
- Punto de entrada CLI/servidor: `run()` en `src/main.py`

**Variables:**

- `snake_case` para variables locales y parámetros: `target_lang`, `translatable`, `zip_buffer`
- Constantes de módulo en `UPPER_SNAKE_CASE`: `FENCE_PATTERN`, `BATCH_SIZE`, `SYSTEM_PROMPT`, `LANGUAGE_NAMES`
- Colecciones inmutables con `frozenset` cuando aplica: `SHELL_LANGS` en `src/parser.py`

**Types:**

- Clases Pydantic de API en `PascalCase`: `TranslateTextRequest`, `TranslateResponse`, `LanguageItem`
- `dataclass` para modelos de dominio: `Segment` en `src/parser.py`
- `Enum` con valores string: `SegmentKind(str, Enum)` con miembros `PROTECTED`, `TRANSLATABLE`
- `Protocol` para callbacks opcionales: `ProgressCallback` en `src/translator.py`
- Anotaciones modernas: `str | None`, `list[tuple[int, str]]`, `dict[int, str]`

## Code Style

**Formatting:**

- No hay configuración activa de Black, Ruff ni isort en el repositorio (solo entradas en `.gitignore` para `.mypy_cache/` y `.ruff_cache/`)
- Estilo implícito PEP 8: indentación 4 espacios, comillas dobles en docstrings y strings de código
- Líneas largas permitidas en prompts y cadenas multilínea (`SYSTEM_PROMPT` en `src/translator.py`)

**Linting:**

- No detectado: `.eslintrc`, `ruff.toml`, `mypy.ini`, ni sección `[tool.ruff]` / `[tool.mypy]` en `pyproject.toml`
- Pre-commit: hook `git secrets --pre_commit_hook` en `.git/hooks/pre-commit` (evita filtrar secretos, no formatea código)

**Python version:**

- `requires-python = ">=3.11"` en `pyproject.toml`
- Usar `from __future__ import annotations` al inicio de cada módulo en `src/` para forward references

## Import Organization

**Order (observado en `src/main.py`, `src/translator.py`, `src/parser.py`):**

1. `from __future__ import annotations` (si aplica)
2. Docstring de módulo (una línea, español)
3. Biblioteca estándar (`asyncio`, `re`, `os`, …)
4. Dependencias de terceros (`fastapi`, `openai`, `dotenv`, …)
5. Imports relativos del paquete: `from .parser import …`, `from .translator import …`

**Tests:**

- Imports absolutos desde el paquete raíz del proyecto:
  ```python
  from src.parser import SegmentKind, collect_translatable, reassemble, segment_markdown
  ```
- `pythonpath = ["."]` en `[tool.pytest.ini_options]` de `pyproject.toml` habilita este patrón

**Path Aliases:**

- No hay aliases de import configurados; el paquete vive en `src/` como namespace plano (`src.main:app` para uvicorn)

## Error Handling

**Capa API (`src/main.py`):**

- Validación de entrada del cliente → `HTTPException` con códigos 400 (validación), 502 (fallo de traducción), 503 (configuración/servicio no disponible)
- Mensajes de error orientados al usuario en español: `"El contenido está vacío"`, `"Idioma destino no soportado: …"`
- Errores de decodificación de archivo → capturar `ValueError` de `_decode_upload` y reenviar como `HTTPException(400, …)` con `from e`
- Configuración o proveedor ausente → `RuntimeError` desde `src/translator.py` mapeado a `HTTPException(503, str(e))`
- Errores inesperados en traducción → `logger.exception(...)` y `HTTPException(502, …)` con `from e`

**Capa traducción (`src/translator.py`):**

- Configuración faltante → `RuntimeError` con mensaje accionable (referencia a variables `.env`, sin incluir valores)
- Respuesta de modelo inválida → `ValueError` con conteo esperado vs recibido
- Reintentos con backoff exponencial (`2 ** (attempt + 1)`) para `RateLimitError` y códigos HTTP 429/5xx de OpenAI
- División recursiva de lotes cuando la respuesta JSON no coincide o DeepL falla en lote grande
- Proveedor desconocido → `RuntimeError` listando valores válidos (`openai`, `deepl`)

**Capa parser (`src/parser.py`):**

- Sin excepciones custom; funciones puras que asumen Markdown bien formado
- Segmentos vacíos se omiten en `_append_segment` (no se añaden al listado)

**Patrón recomendado al añadir código:**

- Lógica reutilizable: lanzar `ValueError` / `RuntimeError` con mensaje claro
- Borde HTTP: convertir en `HTTPException` en `src/main.py`, no en `parser` ni `translator`
- Usar `raise … from e` al envolver excepciones

## Logging

**Framework:** `logging` estándar de Python

**Patterns:**

- `logger = logging.getLogger(__name__)` en `src/main.py` y `src/translator.py`
- Nivel configurado solo al arrancar servidor en `run()`: `logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")`
- `logger.warning` para reintentos y división de lotes en `src/translator.py`
- `logger.exception` antes de respuestas 502 en endpoints de traducción en `src/main.py`
- No hay logging en `src/parser.py` (módulo determinista)

## Comments

**When to Comment:**

- Docstring de módulo al inicio de cada archivo `src/*.py` (descripción breve en español)
- Docstrings en funciones públicas o no obvias: `segment_markdown`, `reassemble`, `collect_translatable`, `translate_segments`
- Comentarios inline solo para reglas de negocio no evidentes (p. ej. comentarios `#` traducibles en bloques shell en `src/parser.py`)

**Docstrings:**

- Estilo Google informal en español, sin tipos repetidos si ya hay anotaciones
- Tests: docstring de módulo en `tests/test_parser.py` (`"""Tests del segmentador Markdown."""`)

## Function Design

**Size:**

- `segment_markdown` en `src/parser.py` es el método más largo (~100 líneas); el resto del código favorece funciones auxiliares `_append_*`, `_split_*`
- `src/translator.py` separa lotes, proveedores y parsing de respuesta en funciones `_`-prefijadas

**Parameters:**

- Idiomas como códigos ISO cortos (`es`, `pt-BR`); `source_lang=None` o `"auto"` significa detección automática
- Segmentos traducibles como `list[tuple[int, str]]` (índice estable + texto)
- Callback opcional con keyword-only: `on_progress: Callable[[int, int], None] | None = None` en `translate_segments`

**Return Values:**

- Parser: `list[Segment]`, `dict[int, str]` para traducciones, `str` reconstruido
- Traductor: `dict[int, str]` indexado por índice de segmento
- API: modelos Pydantic o `FileResponse` / `StreamingResponse`

## Module Design

**Exports:**

- No hay `src/__init__.py` requerido para el layout actual; uvicorn usa `src.main:app`
- API pública del parser: `SegmentKind`, `Segment`, `segment_markdown`, `reassemble`, `collect_translatable`
- API pública del traductor: `LANGUAGE_NAMES`, `translate_segments`, `get_provider`, factories `create_openai_client` / `create_deepl_client`

**Barrel Files:**

- No usados; importar desde el módulo concreto

**Configuration:**

- `load_dotenv()` una vez al importar `src/main.py`
- Lectura de entorno vía `os.getenv` en traductor y `run()`; documentar nombres en `README.md` y `.env.example` (no commitear `.env`)

**Frontend (`static/js/app.js`):**

- JavaScript vanilla ES modules implícitos (script clásico, no bundler)
- `const` / `let`, funciones con nombre, objeto `state`, helper `$` para `querySelector`
- Comentarios de bloque JSDoc-style en cabecera del archivo
- Mensajes de UI y `SAMPLE_MD` en inglés (contenido de demo), errores vía API en español

## Where New Code Should Match

| Tipo de cambio                 | Ubicación                               | Convención                                                                    |
| ------------------------------ | --------------------------------------- | ----------------------------------------------------------------------------- |
| Regla de segmentación MD       | `src/parser.py`                         | Helper `_`, tests en `tests/test_parser.py`                                   |
| Proveedor o lote de traducción | `src/translator.py`                     | Constantes en mayúsculas, reintentos existentes                               |
| Endpoint o modelo HTTP         | `src/main.py`                           | Pydantic + `HTTPException`, async + `run_in_executor` para trabajo bloqueante |
| UI web                         | `static/js/app.js`, `static/index.html` | Patrón `els` / `state`, sin framework                                         |

---

*Convention analysis: 2026-05-28*
