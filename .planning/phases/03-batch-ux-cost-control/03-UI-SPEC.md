# UI-SPEC: Batch Progress, Cancel & Cost Estimate (Phase 3)

**Phase:** 03-batch-ux-cost-control
**Requirements:** JOB-02, JOB-03, COST-02
**Design system:** Existing Plus Jakarta Sans + teal palette — NO shadcn, NO bundler

---

## Overview

Reemplazar la barra de progreso simulada (30%) en traducción por lote con **progreso SSE real**: barra global + lista de archivos con estados. Añadir botón **Cancelar** con confirmación, resumen final parcial/errores, y bloque **Estimación** inline en pestañas Lote y Archivo (no Editor).

---

## Layout — Batch tab

```
[ Idioma origen | Idioma destino ]
[ ▼ Glosario ]  ← existing

[ Tabs Editor | Archivo | Lote ]

Batch panel (#panel-batch):
  [ Drop zone + file picker ]  ← existing
  [ #batch-list ]  ← pre-job file names (existing)

  [ #estimate-batch ]  ← NEW inline estimate (hidden until files + langs ready)
    «~70 segmentos · ~12 000 chars · ~$0.02 (gpt-4o-mini)»
    [ #estimate-warn ] optional amber banner if over ESTIMATE_WARN_USD

  [ #batch-progress-section ]  ← NEW (hidden until job starts)
    [ Global progress bar #batch-progress-bar ]
    [ #batch-progress-text ]  «Archivo 3/10 · 45% · README.md»
    [ #batch-file-progress-list ]  ← ul with per-file status icons
    [ #btn-cancel-job ]  «Cancelar» — visible only during active job

  [ Traducir ] [ Descargar ]  ← existing; Cancel replaces loading disable pattern for batch

[ #progress-wrap ]  ← keep for editor/file spinner ONLY; NOT used for batch SSE
```

**Placement rationale:** Estimate above Traducir (user sees cost before click); progress section replaces fake spinner during batch job.

---

## Batch progress (JOB-02)

### Global bar
- Container: `#batch-progress-section` — `class="hidden mb-4"`
- Bar track: reuse `#progress-wrap` styling OR dedicated `#batch-progress-bar` in section (prefer dedicated to avoid editor/file conflict — D-03)
- Width: `(completed_files + current_file_segment_ratio) / total_files * 100`
- Text `#batch-progress-text`: `{current}/{total} archivos · {pct}% · {current_filename}`

### Per-file list
- `#batch-file-progress-list` — `<ul class="space-y-1 text-sm max-h-48 overflow-y-auto">`
- Each `<li data-filename="...">` with icon + name:
  - `pending`: ○ gray (`text-ink-muted`)
  - `active`: spinner or ● teal pulse (`text-primary`)
  - `ok`: ✓ (`text-teal-600`)
  - `error`: ✗ (`text-red-600`)
  - `cancelled`: — (`text-ink-muted`) for unprocessed after cancel

### SSE client flow (app.js)
1. `POST /api/translate/batch/jobs` with FormData (files + langs) → `{ job_id }`
2. `EventSource('/api/translate/batch/jobs/{id}/events')`
3. On events:
   - `file_start`: mark file active, update progress text
   - `segment_progress`: update global bar intra-file (optional sub-percent)
   - `file_done`: mark ok, increment completed
   - `error`: mark file error, continue (D-06)
   - `complete`: close EventSource, show summary, enable download button
4. On `complete` or cancel: `GET .../download` → blob → `state.downloadBlob`

### Summary states
- Full success: `showStatus('10/10 archivos traducidos — validation.json incluido en ZIP.', 'success')`
- Partial: `showStatus('8/10 OK — 2 errores. Revisa errors.json en el ZIP.', 'warning')`
- Cancelled: `showStatus('Cancelado: 5/10 completados. Descarga parcial disponible.', 'warning')` then reset file list after user dismisses or on new job

### Mobile (D-04)
- `#batch-progress-section`: `flex flex-col gap-3`
- File list: `max-h-40 overflow-y-auto` stacked below bar

---

## Cancel button (JOB-03)

- `#btn-cancel-job` — `type="button"`, secondary/danger outline (`border-red-200 text-red-700`)
- Visible only when `state.batchJobActive === true`
- On click:
  1. `if (!confirm('¿Cancelar la traducción en curso?')) return;`
  2. `fetch(DELETE /api/translate/batch/jobs/{id})`
  3. Close EventSource
  4. Offer download if partial available (enable `#btn-download`)
  5. Reset UI: hide progress section, clear job state, show cancellation summary (D-13)

---

## Cost estimate (COST-02)

### Batch tab
- `#estimate-batch` — `text-sm text-ink-muted mb-3 hidden`
- Trigger: when `state.batchFiles.length > 0` and languages selected → debounced `POST /api/translate/estimate` with file list
- Display format (D-15): `` `~${segments} segmentos · ~${chars} chars · ~$${cost} (${model})` ``
- Warning `#estimate-warn`: if `estimate.exceeds_threshold` → `class="text-amber-600 text-sm mt-1"` «Coste estimado superior al umbral configurado»

### File tab
- `#estimate-file` — same pattern when `state.selectedFile` set
- Estimate before Traducir; no extra confirm modal (D-17)

### Editor tab
- **No estimate block** (D-14)

### Loading estimate
- Show «Calculando…» in estimate block while fetch pending
- On error: hide block or show «Estimación no disponible»

---

## File tab integration

- Add `#estimate-file` above Traducir in `#panel-file`
- Keep existing spinner via `setLoading()` for single-file translate (not SSE)

---

## Accessibility

- Progress bar: `role="progressbar"`, `aria-valuenow`, `aria-valuemin="0"`, `aria-valuemax="100"`, `aria-label="Progreso del lote"`
- Cancel: `aria-label="Cancelar traducción por lote"`
- File list items: status conveyed in text, icons `aria-hidden="true"`
- Estimate: `aria-live="polite"` on `#estimate-batch` / `#estimate-file`

---

## Anti-patterns (do NOT)

- Use fake 30% progress for batch mode
- SSE progress in editor tab
- Modal confirm after estimate (only confirm on cancel)
- Block download on partial batch or cancel
- Bundler / npm build

---

*UI-SPEC created: 2026-05-29 — Phase 3 Batch UX & Cost Control*
