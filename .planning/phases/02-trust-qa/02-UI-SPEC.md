# UI-SPEC: Validation Panel & Markdown Preview (Phase 2)

**Phase:** 02-trust-qa
**Requirements:** VAL-02, PREV-01, PREV-02
**Design system:** Existing Plus Jakarta Sans + teal palette — NO shadcn, NO bundler

---

## Overview

Añadir (1) panel colapsable «Validación» bajo el área de resultado tras traducir y (2) paneles de vista previa HTML sanitizada (Original | Traducido) bajo los textareas del editor. Mantiene coherencia con el panel Glosario (Fase 1) y tokens existentes en `static/css/app.css`.

---

## Layout — Editor tab

```json
[ Idioma origen | Idioma destino ]
[ ▼ Glosario ]  ← existing

[ Tabs Editor | Archivo | Lote ]

Editor panel:
  [ Textarea original (#source-md) ]
  [ Textarea traducido (#result-md) ]  ← existing pattern

  [ Preview Original | Preview Traducido ]  ← NEW dual render row
    ├─ #preview-source.prose-preview
    └─ #preview-result.prose-preview

[ ▼ Validación ]  ← NEW collapsible (default collapsed, visible after translate)
    ├─ Resumen: «3 pass · 1 warn · 0 error»
    └─ Lista checks con icono estado

[ Traducir ] [ Descargar ] [ Limpiar memoria ]
[ Progress / Status ]
```

**Placement rationale:** Preview junto al texto plano para comparación visual; validación bajo resultado (post-traducción) como Glosario bajo controles globales.

---

## Validation Panel (VAL-02)

### Container

- `<section id="validation-section" class="hidden mb-6">` — visible only after successful translate (editor/file/batch summary)
- Toggle: `#validation-toggle` with `aria-expanded`, `aria-controls="validation-panel"`
- Heading: «Validación» — `text-sm font-semibold text-ink`
- Chevron: reuse `.glossary-chevron` rotation pattern
- Panel: `#validation-panel` hidden by default

### Summary row

- `#validation-summary` — `text-sm text-ink-muted`
- Format: `{pass} correctos · {warn} avisos · {error} errores`
- Overall badge when errors > 0: `text-amber-600` (warn) / `text-red-600` (error) — **does NOT block download** (D-01)

### Check list

- `#validation-checks` — `<ul class="space-y-2 text-sm">`
- Each item:
  - Icon: ✓ pass (`text-teal-600`), ⚠ warn (`text-amber-600`), ✗ error (`text-red-600`)
  - Label: check name (Fences, Enlaces, Imágenes, Código inline, Encabezados)
  - Detail: short message from API `validation.checks[].message`

### Data contract (client)

- Expect `validation` object on translate API JSON responses:
  ```json
  {
    "overall": "pass" | "warn" | "error",
    "checks": [
      { "id": "fences", "status": "pass", "message": "..." }
    ]
  }
  ```
- Batch: show aggregate summary in status area; per-file detail optional in batch file list tooltip (discretion — minimum: status message «Lote completado — revisa validation.json en ZIP»)

### Empty / no validation

- If API omits validation (legacy): hide section

---

## Markdown Preview (PREV-01, PREV-02)

### CDN scripts (index.html)

- `marked` — pinned minor version in plan (e.g. 12.x)
- `DOMPurify` — pinned (e.g. 3.x)
- Load before `app.js`; guard if CDN fails: preview panels show «Vista previa no disponible»

### Render flow (app.js)

1. `renderPreview(markdown, targetEl)`:
   - `const raw = marked.parse(markdown, { gfm: true, breaks: false })`
   - `const clean = DOMPurify.sanitize(raw, { USE_PROFILES: { html: true } })`
   - `targetEl.innerHTML = clean` (never assign unsanitized HTML)
2. Call **only** on: successful translate, load sample (`SAMPLE_MD`), file translate complete
3. **Do NOT** bind to `input`/`keyup` on textareas

### Layout

- Wrapper: `#preview-row` — `grid grid-cols-1 md:grid-cols-2 gap-4 mt-4`
- Each panel:
  - Label: «Vista previa — Original» / «Vista previa — Traducido»
  - Container: `div.prose-preview rounded-xl border border-teal-100 bg-white dark:bg-surface p-4 max-h-96 overflow-y-auto`
- Mobile (`< md`): stack vertical — original above translated (D-10)

### Styling (PREV dark mode — D-12)

- `.prose-preview` in `app.css`:
  - Headings, links, code, pre: use existing `--ink`, `--ink-muted`, `--primary` CSS variables
  - `pre`, `code`: `bg-teal-50/80` light; `dark:` variant with `surface` tones
  - Links: `text-primary hover:underline`
  - Images: `max-w-full h-auto rounded-lg`

### XSS safety (PREV-02)

- No `innerHTML` with raw marked output
- Strip `<script>`, event handlers via DOMPurify default + `FORBID_TAGS: ['script', 'iframe']`
- Test fixture: `[click me](javascript:alert(1))` renders inert link

---

## File & Batch tabs

### File tab

- After file translate: show validation panel (same component)
- Preview: optional minimum — if effort low, dual preview under file result textarea; else defer to editor-only (planner discretion)

### Batch tab

- Post batch: `showStatus('… validation.json incluido en ZIP', 'success')`
- No per-file preview in batch UI (Phase 3 scope for progress)

---

## Accessibility

- Validation toggle: keyboard operable, `aria-expanded` synced
- Preview panels: `aria-label` on containers; headings visible as `<p class="text-xs font-medium text-ink-muted">`
- Status icons: decorative with `aria-hidden="true"`; text conveys state

---

## Anti-patterns (do NOT)

- Bundler / npm build step
- Live preview on every keystroke
- Block download in UI on validation errors
- Toggle «modo estricto» in web UI (CLI only — D-02 scope)
- raw `marked` output to DOM

---

*UI-SPEC created: 2026-05-28 — Phase 2 Trust & QA*
