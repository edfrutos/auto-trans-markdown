# Phase 2: Trust & QA - Context

**Gathered:** 2026-05-28
**Status:** Ready for planning

<domain>
## Phase Boundary

El usuario puede **confiar** en que la traducción no rompió la estructura Markdown y **revisarla visualmente** antes de exportar. Esta fase entrega: validador post-traducción con informe en UI y en ZIP de lote, vista previa HTML sanitizada (original y traducido), extensión del parser para comentarios traducibles en fences Python/JS/TS/HTML, y traducción selectiva de frontmatter YAML con metadatos técnicos intactos. Modo `--strict` en CLI bloquea exportación si la validación falla.

**Depende de:** Phase 1 (pipeline `translate_markdown()`, UI vanilla, CLI Typer).

**Fuera de alcance:** SSE/jobs y progreso real en lote (Phase 3), diff lado a lado editorial (Phase 5), auth/CORS (Phase 4), bundler frontend, validación que bloquee por defecto en UI (solo avisos; bloqueo vía `--strict` CLI).

</domain>

<decisions>
## Implementation Decisions

### Validación post-traducción (VAL-01, VAL-02, VAL-03)

- **D-01:** Por defecto los fallos de validación son **warnings** — la descarga y el flujo normal continúan.
- **D-02:** Flag CLI `--strict`: si hay checks en estado **error** (o equivalente fail), no escribir archivo de salida; exit code distinto de 0 (detalle en plan).
- **D-03:** Checks v1 (comparación original vs traducido): **fences** (conteo/apertura-cierre), **enlaces e imágenes** markdown, **código inline** (spans `` ` ``), **encabezados** (profundidad `#` por línea). Sin alerta de longitud >300% en Fase 2.
- **D-04:** Módulo `src/validator.py` produce informe estructurado (JSON) con estado por check: `pass` | `warn` | `error` (definir reglas en plan; p. ej. desajuste numérico = error, desajuste menor = warn).
- **D-05:** UI: panel **colapsable bajo el resultado** (mismo patrón que Glosario) — resumen + lista de checks con icono/estado; visible tras traducir en editor, archivo y (cuando aplique) tras lote en UI.
- **D-06:** Lote ZIP: incluir **`validation.json` por cada archivo traducido** (mismo stem o ruta relativa documentada en plan), además del `.md` traducido.
- **D-07:** Validación se ejecuta en el **pipeline** tras `reassemble`, sobre pares `(original, translated)`; API devuelve informe en respuesta donde ya hay `TranslateResponse` o campo dedicado (planner decide contrato).

### Vista previa renderizada (PREV-01, PREV-02)

- **D-08:** En pestaña Editor, **dos paneles renderizados** bajo los textareas de texto plano: **Original | Traducido**, lado a lado en desktop.
- **D-09:** Actualizar preview **solo al terminar traducción exitosa** y al cargar ejemplo — no en cada tecla del editor.
- **D-10:** En viewport estrecho, paneles renderizados **apilados verticalmente** (original arriba, traducido abajo).
- **D-11:** Cliente: **marked** (o equivalente) + **DOMPurify** antes de insertar HTML en el DOM; cargar por **CDN** en `static/index.html` (sin bundler), coherente con stack actual.
- **D-12:** Preview respeta **modo oscuro** existente (clases/variables ya usadas en `app.css`).
- **D-13:** No ejecutar scripts ni HTML no sanitizado del Markdown traducido (PREV-02 obligatorio).

### Frontmatter YAML selectivo (FM-01, FM-02)

- **D-14:** Campos traducibles (lista blanca **hardcoded** en código): `title`, `description`, `summary`, `tags`, `categories`, `keywords`.
- **D-15:** Campos **nunca** traducibles: `date`, `slug`, `id`, `layout`, `author`, URLs, booleanos, números y claves no listadas en D-14.
- **D-16:** Parsear frontmatter con PyYAML; traducir solo valores string (o elementos string de listas) en claves de la whitelist; **reconstruir YAML** preservando tipos y orden razonable.
- **D-17:** Si el bloque `---` … `---` no es YAML válido: **proteger el bloque entero** (comportamiento actual, sin traducción parcial).

### Parser — comentarios en fences (PARS-01, PARS-02)

- **D-18:** Lenguajes en Fase 2: etiquetas fence `python`, `javascript`, `typescript`, `html`, `xml` (misma familia que ROADMAP PARS-01/02).
- **D-19:** Reglas de comentario: `#` en python; `//` en javascript/typescript; `<!-- ... -->` en html/xml — análogo al patrón shell existente en `src/parser.py`.
- **D-20:** Edge cases (shebangs, URLs en comentarios, `#` en strings, directivas pragma): **criterio en tests** — Claude/plan define casos mínimos; no traducción agresiva «cualquier línea con prefijo».

### Claude's Discretion

- Esquema JSON exacto del informe de validación y mapeo check → warn vs error.
- Versiones CDN de marked/DOMPurify y estilos del preview (tipografía, prose).
- Integración validación en `TranslateResult` vs endpoint separado.
- Casos límite de comentarios traducibles por lenguaje (tabla de tests en plan).
- Si la preview en pestañas Archivo/Lote es solo post-traducción o también en editor únicamente (mínimo: editor; extensión a archivo si bajo esfuerzo).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requisitos y roadmap

- `.planning/REQUIREMENTS.md` — VAL-01…03, PREV-01…02, PARS-01…02, FM-01…02
- `.planning/ROADMAP.md` — Phase 2 success criteria
- `.planning/phases/01-production-table-stakes/01-CONTEXT.md` — pipeline, UI patterns, deferred items

### NOTEBOOK y research

- `NOTEBOOK.md` §4 (Preview), §6 (Validación), §7 (Comentarios), §8 (Frontmatter)
- `.planning/research/SUMMARY.md` — Phase B deliverables (`validator.py`, marked + DOMPurify)
- `.planning/research/PITFALLS.md` — fences, anchors, XSS preview (#1, #2, #4, #5, #21)

### Código base

- `src/parser.py` — segmentación, shell comments, frontmatter protegido
- `src/pipeline.py` — punto de integración post-traducción
- `src/main.py` — respuestas API y batch ZIP
- `static/js/app.js`, `static/index.html`, `static/css/app.css` — UI vanilla

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `translate_markdown()` / `TranslateResult` — enganchar validador al final del pipeline
- `segment_markdown`, `reassemble`, `SHELL_COMMENT` / `_is_shell_fence` — extender con registries por lang
- Panel colapsable Glosario en `app.js` — patrón para panel Validación y preview
- `tests/test_parser.py` — ampliar con fixtures por lenguaje

### Established Patterns

- Sin bundler: scripts CDN en `index.html`
- Errores y mensajes UI en español; contenido demo en inglés
- Guards `?.` y `setHtml()` en `app.js` tras lecciones Fase 1 caché

### Integration Points

- Pipeline retorna contenido + metadatos → validador compara con input original guardado en handler
- Batch ZIP en `main.py` — añadir `validation.json` por entrada
- CLI `file`/`dir`/`batch` — flag `--strict` consulta informe antes de escribir salida

</code_context>

<specifics>
## Specific Ideas

- Validación: panel bajo resultado, estilo Glosario; lote con un JSON por archivo.
- Preview: dual render bajo texto plano; sync al traducir; stack en móvil.
- Frontmatter: whitelist amplia (incl. tags, categories, keywords) pero fija en código.
- Parser: alcance ROADMAP (python, js/ts, html/xml); prudencia en edge cases vía tests.

</specifics>

<deferred>
## Deferred Ideas

- Alerta longitud segmento >300% — backlog o fase posterior
- Lista blanca frontmatter configurable por `.env` / `config.yaml` — usuario eligió hardcoded
- Lenguajes extra NOTEBOOK (ruby, java, go, sql) — fuera de Fase 2
- Toggle «modo estricto» en UI web — solo `--strict` CLI en Fase 2
- SSE progreso lote — Phase 3
- Diff visual original/traducido — Phase 5

</deferred>

---

*Phase: 02-trust-qa*
*Context gathered: 2026-05-28*
