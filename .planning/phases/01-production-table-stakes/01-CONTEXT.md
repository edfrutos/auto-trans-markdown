# Phase 1: Production Table Stakes - Context

**Gathered:** 2026-05-28
**Status:** Ready for planning
**Mode:** auto (decisions from REQUIREMENTS + research + NOTEBOOK §1–§3)

<domain>
## Phase Boundary

Unificar el pipeline de traducción en una fachada `translate_markdown()`, añadir memoria de traducción SQLite, glosario YAML con UI de gestión, y CLI Typer `md-translate` con subcomandos `file|dir|batch|serve|memory clear`. API, CLI y web deben compartir el mismo comportamiento. Phase 0 (hardening) está completo: `IncompleteTranslationError`, UTF-8 estricto, idiomas por proveedor, tests de integración.

Fuera de alcance: validador post-traducción (Phase 2), SSE/jobs (Phase 3), Docker (Phase 4), Redis, ORM, bundler frontend.

</domain>

<decisions>
## Implementation Decisions

### Pipeline unificado (PIPE-01)

- **D-01:** Crear `src/pipeline.py` con `translate_markdown(content: str, options: TranslateOptions) -> TranslateResult` como única fachada para API, CLI y web.
- **D-02:** `TranslateOptions` es `@dataclass` con campos: `target_lang`, `source_lang: str | None` (None = auto), `dry_run: bool = False`, `use_memory: bool = True`, `use_glossary: bool = True`, `glossary_path: Path | None = None`, `memory_path: Path | None = None`, `on_progress: ProgressCallback | None = None`.
- **D-03:** `TranslateResult` incluye `content: str`, `segments_total: int`, `segments_translated: int`, `cache_hits: int`, `cache_misses: int`, `dry_run_segments: list[tuple[int, str]] | None = None`.
- **D-04:** Refactorizar `src/main.py`: eliminar `_translate_file_content()`; todos los endpoints llaman `translate_markdown()` vía `run_in_executor`.
- **D-05:** Orden en pipeline: `segment_markdown` → `collect_translatable` → TM lookup (pre-glossary text) → glossary pre-process → `translate_segments` (solo misses) → glossary post-process → TM store → `reassemble`.

### Memoria de traducción (TM-01, TM-02, TM-03)

- **D-06:** `src/memory.py` usa stdlib `sqlite3`; archivo en `data/translation_memory.db`; modo WAL (`PRAGMA journal_mode=WAL`).
- **D-07:** Clave de cache: `sha256(normalize(text) + "|" + source_lang + "|" + target_lang)` donde `normalize()` colapsa whitespace interno a un espacio y hace strip.
- **D-08:** TM lookup usa texto **pre-glossary** del segmento; store persiste traducción **post-glossary** (texto final que verá el usuario).
- **D-09:** `memory clear` disponible vía CLI (`md-translate memory clear`) y API (`DELETE /api/memory`); UI con botón confirmado (modal o `confirm()`).
- **D-10:** Crear `data/` en startup si no existe; añadir `data/` a `.gitignore` (DB puede contener docs privados).

### Glosario (GLOS-01, GLOS-02, GLOS-03)

- **D-11:** Archivo por defecto `glossary.yaml` en raíz del proyecto; formato YAML con `safe_load`/`safe_dump` exclusivamente.
- **D-12:** Esquema YAML:
  ```yaml
  version: 1
  do_not_translate:          # lista global — preservar literal en cualquier idioma
    - API Gateway
    - MarkDown Auto Translator
  pairs:                     # clave "source-target" (ej. en-es, auto-es)
    en-es:
      dashboard: panel
      "piece of cake": pan comido
    auto-es:
      dashboard: panel
  ```
