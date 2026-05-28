# Phase 0: MVP Hardening - Context

**Gathered:** 2026-05-28
**Status:** Ready for planning
**Mode:** auto (via /gsd-next — decisions from REQUIREMENTS + research, no interactive discuss)

<domain>
## Phase Boundary

Endurecer el pipeline existente (segment → translate → reassemble) antes de añadir glosario, memoria, CLI ni nuevas features. Entregables: contratos de error explícitos, UTF-8 estricto en uploads, idiomas filtrados por proveedor activo, y tests de integración que cubran traductor + API + reassemble.

</domain>

<decisions>
## Implementation Decisions

### Traducciones incompletas (HARD-01)
- **D-01:** Fallar con HTTP 502 y mensaje explícito cuando `len(translations) != len(translatable)` — nunca devolver salida parcial silenciosa.
- **D-02:** Validar conteo en **todos** los caminos (OpenAI y DeepL), no solo en `_parse_openai_response`.
- **D-03:** Incluir en el cuerpo del error cuántos segmentos faltan; opcionalmente lista de índices en modo debug (`detail.missing_indices`).

### UTF-8 en uploads (HARD-02)
- **D-04:** Rechazar archivos no UTF-8 válidos con HTTP 400 y mensaje claro al usuario.
- **D-05:** Eliminar fallback `latin-1` y `errors="replace"` en `_decode_upload`; sin sustitución silenciosa de caracteres.
- **D-06:** Aplicar la misma validación en editor (texto), archivo único y lote.

### Idiomas por proveedor (HARD-03)
- **D-07:** `/api/languages` devuelve solo idiomas soportados por `TRANSLATION_PROVIDER` activo (OpenAI vs DeepL).
- **D-08:** Validar `target_lang` y `source_lang` en **todas** las rutas (`/translate`, `/translate/file`, `/translate/batch`) contra la lista del proveedor activo → HTTP 400 si inválido.
- **D-09:** La UI consume `/api/languages` dinámicamente; no hardcodear listas desalineadas con el backend.

### Tests de integración (HARD-04)
- **D-10:** Tests con proveedor mockeado (sin API keys reales en CI) para `translate_segments`, reassemble y endpoints FastAPI (`TestClient`).
- **D-11:** Casos obligatorios: respuesta JSON incompleta → 502; upload bytes inválidos → 400; idioma no soportado → 400; round-trip segment/reassemble sin pérdida de índices.
- **D-12:** Mantener tests unitarios existentes en `tests/test_parser.py`; añadir `tests/test_translator.py` y `tests/test_api.py` (o equivalente).

### Claude's Discretion
- Formato exacto del JSON de error (`detail` vs mensaje plano).
- Estructura de mocks (pytest fixtures vs dependency override en FastAPI).
- Orden de implementación dentro de la fase (traductor antes que API o en paralelo por plan).

</decisions>

<canonical_refs>
## Canonical References

### Requisitos y alcance
- `.planning/REQUIREMENTS.md` — HARD-01 a HARD-04 (criterios de aceptación)
- `.planning/ROADMAP.md` § Phase 0 — goal y success criteria
- `.planning/PROJECT.md` — core value y decisiones de proyecto

### Riesgos y deuda conocida
- `.planning/codebase/CONCERNS.md` — Known Bugs (UTF-8 fallback, segmentos sin traducción, source_lang sin validar)
- `.planning/research/PITFALLS.md` — Pitfall 3 (segmentos no traducidos sin fallar)

### Código existente
- `src/parser.py` — `segment_markdown`, `reassemble`, contrato de índices
- `src/translator.py` — `translate_segments`, proveedores OpenAI/DeepL
- `src/main.py` — endpoints API, `_decode_upload`, `LANGUAGE_NAMES`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/parser.py`: `collect_translatable`, `reassemble` — punto de validación post-traducción
- `src/translator.py`: `_parse_openai_response` ya valida conteo parcial — extender patrón a DeepL
- `src/main.py`: `LANGUAGE_NAMES`, `_decode_upload`, validación parcial en `translate_text`

### Established Patterns
- FastAPI + `HTTPException` para errores de cliente (400) y proveedor (502/503)
- Traducción en `run_in_executor` — tests deben mockear `translate_segments` o el cliente del proveedor
- Segmentos indexados únicos — regresión ya cubierta en `tests/test_parser.py`

### Integration Points
- `_decode_upload` → todos los endpoints multipart
- `translate_segments` → retorno validado antes de `reassemble` en API y futuro `pipeline.py`
- `/api/languages` → `static/js/app.js` selectores de idioma

</code_context>

<specifics>
## Specific Ideas

- Priorizar confianza del usuario: mejor error explícito que salida «casi traducida».
- Alineado con NOTEBOOK Pre-A / research: hardening es prerequisito de Phase 1 (pipeline unificado).

</specifics>

<deferred>
## Deferred Ideas

- Validador post-traducción estructural — Phase 2 (VAL-*)
- Lotes parciales con `errors.json` — Phase 3 (JOB-*)
- CORS/auth hardening — Phase 4 (SEC-*)
- `source_lang=auto` detect — backlog / Phase 2+

</deferred>

---

*Phase: 00-mvp-hardening*
*Context gathered: 2026-05-28*
