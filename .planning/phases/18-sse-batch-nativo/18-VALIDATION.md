---
phase: 18
slug: sse-batch-nativo
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-06-12
revised: 2026-06-12
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.x (backend Python) |
| **Config file** | `pyproject.toml` — sección `[tool.pytest.ini_options]` |
| **Quick run command** | `pytest tests/test_jobs.py -q` |
| **Full suite command** | `pytest tests/ -q` |
| **Build verify command** | ver nota (1) |
| **Estimated runtime (pytest quick)** | ~5 s |
| **Estimated runtime (pytest full)** | ~15 s |
| **Estimated runtime (xcodebuild)** | ~30–90 s (incremental ~30 s; build limpio ~90 s) |

**(1)** Comando completo de build:

```bash
xcodebuild -project macos/MDTranslator/MDTranslator.xcodeproj \
  -scheme MDTranslator -destination 'platform=macOS' build \
  2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

**Nota:** Los Xcode Unit Tests no existen en el proyecto actualmente. Esta fase añade únicamente código Swift nuevo; los tests de backend Python ya cubren `src/jobs.py`. Los criterios de aceptación de SSE-02 y SSE-04 (progreso visual en sheet y Dock) son manuales — ver sección Manual-Only.

---

## Sampling Rate

- **Después de cada commit de tarea:** `pytest tests/test_jobs.py -q` (~5 s)
- **Después de cada plan completo (wave):** `pytest tests/ -q` (~15 s) + xcodebuild build (nota 1) (~30–90 s)
- **Antes de `/gsd:verify-work`:** Suite completa verde + verificación manual de la app
- **Latencia máxima de feedback:** ~90 s (xcodebuild incremental ~30 s + pytest ~15 s)

---

## Per-Task Verification Map

Comando de build abreviado en la tabla como **"xcodebuild build"** — texto completo en nota (1) arriba.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 18-01-T1 | 01 | 1 | SSE-01, SSE-04 | T-18-01 | NSOpenPanel filtra `.md`; solo URLs `.md` pasan a `prepareWith` | build | xcodebuild build | ✅ Commands.swift | ⬜ pending |
| 18-01-T2 | 01 | 1 | SSE-01, SSE-04 | T-18-02, T-18-03 | URL hardcodeada a `127.0.0.1:{port}`; flag `-j` impide path traversal | build + unit | xcodebuild build + `pytest tests/test_jobs.py -q` | ✅ nuevo BatchJobManager.swift | ⬜ pending |
| 18-02-T1 | 02 | 2 | SSE-02, SSE-03 | T-18-06, T-18-08 | Mensajes de error del backend como texto plano en SwiftUI Text() | build + unit | xcodebuild build + `pytest tests/test_jobs.py -q` | ✅ nuevo BatchSheet.swift | ⬜ pending |
| 18-03-T1 | 03 | 3 | SSE-01, SSE-03 | T-18-09 | `.openBatchSheet` solo activa `showBatchSheet = true`; emisor ya llamó `prepareWith` | build | xcodebuild build | ✅ AppDelegate.swift | ⬜ pending |
| 18-03-T2 | 03 | 3 | SSE-01..04 | T-18-09, T-18-10 | `.onReceive(.openBatchSheet)` solo activa la sheet; sin lógica de negocio | build + full suite | xcodebuild build + `pytest tests/ -q` | ✅ MDTranslatorApp.swift | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

- `tests/test_jobs.py` ya existe y cubre `create_batch_job`, `cancel_job`, `file_done`, `complete`.
- `pyproject.toml` ya tiene `[tool.pytest.ini_options]` con `pythonpath = ["."]`.
- No se instalan frameworks nuevos.
- Los criterios de aceptación visuales (SSE-02, SSE-04) son manuales — ver sección siguiente.

---

## Manual-Only Verifications

*Estos comportamientos se verifican en el checkpoint humano T3 del plan 18-03.*

### SSE-02 — Progreso determinado en sheet

**Requirement:** SSE-02
**Why manual:** No hay Xcode Unit Tests en el proyecto; requiere inspección visual de SwiftUI en ejecución.

**Test instructions:**

1. Compilar y ejecutar la app (⌘B + ⌘R en Xcode).
2. File → "Traducir lote…" (o ⌘⇧B) → seleccionar 3–5 archivos `.md`.
3. Pulsar "Traducir".
4. Verificar que la barra global avanza archivo a archivo (no salta de 0% a 100%).
5. Verificar que el nombre del archivo en curso cambia con cada archivo.

### SSE-04 — Progreso determinado en el Dock

**Requirement:** SSE-04
**Why manual:** El progreso del Dock requiere app en ejecución; no testeable con pytest.

**Test instructions:**

1. Con el lote corriendo del paso anterior, mover la ventana fuera de foco o minimizarla.
2. El icono del Dock debe mostrar una barra de progreso determinada que avanza.
3. Al terminar, la barra desaparece.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify (xcodebuild build) or are manual-only with documented instructions
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references — no MISSING entries en la tabla
- [x] No watch-mode flags en ningún comando
- [x] Feedback latency documentada: pytest ~15 s, xcodebuild incremental ~30–90 s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved
