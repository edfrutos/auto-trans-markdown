# Phase 5: Editorial & Pro Workflow - Context

**Gathered:** 2026-05-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Flujo **profesional editorial**: revisar y refinar traducciones, comparar con el original, automatizar watch/árbol de docs, tono formal/informal, historial opt-in y export HTML. Incluye **fallback DeepL → OpenAI** cuando el proveedor primario falla.

**Depende de:** Phase 4 (multi-destino, Docker, pipeline unificado, validación UI).

**Fuera de alcance:** PDF (V2-01), plugins IDE (V2-02), multi-tenant (V2-03), Redis (V2-04), auth obligatorio, bundler frontend.

</domain>

<decisions>
## Implementation Decisions

### Fallback proveedor (FALL-01)
- **D-01:** Variable `TRANSLATION_FALLBACK=openai` (opcional). Solo aplica si `TRANSLATION_PROVIDER=deepl` y existe `OPENAI_API_KEY`.
- **D-02:** Disparadores: idioma no soportado DeepL, cuota/rate limit, errores HTTP 4xx/5xx recuperables de DeepL. Un intento fallback por lote/chunk (no bucle infinito).
- **D-03:** Log `warning` cuando se usa fallback; respuesta API incluye campo opcional `provider_used` en translate response.

### Tono / formalidad (TONE-01)
- **D-04:** Valores UI/API/CLI: `tone` = `auto` | `formal` | `informal` (default `auto`).
- **D-05:** DeepL: mapear a `formality=more|less` cuando tone ≠ auto; omitir si auto.
- **D-06:** OpenAI: apéndice breve al system/user prompt según tone (formal: usted/registro técnico; informal: tuteo natural).
- **D-07:** Propagar `tone` en `TranslateOptions`, FormData, CLI `--tone`.

### Modo revisión (REV-01, REV-02)
- **D-08:** Flujo **draft → edit → finalize**: `POST /api/translate/draft` devuelve segmentos traducibles con `{ index, original, translated, doubtful }`; `POST /api/translate/finalize` recibe `{ segments: {index: text}, source_content }` y reensambla + valida.
- **D-09:** UI: panel «Revisión» colapsable bajo preview; textarea por segmento; botón «Confirmar y exportar» llama finalize.
- **D-10 (Claude):** Heurística `doubtful`: (a) check validación `warning|error` a nivel documento, (b) ratio longitud traducción/original fuera de [0.3, 3.0], (c) traducción idéntica al original en segmento >20 chars alfabéticos. Flag booleano por segmento.
- **D-11:** Modo revisión en **editor y archivo único** (no lote en v1 Fase 5 — lote sigue flujo directo).

### Diff visual (DIFF-01)
- **D-12:** Vista **lado a lado** bajo tabs Preview | Diff en panel resultado.
- **D-13:** Solo **texto traducible** (lista de segmentos alineados); bloques protegidos mostrados atenuados en columna original como referencia contextual mínima (primera línea del segmento anterior protegido omitido — solo pares original/traducido).
- **D-14:** Librería **`diff-match-patch`** vía CDN (sin bundler); resaltado inserciones/eliminaciones en par traducible.

### Watch CLI (WATCH-01)
- **D-15:** Comando `md-translate watch <input_dir> -o <output_dir> -t es` usando **watchdog** ≥6.0.
- **D-16:** Debounce **2 s** tras último evento write; traduce solo `.md|.markdown|.mdx`; salida `stem.{lang}.md` (multi `-t es,en` soportado).
- **D-17:** Ctrl+C limpio; log una línea por archivo procesado.

### Árbol con .gitignore (TREE-01)
- **D-18:** Flag CLI `--respect-gitignore` en `dir` y `batch` (default **true** en `dir` cuando hay `.gitignore` en raíz).
- **D-19:** Parser **stdlib** de `.gitignore` (patrones básicos, negación `!`, sin reglas git avanzadas de subdir anidadas profundas — documentar limitación).
- **D-20:** Siempre ignorar además: `node_modules/`, `.git/`, `.venv/`, `__pycache__/`.

### Historial (HIST-01)
- **D-21:** **localStorage** opt-in (toggle en UI «Guardar historial local»); default **off**.
- **D-22:** Entradas: `{ id, ts, mode, targetLangs, sourceLang, segmentCount, filename? }` — **sin contenido** del documento ni API keys. Máx 20 entradas FIFO.
- **D-23:** Botón «Borrar historial» en UI.

### Export HTML (EXPORT-01)
- **D-24:** Botón «Export HTML» tras traducción; generación **client-side** con `marked` + CSS embebido en blob descargable (autocontenido).
- **D-25:** Sin endpoint server obligatorio; opcional CLI `md-translate export doc.es.md -o doc.html` reutilizando módulo Python mínimo `html_export.py` (markdown→HTML simple).

### Claude's Discretion
- Orden exacto de planes y tests por requisito.
- Estilos CSS diff/review en `app.css`.
- Nombre exacto de endpoints draft/finalize vs extend translate.

</decisions>

<canonical_refs>
## Canonical References

- `.planning/REQUIREMENTS.md` — REV-01…02, FALL-01, DIFF-01, WATCH-01, TREE-01, TONE-01, HIST-01, EXPORT-01
- `.planning/ROADMAP.md` — Phase 5 success criteria
- `NOTEBOOK.md` §12–19 — revisión, fallback, diff, watch, árbol, tono, historial, export
- `.planning/research/STACK.md` — watchdog, formality
- `src/pipeline.py`, `src/parser.py`, `src/translator.py`, `src/validator.py`
- `static/js/app.js` — preview, validation panel (Phase 2)

</canonical_refs>

<deferred>
## Explicitly Out of Phase

| Item | Reason | Where |
|------|--------|-------|
| Revisión en lote/jobs | Complejidad UX | Backlog 999.x |
| PDF export | V2-01 | v2 |
| Historial server-side | Privacidad | v2 |
| diff-match-patch en backend | Solo UI | — |

</deferred>
