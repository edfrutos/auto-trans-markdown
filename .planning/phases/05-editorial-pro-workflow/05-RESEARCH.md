# Phase 5 Research

## Fallback DeepL → OpenAI (FALL-01)

**Patrón:** En `_translate_deepl_batch`, capturar excepciones/errores de cuota e idioma; si `get_fallback_provider()` retorna `openai` y hay clave, delegar a `_translate_openai_batch` con mismo chunk.

**Env:** `TRANSLATION_FALLBACK=openai` (vacío = desactivado).

**Tests:** mock DeepL raise → assert OpenAI called; sin fallback → propagate error.

## Tono (TONE-01)

**DeepL SDK:** `translate_text(..., formality="more"|"less")` — solo algunos idiomas; ignorar error si no soportado.

**OpenAI:** suffix en `SYSTEM_PROMPT` o user message: «Use formal register (usted)» / «Use informal friendly register (tú)».

**API:** `tone` en JSON/Form; default `auto`.

## Modo revisión (REV-01/02)

**Backend:** Reutilizar `segment_markdown`, `collect_translatable`, `translate_segments`, `reassemble`. Nuevo `src/review.py`:

- `build_draft(content, options) -> DraftResult`
- `score_doubtful(original, translated, validation) -> bool`
- `finalize_draft(segments, translations, original_content) -> TranslateResult`

**API models:** `DraftSegment`, `DraftResponse`, `FinalizeRequest`.

## Diff (DIFF-01)

**Frontend:** Tras traducción, guardar `state.draftSegments` desde draft API o derivar de respuesta extendida.

**CDN:** `https://cdn.jsdelivr.net/npm/diff-match-patch@1.0.5/index.js`

**UI:** Dos columnas `.diff-col`; `dmp.diff_main` + `diff_prettyHtml` por segmento.

## Watch (WATCH-01)

**Dep:** `watchdog>=6.0.0` en requirements.txt.

**Pattern:** `Observer` on `input_dir`, filter extensions, debounce con `threading.Timer` o dict last_event.

## Gitignore tree (TREE-01)

**Sin dep externa:** leer `.gitignore` líneas, compilar a fnmatch patterns; helper `should_ignore(path, root, patterns)`.

**Integrar:** `cli.py` `dir_cmd` y `batch_cmd` glob/filter.

## Historial (HIST-01)

**localStorage key:** `md-translate-history` JSON array.

**Opt-in key:** `md-translate-history-enabled` boolean string.

## Export HTML (EXPORT-01)

**Client:** reutilizar `marked` ya cargado; template:

```html
<!DOCTYPE html><html><head><meta charset="utf-8"><style>...</style></head><body>...</body></html>
```

**CLI optional:** `markdown` stdlib no render MD — usar `markdown` PyPI ligero OR simple regex fallback. Prefer **`markdown`>=3.5** single dep for CLI export only.

## Plan waves

| Wave   | Plans               | Focus                                       |
| ------ | ------------------- | ------------------------------------------- |
| 1      | 05-01, 05-02        | translator fallback + tone                  |
| 2      | 05-03, 05-04, 05-05 | review API/UI, diff UI, watch+gitignore CLI |
| 3      | 05-06               | history + HTML export                       |
