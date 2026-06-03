# Roadmap: MarkDown Auto Translator

## Milestones

- ✅ **v1.0 NOTEBOOK A→E** — Phases 0–5 (shipped 2026-05-29) → [archive](milestones/v1.0-ROADMAP.md)
- ✅ **v2.0 Production Polish & PDF** — Phases 6–7 (shipped 2026-05-29) → [archive](milestones/v2.0-ROADMAP.md)
- ⏸ **v2.1 Reproducible Dependencies** — Phase 8 (deferred → incorporated in v3.0 build system)
- 🔄 **v3.0 macOS Native App** — Phases 9–12 (active)

## Phases (v1.0 — shipped)

<details>
<summary>✅ v1.0 NOTEBOOK A→E (Phases 0–5) — SHIPPED 2026-05-29</summary>

| Phase | Name | Plans | Completed |
|-------|------|-------|-----------|
| 0 | MVP Hardening | 4/4 | 2026-05-28 |
| 1 | Production Table Stakes | 5/5 | 2026-05-28 |
| 2 | Trust & QA | 5/5 | 2026-05-29 |
| 3 | Batch UX & Cost Control | 4/4 | 2026-05-29 |
| 4 | Team Scale | 5/5 | 2026-05-29 |
| 5 | Editorial & Pro Workflow | 6/6 | 2026-05-29 |

Detalle: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)

</details>

## Phases (v2.0 — shipped)

<details>
<summary>✅ v2.0 Production Polish & PDF (Phases 6–7) — SHIPPED 2026-05-29</summary>

| Phase | Name | Plans | Completed |
|-------|------|-------|-----------|
| 6 | v1 Tech Debt Closure | 4/4 | 2026-05-29 |
| 7 | PDF Export | 3/3 | 2026-05-29 |

Detalle: [milestones/v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md)

</details>

## Phases (v2.1 — deferred)

<details>
<summary>⏸ v2.1 Reproducible Dependencies (Phase 8) — DEFERRED to v3.0 build system</summary>

Phase 8 se incorpora en el build system de v3.0: el script `scripts/build-python-bundle.sh` usa `uv` para instalar dependencias desde lockfile en el bundle. Los requisitos LOCK-01..05 quedan absorbidos por BUNDLE-01/BUNDLE-02 de la fase 9.

Detalle histórico: [.planning/phases/08-PHASE.md](.planning/phases/08-PHASE.md) (si existe)

</details>

## Phases (v3.0 — active)

- [ ] **Phase 9: Python Embedding Foundation** - El servidor FastAPI Python arranca dentro del .app bundle y responde al health check
- [ ] **Phase 10: Swift App Shell & Auth** - La app Swift tiene navegación completa, gestión segura de API keys y ciclo de vida del servidor
- [ ] **Phase 11: Translation Features & Native UI** - La app tiene paridad funcional con la web UI más las integraciones nativas macOS
- [ ] **Phase 12: Distribution & Auto-Update** - `make dmg` produce un DMG listo para distribuir con firma ad-hoc, Sparkle y documentación

## Phase Details

### Phase 9: Python Embedding Foundation
**Goal**: El servidor FastAPI Python arranca dentro del .app bundle y responde al health check desde la app Swift
**Depends on**: Nothing (base técnica del proyecto; sin dependencias de fases anteriores)
**Requirements**: BUNDLE-01, BUNDLE-02, BUNDLE-03, BUNDLE-04, BUNDLE-05
**Success Criteria** (what must be TRUE):
  1. El usuario puede ejecutar `scripts/build-python-bundle.sh` y el script descarga CPython 3.11.15 standalone, instala las dependencias del proyecto y verifica que `import fastapi` funciona sin Python del sistema
  2. La app Swift lanza el servidor uvicorn en un puerto libre asignado por el kernel y el proceso aparece en el Activity Monitor como subprocess de la app
  3. Después de arrancar la app, `GET /api/languages` responde con la lista de idiomas en menos de 15 segundos
  4. Al cerrar la app (ventana, Cmd+Q o Force Quit), el proceso Python desaparece del Activity Monitor en un máximo de 5 segundos adicionales
  5. La splash screen o indicador de carga es visible durante el arranque del servidor y desaparece cuando el health check pasa
**Plans**: TBD

