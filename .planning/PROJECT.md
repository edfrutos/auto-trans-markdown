# MarkDown Auto Translator

## What This Is

Traductor de archivos Markdown que preserva formato y bloques de código, orientado a documentación técnica y equipos que localizan docs sin romper sintaxis. Incluye interfaz web (editor, archivo, lote), API FastAPI, CLI `md-translate`, glosario, memoria de traducción y proveedores OpenAI o DeepL. Milestones **v1.0** (NOTEBOOK A→E) y **v2.0** (polish + PDF) están **completos**. **v2.1** (lockfile) diferido — incluido en v3.0.

## Core Value

Traducir **solo el texto dirigido al usuario** al idioma destino **sin alterar Markdown ni código**, con coherencia terminológica y coste predecible en lotes grandes.

## Current Milestone: v3.0 macOS Native App

**Goal:** Empaquetar MarkDown Auto Translator como aplicación macOS nativa con UI SwiftUI, backend Python embebido mediante python-build-standalone e integraciones del sistema operativo.

**Target features:**
- SwiftUI nativa: sidebar + editor (texto) + file picker + batch + glosario/TM
- Backend Python (FastAPI) embebido como subprocess dentro del .app bundle
- Drag & drop nativo para archivos .md
- Keychain macOS para API keys (sin `.env`)
- Menubar icon para acceso rápido sin ventana principal
- Notificaciones nativas al completar traducciones batch
- Auto-update con Sparkle framework
- Distribución como DMG con firma ad-hoc

## Requirements

<details>
<summary>Shipped v1.0 (phases 0–5) — NOTEBOOK A→E</summary>

Ver `.planning/milestones/v1.0-REQUIREMENTS.md` para el listado completo (HARD, PIPE, GLOS, TM, CLI, VAL, PREV, JOB, COST, MULTI, DOCKER, SEC, REV, FALL, DIFF, WATCH, TONE, HIST, EXPORT).

</details>

<details>
<summary>Shipped v2.0 (phases 6–7) — Production Polish & PDF</summary>

- ✓ Tech debt audit — DEBT-01 … DEBT-04 (tone batch ZIP, Bearer UI/SSE, editor multi-idioma, 02-VERIFICATION)
- ✓ Export PDF — PDF-01 … PDF-04 (WeasyPrint opcional, CLI, API, UI, README)

Ver `.planning/milestones/v2.0-REQUIREMENTS.md`.

</details>

### Deferred / Backlog

- [ ] Plugin Obsidian o VS Code — V2-02
- [ ] Multi-tenant con API key por usuario — V2-03
- [ ] Redis job store para multi-worker — V2-04
- [ ] Lockfile reproducible — LOCK-01 *(incorporar en v3.0 build system)*

## Context

**Estado actual:** Pipeline segment → translate → reassemble con fachada `pipeline.py`. FastAPI + UI estática. Memoria SQLite. Glosario YAML. Jobs in-memory SSE. Export HTML + PDF (opcional). **148 tests**. Docker documentado.

**Usuarios objetivo:** Desarrolladores, redactores técnicos y equipos que traducen README, docs y artículos Markdown.

**Límites conocidos:** Jobs SSE no persisten (V2-04). Auth Bearer opcional, no multi-tenant. WeasyPrint no en imagen Docker por defecto. Sin lockfile pip.

## Constraints

- **Tech stack**: Python 3.11+, FastAPI, parser actual; extender sin reescritura total
- **macOS app**: Swift 5.9+, macOS 14+ (Sonoma), Xcode 15+; python-build-standalone para embed Python
- **Seguridad**: Nunca commitear `.env`; API keys en Keychain en la app macOS
- **Compatibilidad**: OpenAI y DeepL; variables de entorno existentes (o Keychain en app)
- **Formato**: Salida Markdown válida; código y URLs intactos
- **Privacidad**: Traducciones y `output/` pueden ser privados — gitignore y avisos UI
- **Distribución**: DMG ad-hoc, sin cuenta Apple Developer en v3.0

## Key Decisions

| Decision | Rationale | Outcome |
| -------- | --------- | ------- |
| v2.0 scope = debt + PDF only | Enfoque acotado post-v1.0 | ✓ Shipped 2026-05-29 |
| WeasyPrint opcional | Deps nativas Cairo/Pango | ✓ `[pdf]` extra, mock tests |
| PDF vía html_export | Reutilizar CSS HTML existente | ✓ Paridad visual CLI |
| SSE auth query token | EventSource sin headers custom | ✓ DEBT-02 |
| v2.1 diferido | El lockfile es pequeño; el salto a macOS app es más valioso ahora | → Incorporar en v3.0 build |
| SwiftUI nativa vs WebView | Máxima integración macOS, mejor UX a largo plazo | v3.0 target |
| python-build-standalone para embed | Portable, sin dependencia de Python del sistema | v3.0 Phase 9 |
| DMG ad-hoc sin Apple Developer | Evitar $99/año; usuario puede bypassar Gatekeeper | v3.0 Phase 12 |

## Evolution

**Shipped v1.0 (2026-05-29):** NOTEBOOK A→E — tag `v1.0`  
**Shipped v2.0 (2026-05-29):** Tech debt + PDF — tag `v2.0`  
**v2.1 diferido (2026-06-02):** Lockfile uv incorporado en v3.0 build system  
**v3.0 started (2026-06-02):** macOS Native App (SwiftUI + Python embedded)

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

## Current State (v2.0 shipped, v3.0 planning)

- **148 tests** (`pytest tests/ -q`)
- **Stack:** Python 3.11+, FastAPI, SQLite TM, vanilla JS UI, Docker
- **Proveedores:** OpenAI (default), DeepL + fallback opcional
- **Modos:** editor (multi-idioma tabs), archivo, lote SSE, CLI, watch, revisión, export HTML/PDF
- **Despliegue:** `API_TOKEN` + UI Bearer; CORS, límites upload, TTL output/
- **v3.0 en planificación:** App macOS nativa SwiftUI + Python embedded

---
*Last updated: 2026-06-02 — v3.0 milestone started (macOS Native App)*
