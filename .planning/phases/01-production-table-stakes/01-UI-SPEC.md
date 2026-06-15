# UI-SPEC: Glossary Panel & Memory Clear (Phase 1)

**Phase:** 01-production-table-stakes
**Requirements:** GLOS-02, TM-03 (UI portion)
**Design system:** Existing Plus Jakarta Sans + teal palette — NO shadcn, NO new bundler

---

## Overview

Añadir panel colapsable «Glosario» debajo de los selectores de idioma y botón «Limpiar memoria» en la barra de acciones. Mantiene coherencia visual con cards/tabs existentes en `static/index.html` y tokens Tailwind (`primary`, `surface`, `ink`).

---

## Layout

```json
[ Header — unchanged ]

[ Hero — unchanged ]

[ Idioma origen | Idioma destino ]  ← existing grid

[ ▼ Glosario ]  ← NEW collapsible section (default collapsed)
    ├─ Tabla entradas (término | traducción | no traducir | acciones)
    ├─ [+ Añadir entrada] [Guardar glosario]
    └─ hint: "Se aplica en editor, archivo y lote"

[ Tabs Editor | Archivo | Lote ]  ← unchanged

[ ... panels ... ]

[ Traducir ] [ Descargar ] [ Limpiar memoria ]  ← NEW tertiary button
[ Progress / Status ]
```

**Placement rationale:** Glosario junto a idiomas porque reglas son por par origen→destino; memoria en action bar como operación infrecuente de mantenimiento.

---

## Glossary Panel (GLOS-02)

### Container

- `<section id="glossary-section" aria-labelledby="glossary-heading">`
- Toggle: `<button id="glossary-toggle" aria-expanded="false" aria-controls="glossary-panel">`
- Heading: «Glosario» — `text-sm font-semibold text-ink`
- Chevron icon rotates on expand (CSS transition 200ms)
- Panel: `#glossary-panel` hidden by default (`hidden` class)

### Table

- Wrapper: `overflow-x-auto rounded-xl border border-teal-100`
- Table classes: `w-full text-sm`
- Header row: `bg-teal-50/80 text-ink-muted font-medium`
- Columns:
  1. **Término** — `<input type="text" class="input-inline">` placeholder «API Gateway»
  2. **Traducción** — input; disabled + aria-disabled when «No traducir» checked
  3. **No traducir** — checkbox `type="checkbox"` center-aligned
  4. **Acciones** — icon button eliminar fila (trash), `aria-label="Eliminar entrada"`

### Empty state

- Single row message: «No hay entradas. Añade términos para forzar traducciones consistentes.»
- `text-ink-muted text-sm py-4 text-center`

### Actions

- **Añadir entrada:** `btn-secondary text-sm` — append blank row client-side
- **Guardar glosario:** `btn-primary text-sm` — `PUT /api/glossary` with assembled YAML structure
- Loading state on save: disable buttons, label «Guardando…»

### Data mapping (UI ↔ YAML)

- Row with «No traducir» checked → term added to `do_not_translate[]`
- Row with translation filled → `pairs[{source}-{target}][term] = translation`
- Source/target from `#source-lang` and `#target-lang` at save time (if source=auto, use `auto-{target}` key)
- On load (`GET /api/glossary`): flatten `do_not_translate` + current pair into table rows

### Feedback

- Success: `showStatus('Glosario guardado correctamente', 'success')`
- Error: `showStatus(message, 'error')` from API detail
- Unsaved changes: optional dot indicator on toggle button (discretion)

---

## Memory Clear Button (TM-03)

### Control

- `<button type="button" id="btn-clear-memory" class="btn-secondary text-sm">`
- Label: «Limpiar memoria»
- Icon: optional eraser/trash 16px left of label
- Position: action bar after `#btn-download`, visible always (not mode-dependent)

### Interaction

1. Click → `confirm('¿Eliminar todas las traducciones en cache? Esta acción no se puede deshacer.')`
2. If confirmed → `DELETE /api/memory`
3. Success → `showStatus('Memoria de traducción vaciada', 'success')`
4. Error → `showStatus(..., 'error')`

### Accessibility

- Button has explicit label (no icon-only)
- Confirm dialog is browser native (Phase 1); modal custom deferred

---

## Visual Tokens (must match existing)

| Token           | Value                                   | Usage                               |
| --------------- | --------------------------------------- | ----------------------------------- |
| primary         | `#0D9488`                               | Save button, links                  |
| surface.card    | `#FFFFFF`                               | Panel background                    |
| ink / ink-muted | `#134E4A` / `#475569`                   | Text                                |
| border          | `border-teal-100`                       | Panel/table borders                 |
| input           | `.input-select` / `.input-inline` (new) | Match select styling from `app.css` |

### Dark mode

- Reuse `[data-theme="dark"]` variables from `app.css`
- Table header: `dark:bg-teal-900/30`
- Inputs: inherit existing dark input styles

---

## CSS Additions (`static/css/app.css`)

```css
.input-inline {
  /* mirror .input-select padding/font, width 100%, border teal-100 */
}
.glossary-chevron { transition: transform 0.2s; }
.glossary-chevron-expanded { transform: rotate(180deg); }
```

---

## JS State (`static/js/app.js`)

```javascript
state.glossary = {
  loaded: false,
  entries: [],      // { term, translation, doNotTranslate }
  dirty: false,
  expanded: false,
};
```

Functions to add:

- `loadGlossary()` — GET on page init after languages
- `renderGlossaryTable()`
- `saveGlossary()` — PUT assembled body
- `clearMemory()` — DELETE with confirm

Wire `#glossary-toggle`, `#btn-add-glossary`, `#btn-save-glossary`, `#btn-clear-memory`.

---

## Optional UX Fixes (from 00-UI-REVIEW.md)

If touched in same plan, include:

1. Disable `#btn-translate` until `loadLanguages()` succeeds
2. Retry link on language load failure
3. `aria-busy` on `#target-lang` during fetch

Not blocking for GLOS-02 acceptance; implement if low cost during 01-04.

---

## Acceptance Criteria

- [ ] Panel glosario expandible sin romper layout mobile (stack vertical)
- [ ] CRUD via API persiste en `glossary.yaml`
- [ ] Glosario cargado al iniciar página
- [ ] Traducción editor/archivo/lote usa reglas guardadas (via pipeline, no re-fetch manual)
- [ ] Botón limpiar memoria vacía TM y muestra confirmación
- [ ] Keyboard: toggle glossary via Enter/Space on focused toggle button
- [ ] Dark mode coherente

---

*UI-SPEC Phase 1 — 2026-05-28*
