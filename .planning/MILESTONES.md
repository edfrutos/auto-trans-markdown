# Milestones

## v1.0 NOTEBOOK A→E (Shipped: 2026-05-29)

**Phases:** 6 (0–5) · **Plans:** 29 · **Tests:** 137 passed

**Delivered:** Traductor Markdown production-ready — pipeline unificado, glosario, memoria TM, validación, preview, lote SSE, multi-destino, Docker, flujo editorial (revisión, diff, watch, tono, export HTML).

**Archives:** [ROADMAP](milestones/v1.0-ROADMAP.md) · [REQUIREMENTS](milestones/v1.0-REQUIREMENTS.md) · [AUDIT](milestones/v1.0-MILESTONE-AUDIT.md)

**Tag:** `v1.0`

---

## v2.0 Production Polish & PDF (Shipped: 2026-05-29)

**Phases:** 2 (6–7) · **Plans:** 7 · **Tests:** 148 passed

**Delivered:** Cierre deuda audit v1.0 (tone batch ZIP, Bearer UI/SSE, tabs multi-idioma editor, 02-VERIFICATION) + export PDF WeasyPrint opcional (CLI, API, UI, README).

**Key accomplishments:**

- Tech debt: paridad `--tone` en batch ZIP; auth completa con `API_TOKEN` + SSE query token
- Editor multi-destino: tabs para preview/descarga por idioma
- Artefacto GSD fase 2 retroactivo (`02-VERIFICATION.md`)
- PDF: `pdf_export.py`, `export --format pdf`, `POST /api/export/pdf`, botón Export PDF

**Deferred to v2.1+:** Redis jobs (V2-04), multi-tenant (V2-03), plugin editor (V2-02), lockfile (LOCK-01)

**Archives:**

- [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md)
- [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md)
- [v2.0-MILESTONE-AUDIT.md](milestones/v2.0-MILESTONE-AUDIT.md)

**Tag:** `v2.0`

---

## v3.0 macOS Native App (Shipped: 2026-06-09)

**Phases:** 4 (9–12) · **Plans:** 12 · **Tests:** 148 passed

**Delivered:** App nativa Swift/SwiftUI para macOS que embebe el backend FastAPI como subprocess autocontenido (CPython 3.11.15 standalone). Navegación completa, API keys en Keychain, paridad funcional con la web UI (editor, archivo, lote, glosario, TM), notificaciones nativas, MenuBarExtra, DMG con firma ad-hoc y auto-update Sparkle (EdDSA).

**Key accomplishments:**

- `scripts/build-python-bundle.sh` — CPython portátil + deps con uv (absorbe Phase 8 / LOCK-01)
- `ServerManager` — puerto dinámico, health check, shutdown graceful, recuperación de huérfanos
- `make dmg` — firma bottom-up de dylibs, INSTALL.txt, appcast firmado
- 26/26 requisitos completados

**Deferred to v3.1:** SSE batch nativo, Universal Binary, notarización.

**Archives:** [v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md)

**Tag:** — (sin tag; commit `dd1a04a`)

---

## v3.1 Native macOS Polish (Shipped: 2026-06-11)

**Phases:** 3 (13–15) · **Tests:** 148 passed

**Delivered:** Integración macOS de primera clase (Dock drag&drop + progreso, Open Recent, Services "Traducir con MDTranslator"), operación por teclado (hotkey global ⌥⇧T, ⌘↩, ⌘⇧C, undo en WKWebView), estimación de coste en vivo, bundle reducido a 116 MB (< 120 MB), crash reporter Sparkle y `make smoke-test`.

**Pending minor:** registrar medición de arranque en frío (PERF-03) en `docs/performance.md`.

**Deferred:** Phase 16 Distribution Upgrade (notarización, Sandbox, MAS) — bloqueada por Apple Developer Program.

**Distribution (Phase 16, 2026-06-12):** GitHub Release v3.1 publicada con DMG (firma ad-hoc) + ZIP Sparkle + SHA-256; appcast en producción y actualización automática verificada end-to-end. Durante el release se corrigieron dos bugs críticos del pipeline: export anidado de `cp -R` en el Makefile (distribuía el bundle v3.0 rancio) y usuario GitHub erróneo (`edefrutos` → `edfrutos`) en SUFeedURL/appcast.

**Archives:** [v3.1-REQUIREMENTS.md](milestones/v3.1-REQUIREMENTS.md)

**Tags:** `v3.1` (release final, `2c6fb32`)

---