### Phase 10: Swift App Shell & Auth
**Goal**: La app Swift tiene navegación completa, gestión segura de API keys y ciclo de vida del servidor integrado
**Depends on**: Phase 9
**Requirements**: CORE-01, CORE-02, CORE-03, CORE-04, AUTH-01, AUTH-02, AUTH-03
**Success Criteria** (what must be TRUE):
  1. El usuario puede navegar entre Editor, Archivo, Lote, Glosario y Memoria TM desde la barra lateral sin que la app se reinicie ni pierda estado
  2. El usuario puede abrir Preferencias (Cmd+,), introducir su API key de OpenAI o DeepL en un campo seguro y la clave persiste entre reinicios de la app sin estar en ningún archivo en disco
  3. El selector de idioma destino recuerda la última selección al cerrar y reabrir la app
  4. La app respeta automáticamente el tema claro/oscuro del sistema sin ninguna configuración adicional por parte del usuario
  5. Las API keys se inyectan como variables de entorno al subprocess Python, sin que aparezcan en argumentos de proceso visibles con `ps aux`
**Plans**: TBD
**UI hint**: yes

### Phase 11: Translation Features & Native UI
**Goal**: La app tiene paridad funcional con la web UI más las integraciones nativas macOS para archivos y notificaciones
**Depends on**: Phase 10
**Requirements**: EDITOR-01, EDITOR-02, FILE-01, FILE-02, FILE-03, BATCH-01, BATCH-02, BATCH-03, NOTIF-01, GLOS-01, TM-01, MENU-01, MENU-02
**Success Criteria** (what must be TRUE):
  1. El usuario puede escribir o pegar Markdown en el editor, pulsar "Traducir" y ver el resultado traducido en un segundo panel con un botón para copiar al portapapeles
  2. El usuario puede abrir un archivo `.md` mediante el selector de archivos o arrastrándolo desde el Finder sobre la ventana, traducirlo y guardarlo con el panel de guardado nativo de macOS
  3. El usuario puede seleccionar múltiples archivos `.md` o una carpeta completa para traducción en lote, ver un indicador de progreso durante la operación y recibir una notificación del sistema al completar con el recuento de archivos procesados
  4. El usuario puede ver, añadir, editar y eliminar términos del glosario YAML desde la interfaz, y puede buscar entradas de la memoria de traducción SQLite
  5. El icono de la app es visible en la barra de menús aunque la ventana principal esté cerrada, y desde él se puede abrir la ventana principal o lanzar una traducción rápida de texto
**Plans**: TBD
**UI hint**: yes

### Phase 12: Distribution & Auto-Update
**Goal**: `make dmg` produce un DMG listo para distribuir con firma ad-hoc, auto-update Sparkle y documentación de instalación
**Depends on**: Phase 11
**Requirements**: UPDATE-01, DIST-01, DIST-02, DIST-03
**Success Criteria** (what must be TRUE):
  1. Ejecutar `make dmg` desde el directorio raíz completa sin errores y produce un archivo `.dmg` que contiene la app firmada y un icono de alias a `/Applications`
  2. El usuario puede instalar la app haciendo doble clic en el DMG, arrastrar la app a Aplicaciones y abrirla sin que macOS 14/15 muestre un error de Gatekeeper (usando clic derecho → Abrir según las instrucciones incluidas)
  3. El DMG incluye un archivo `INSTALL.txt` legible con instrucciones para bypassear Gatekeeper en macOS 14+ y macOS 15+
  4. La app muestra un diálogo de actualización disponible cuando existe una versión nueva en el appcast, y el appcast XML se genera automáticamente como parte de `make dmg`
**Plans**: TBD

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. MVP Hardening | 4/4 | Shipped | 2026-05-28 |
| 1. Production Table Stakes | 5/5 | Shipped | 2026-05-28 |
| 2. Trust & QA | 5/5 | Shipped | 2026-05-29 |
| 3. Batch UX & Cost Control | 4/4 | Shipped | 2026-05-29 |
| 4. Team Scale | 5/5 | Shipped | 2026-05-29 |
| 5. Editorial & Pro Workflow | 6/6 | Shipped | 2026-05-29 |
| 6. v1 Tech Debt Closure | 4/4 | Shipped | 2026-05-29 |
| 7. PDF Export | 3/3 | Shipped | 2026-05-29 |
| 8. Reproducible Dependencies | — | Deferred (absorbed in Phase 9) | - |
| 9. Python Embedding Foundation | 0/3 | Not started | - |
| 10. Swift App Shell & Auth | 0/3 | Not started | - |
| 11. Translation Features & Native UI | 0/4 | Not started | - |
| 12. Distribution & Auto-Update | 0/2 | Not started | - |

---
*Last updated: 2026-06-02 — v3.0 roadmap created (4 phases, 9–12)*
