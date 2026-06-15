# Requirements: MarkDown Auto Translator v3.2 — Native Workflow & Sync

## Overview

Milestone v3.2 completa el flujo de trabajo nativo de la app macOS: progreso real en lotes (SSE), integración con Finder (asociación de `.md`), export PDF sin dependencias nuevas (WKWebView) y sincronización de glosario/TM entre Macs vía iCloud Drive. **Sin Apple Developer account** — todas las features están especificadas para funcionar con firma ad-hoc.

**Stack:** Swift 6.3.2 / Xcode 26.5 / macOS 14+ · backend FastAPI existente (endpoints SSE ya disponibles en `src/jobs.py`)

---

## v3.2 Requirements

### SSE — Progreso real en batch nativo (Phase 18)

- [ ] **SSE-01**: La app consume `GET /api/translate/batch/jobs/{id}/events` con `URLSession` (bytes stream) y parsea los eventos SSE existentes (`file_start`, `segment_progress`, `file_done`, `error`, `complete`)
- [ ] **SSE-02**: La vista de lote muestra progreso determinado: barra global (archivos completados/total) + archivo en curso con su progreso de segmentos
- [ ] **SSE-03**: Botón "Cancelar" llama a `DELETE /api/translate/batch/jobs/{id}` (cancelación cooperativa ya implementada en backend)
- [ ] **SSE-04**: El progreso del Dock (`DockProgressManager`, Phase 13) se alimenta de los eventos SSE en lugar del estado indeterminado actual

### ASSOC — Asociación de archivos .md (Phase 19)

- [ ] **ASSOC-01**: `CFBundleDocumentTypes` en Info.plist declara `net.daringfireball.markdown` (+ `public.plain-text` como secundario) con rol Viewer/Editor
- [ ] **ASSOC-02**: Abrir un `.md` vía doble clic / "Abrir con" carga el archivo en el editor reutilizando la ruta de apertura del Dock (`application(_:open:)`, Phase 13)
- [ ] **ASSOC-03**: La app NO se autoproclama handler por defecto de `.md`; el usuario decide vía "Abrir con → Cambiar todo…" (documentado en README)

### PDFN — Export PDF nativo (Phase 20)

- [ ] **PDFN-01**: Botón "Export PDF" en la app genera el PDF con `WKWebView.createPDF(configuration:)` a partir del HTML de `src/html_export.py` — sin WeasyPrint ni dependencias nativas nuevas en el bundle
- [ ] **PDFN-02**: El PDF se guarda vía panel nativo (`NSSavePanel`) o en la carpeta de salida configurada, con revelado en Finder
- [ ] **PDFN-03**: Paridad visual razonable con el export HTML (mismos estilos); paginación A4 con márgenes correctos

### SYNC — Glosario y TM en iCloud Drive (Phase 21)

- [ ] **SYNC-01**: Opción en Configuración: "Sincronizar datos vía iCloud Drive" — mueve `glossary.yaml` y `translation_memory.db` a `~/Library/Mobile Documents/com~apple~CloudDocs/MDTranslator/` (sin entitlements; es una carpeta normal)
- [ ] **SYNC-02**: El backend recibe las rutas vía variables de entorno (`GLOSSARY_PATH`, `TM_DB_PATH`) inyectadas por `ServerManager` — requiere parametrizar las rutas en `src/glossary.py`/`src/memory.py` (hoy semi-fijas)
- [ ] **SYNC-03**: Migración asistida: al activar, copia los datos actuales a iCloud; al desactivar, los devuelve a `data/` local; nunca borra sin copia
- [ ] **SYNC-04**: Manejo de conflicto básico para la TM SQLite: lock advisory o aviso si el archivo está en uso por otra máquina (documentar limitación: SQLite sobre iCloud Drive no es multi-escritor)

---

## Out of Scope (v3.2)

| Item                                     | Motivo                                                                                    |
| ---------------------------------------- | ----------------------------------------------------------------------------------------- |
| Universal Binary (Intel)                 | Sin demanda; python-bundle x86_64 duplicaría el trabajo de empaquetado                    |
| Notarización / Sandbox / MAS (Phase 17)  | Requiere Apple Developer Program                                                          |
| CloudKit / contenedor iCloud propio      | Requiere Apple Developer Program; iCloud Drive como carpeta cubre el caso de uso          |
| WeasyPrint en el bundle                  | Sustituido por WKWebView.createPDF (PDFN-01)                                              |
| Redis jobs (V2-04), multi-tenant (V2-03) | Deuda servidor/equipo, sin relación con la app nativa; re-evaluar en milestone de backend |

---

## Notas técnicas / riesgos

- **SSE con URLSession**: usar `URLSession.bytes(for:)` y parseo manual de líneas `data:` — no hay cliente SSE en Foundation. El token Bearer (si `API_TOKEN` activo) ya se soporta por query param en el backend (`?token=`).
- **WKWebView.createPDF** pagina como "una página larga" por defecto; para A4 real usar `NSPrintOperation` sobre la WKWebView o `UIGraphicsPDFRenderer`-equivalente con `pageSize` en `WKPDFConfiguration` (verificar en research de la fase).
- **SQLite en iCloud Drive**: el demonio `bird` sincroniza el fichero completo; con WAL activo puede corromper. Usar `PRAGMA journal_mode=DELETE` cuando la TM esté en iCloud, o checkpoint+close agresivo.
- Pitfalls heredados aplicables: TCC se resetea al re-firmar (pitfall 11), una sola copia instalada (pitfall 14), `rm -rf $(APP)` antes de exportar (pitfall 9).

---

## Traceability

| REQ-ID       | Phase    | Status   |
| ------------ | -------- | -------- |
| SSE-01..04   | Phase 18 | Pending  |
| ASSOC-01..03 | Phase 19 | Pending  |
| PDFN-01..03  | Phase 20 | Pending  |
| SYNC-01..04  | Phase 21 | Pending  |

**Coverage:** 14/14 requisitos v3.2 mapeados (100%) ✓

---

## Archivos de milestones anteriores

- [v1.0](milestones/v1.0-REQUIREMENTS.md) · [v2.0](milestones/v2.0-REQUIREMENTS.md) · [v3.0](milestones/v3.0-REQUIREMENTS.md) · [v3.1](milestones/v3.1-REQUIREMENTS.md)

---

*Last updated: 2026-06-12 — milestone v3.2 definido (4 fases, 14 requisitos); pendiente research y planificación de Phase 18*