- **D-13:** OpenAI: inyectar reglas de glosario como bloque adicional en system/user prompt antes del batch (no modificar `SYSTEM_PROMPT` base; append dinámico en pipeline).
- **D-14:** DeepL: pre-proceso envuelve términos con placeholders `⟦GLO{n}⟧`; post-proceso restaura traducción fija o literal según regla.
- **D-15:** API CRUD glosario: `GET/PUT /api/glossary` lee/escribe `glossary.yaml`; validación de esquema en PUT.
- **D-16:** UI panel colapsable «Glosario» bajo controles de idioma; tabla editable; guardar vía PUT; aplicado automáticamente en editor, archivo y lote (misma fachada pipeline).

### CLI Typer (CLI-01 … CLI-05)

- **D-17:** `src/cli.py` con Typer app; entry point `md-translate = "src.cli:app"` en `pyproject.toml`.
- **D-18:** Subcomandos: `file`, `dir`, `batch`, `serve`, `memory` (con subcomando `clear`).
- **D-19:** Flags comunes: `--target/-t`, `--source/-s` (default `auto`), `--dry-run`, `--no-memory`, `--no-glossary`, `--glossary-path`, `--provider` (override env).
- **D-20:** `file`: `md-translate file INPUT.md -t es -o README.es.md` — exit 0 OK, 1 error traducción, 2 error config/validación.
- **D-21:** `dir`: `--recursive` preserva estructura relativa bajo `-o/--output-dir`.
- **D-22:** `batch`: acepta globs o lista de paths; salida `--zip PATH` o `--output-dir PATH` (mutuamente excluyentes).
- **D-23:** `--dry-run`: lista segmentos traducibles a stdout (JSON lines o tabla); no llama proveedor ni escribe TM.
- **D-24:** `serve`: delega a `src.main.run()` — servidor web separado del entry point principal.
- **D-25:** Dependencias nuevas: `typer>=0.21`, `pyyaml>=6.0.2`; actualizar `requirements.txt` y `pyproject.toml`.

### Claude's Discretion

- Formato exacto de salida `--dry-run` (JSON vs tabla Rich).
- Ubicación del panel glosario en DOM (debajo de idiomas vs drawer lateral).
- Mensaje exacto del modal «Limpiar memoria».
- Tests adicionales más allá de smoke CLI + TM + glossary unitarios.

</decisions>

<canonical_refs>
## Canonical References

- `.planning/REQUIREMENTS.md` — PIPE-01, GLOS-*, TM-*, CLI-*
- `.planning/ROADMAP.md` § Phase 1
- `.planning/research/SUMMARY.md` — build order pipeline → memory → glossary → CLI
- `.planning/phases/00-mvp-hardening/00-CONTEXT.md` — hardening completado
- `NOTEBOOK.md` §1–§3 — glosario, TM, CLI
- `src/main.py`, `src/translator.py`, `src/parser.py` — baseline Phase 0

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `segment_markdown`, `collect_translatable`, `reassemble` — sin cambios de contrato
- `translate_segments` con `on_progress`, `IncompleteTranslationError` — invocado desde pipeline
- `get_supported_languages`, `is_valid_target_lang`, `is_valid_source_lang` — reutilizar en CLI
- `tests/conftest.py`, `tests/test_api.py` — extender con mocks pipeline/TM/glossary

### Established Patterns

- FastAPI async + `run_in_executor` para I/O bloqueante
- `HTTPException` 400/502/503; errores en español
- Frontend vanilla: `state`, `els`, `$`, fetch API
- Tests sin API keys reales (mock en frontera)

### Integration Points

- `_translate_file_content()` → reemplazar por `pipeline.translate_markdown`
- `/api/languages` → sin cambio; CLI valida idiomas igual que API
- `pyproject.toml` scripts → cambiar entry point crítico para CLI-05

</code_context>

<deferred>
## Deferred Ideas

- Validador estructural post-traducción — Phase 2 (VAL-*)
- Preview Markdown renderizada — Phase 2 (PREV-*)
- SSE progreso real en lote — Phase 3 (JOB-*)
- TTL automático en TM — backlog
- Import/export glosario CSV — backlog
- Estadísticas cache hit en UI — backlog (TM stats en CLI opcional)

</deferred>

---

*Phase: 01-production-table-stakes*
*Context gathered: 2026-05-28*
