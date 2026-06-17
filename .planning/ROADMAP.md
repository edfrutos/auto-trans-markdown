# Roadmap: MarkDown Auto Translator

## Milestones

- ✅ **v1.0 NOTEBOOK A→E** — Phases 0–5 (shipped 2026-05-29) → [archive](milestones/v1.0-ROADMAP.md)
- ✅ **v2.0 Production Polish & PDF** — Phases 6–7 (shipped 2026-05-29) → [archive](milestones/v2.0-ROADMAP.md)
- ⏸ **v2.1 Reproducible Dependencies** — Phase 8 (deferred → incorporated in v3.0 build system)
- ✅ **v3.0 macOS Native App** — Phases 9–12 (shipped 2026-06-09) → [requirements](milestones/v3.0-REQUIREMENTS.md)
- ✅ **v3.1 Native macOS Polish** — Phases 13–15 (shipped 2026-06-11) → [requirements](milestones/v3.1-REQUIREMENTS.md)
- ✅ **Phase 16 Release v3.1 Distribuible** — shipped 2026-06-12 (GitHub Release + Sparkle verificado)
- 🔄 **v3.2 Native Workflow & Sync** — Phases 18–21 (definido 2026-06-12; pendiente research/planificación)

## Phases (v1.0 — shipped)

<details>
<summary>✅ v1.0 NOTEBOOK A→E (Phases 0–5) — SHIPPED 2026-05-29</summary>

| Phase   | Name                     | Plans   | Completed   |
| ------- | ------------------------ | ------- | ----------- |
| 0       | MVP Hardening            | 4/4     | 2026-05-28  |
| 1       | Production Table Stakes  | 5/5     | 2026-05-28  |
| 2       | Trust & QA               | 5/5     | 2026-05-29  |
| 3       | Batch UX & Cost Control  | 4/4     | 2026-05-29  |
| 4       | Team Scale               | 5/5     | 2026-05-29  |
| 5       | Editorial & Pro Workflow | 6/6     | 2026-05-29  |

Detalle: [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)

</details>

## Phases (v2.0 — shipped)

<details>
<summary>✅ v2.0 Production Polish & PDF (Phases 6–7) — SHIPPED 2026-05-29</summary>

| Phase   | Name                 | Plans   | Completed   |
| ------- | -------------------- | ------- | ----------- |
| 6       | v1 Tech Debt Closure | 4/4     | 2026-05-29  |
| 7       | PDF Export           | 3/3     | 2026-05-29  |

Detalle: [milestones/v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md)

</details>

## Phases (v2.1 — deferred)

<details>
<summary>⏸ v2.1 Reproducible Dependencies (Phase 8) — DEFERRED to v3.0 build system</summary>

Phase 8 se incorpora en el build system de v3.0: el script `scripts/build-python-bundle.sh` usa `uv` para instalar dependencias desde lockfile en el bundle. Los requisitos LOCK-01..05 quedan absorbidos por BUNDLE-01/BUNDLE-02 de la fase 9.

Detalle histórico: [.planning/phases/08-PHASE.md](.planning/phases/08-PHASE.md) (si existe)

</details>

## Phases (v3.0 — active)

- [x] **Phase 9: Python Embedding Foundation** - El servidor FastAPI Python arranca dentro del .app bundle y responde al health check
- [x] **Phase 10: Swift App Shell & Auth** - La app Swift tiene navegación completa, gestión segura de API keys y ciclo de vida del servidor
- [x] **Phase 11: Translation Features & Native UI** - La app tiene paridad funcional con la web UI más las integraciones nativas macOS
- [x] **Phase 12: Distribution & Auto-Update** - `make dmg` produce un DMG listo para distribuir con firma ad-hoc, Sparkle y documentación

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

| Phase                                | Plans Complete   | Status                         | Completed   |
| ------------------------------------ | ---------------- | ------------------------------ | ----------- |
| 0. MVP Hardening                     | 4/4              | Shipped                        | 2026-05-28  |
| 1. Production Table Stakes           | 5/5              | Shipped                        | 2026-05-28  |
| 2. Trust & QA                        | 5/5              | Shipped                        | 2026-05-29  |
| 3. Batch UX & Cost Control           | 4/4              | Shipped                        | 2026-05-29  |
| 4. Team Scale                        | 5/5              | Shipped                        | 2026-05-29  |
| 5. Editorial & Pro Workflow          | 6/6              | Shipped                        | 2026-05-29  |
| 6. v1 Tech Debt Closure              | 4/4              | Shipped                        | 2026-05-29  |
| 7. PDF Export                        | 3/3              | Shipped                        | 2026-05-29  |
| 8. Reproducible Dependencies         | —                | Deferred (absorbed in Phase 9) | -           |
| 9. Python Embedding Foundation       | ✅                | Shipped                        | 2026-06-07  |
| 10. Swift App Shell & Auth           | ✅                | Shipped                        | 2026-06-07  |
| 11. Translation Features & Native UI | ✅                | Shipped                        | 2026-06-07  |
| 12. Distribution & Auto-Update       | ✅                | Shipped                        | 2026-06-09  |

---
*Last updated: 2026-06-09 — v3.0 shipped (phases 9–12 complete, DMG + Sparkle)

---

## Milestones (v3.1)

- ✅ **v3.1 Native macOS Polish** — Phases 13–15 (shipped 2026-06-11); Phase 16 separada y en espera de Apple Developer account

## Phases (v3.1 — shipped; Phase 16 en espera)

### Phase 13: Native macOS Integration

**Goal**: La app se comporta como una app macOS de primera clase — acepta archivos desde el Finder, Dock y Services, y tiene historial de archivos recientes.
**Depends on**: Phase 12
**No requiere Apple Developer account.**
**Requirements**:

- `DOCK-01` — Arrastrar uno o varios `.md` al icono del Dock abre la ventana y los carga en el editor o lanza traducción en lote según el número de archivos
- `DOCK-02` — `NSApplication.dockTile` muestra una barra de progreso durante traducciones largas (NSProgressIndicator en el Dock tile)
- `RECENT-01` — Menú `File > Open Recent` estándar de macOS (NSDocumentController o manual con UserDefaults) con los últimos 10 archivos traducidos/abiertos
- `DROP-01` — Arrastrar archivos `.md` directamente sobre la ventana principal (WKWebView) los inyecta en el editor
- `SERVICES-01` — Entrada en el menú Services del sistema: "Traducir con MDTranslator" — recibe texto seleccionado de cualquier app, lo traduce al idioma configurado y devuelve el resultado al portapapeles

**Success Criteria**:

1. Arrastrar `readme.md` al Dock icon carga el contenido en el editor y activa el tab Editor
2. Durante una traducción de lote > 5 archivos, el Dock icon muestra progreso visual
3. `File > Open Recent` lista los últimos ficheros abiertos y los reabre al seleccionarlos
4. El menú Services del sistema tiene "Traducir con MDTranslator" activo cuando hay texto seleccionado en cualquier app

---

### Phase 14: Keyboard & Workflow

**Goal**: Usuarios avanzados pueden operar la app casi sin ratón y lanzar traducciones desde cualquier contexto.
**Depends on**: Phase 13
**No requiere Apple Developer account.**
**Requirements**:

- `HOTKEY-01` — Atajo global configurable (por defecto `⌥⇧T`) que activa MDTranslator desde cualquier app y enfoca el editor, usando `CGEventTap` o `MASShortcut`-style
- `HOTKEY-02` — `⌘↩` (Cmd+Return) en el editor lanza la traducción sin necesidad de clic en el botón
- `HOTKEY-03` — `⌘⇧C` copia el texto traducido del panel de resultado al portapapeles
- `ESTIMATE-01` — Indicador en tiempo real de tokens estimados y coste aproximado conforme el usuario escribe/pega en el editor (usando `src/estimate.py` via la API `/api/translate/estimate`)
- `UNDO-01` — `⌘Z` / `⌘⇧Z` funciona dentro del textarea del editor (actualmente WKWebView lo pierde)

**Success Criteria**:

1. Pulsando el atajo global desde Safari/VSCode/cualquier app, MDTranslator pasa a primer plano y el cursor está en el textarea
2. `⌘↩` en el editor lanza la traducción igual que el botón "Traducir"
3. El indicador de coste se actualiza < 300 ms tras cada keystroke (debounced 500 ms)

---

### Phase 15: Performance & Quality

**Goal**: La app arranca en < 5 s en Mac Studio M2 y el bundle pesa < 120 MB, sin regresiones de funcionalidad.
**Depends on**: Phase 13
**No requiere Apple Developer account. Instruments es gratuito.**
**Requirements**:

- `PERF-01` — Profiling con Instruments (Time Profiler + Allocations) sobre la app ad-hoc firmada; documentar tiempo de arranque y RSS en reposo en `docs/performance.md`
- `PERF-02` — Reducir tamaño del python-bundle eliminando tests, `__pycache__`, `.dist-info` innecesarios y binarios de plataformas no-arm64 del bundle de CPython standalone; objetivo < 120 MB (actualmente ~200 MB)
- `PERF-03` — Arranque en frío < 5 s medido desde doble clic hasta que el health check pasa (actualmente ~8-10 s según la máquina)
- `CRASH-01` — Integrar el Crash Reporter de Sparkle (`SentCrashReport` delegate) para recibir reports anónimos de crash opcionalmente
- `TEST-01` — Script `make smoke-test` que lanza la app, espera el health check y ejecuta `curl /api/translate` con un texto de prueba; devuelve exit 0 si la traducción es correcta

**Success Criteria**:

1. `docs/performance.md` existe con métricas base de v3.0 y objetivos v3.1
2. `python-bundle/` < 120 MB tras `scripts/build-python-bundle.sh`
3. Arranque en frío < 5 s en Mac Studio M2 (medido 3 veces, mediana)
4. `make smoke-test` pasa en CI (GitHub Actions con runner macOS)

---

### Phase 16: Release v3.1 Distribuible *(redefinida 2026-06-12 — sin Apple Developer account)*

**Goal**: Publicar MD Translator 3.1 como DMG distribuible (firma ad-hoc) con release notes, checksum, appcast Sparkle y tags git. Mac App Store y notarización quedan fuera por decisión del usuario.
**Depends on**: Phase 15
**Requirements**:

- `REL-01` — Makefile con `VERSION=3.1` / `BUILD_NUM=2`; `make dmg` produce `MDTranslator-3.1.dmg` + `.sha256` ✅ (preparado 2026-06-12)
- `REL-02` — `docs/RELEASE-NOTES-3.1.md` con novedades, requisitos, instalación (bypass Gatekeeper) y verificación de integridad ✅ (preparado 2026-06-12)
- `REL-03` — Item v3.1 en `docs/appcast.xml` (sparkle:version=2) con edSignature/length reales tras `make appcast` — bloque preparado comentado, pendiente de build en el Mac
- `REL-04` — Tags git `v3.0` y `v3.1` creados; GitHub Release v3.1 con DMG, ZIP, SHA-256 y release notes
- `REL-05` — (opcional) Registrar medición PERF-03 de arranque en frío en `docs/performance.md` durante la verificación del DMG

**Success Criteria**:

1. `make dmg && make appcast` completan sin errores en el Mac y el DMG instala y arranca tras clic derecho → Abrir
2. GitHub Release v3.1 publicada con DMG + ZIP + SHA-256 + release notes
3. Una instalación de la 3.0 recibe el aviso de actualización a 3.1 vía Sparkle

**Ejecución**: los pasos que requieren Xcode/macOS se ejecutan en el Mac del usuario (ver checklist en BUILDING.md §4–5 y comentario del appcast).

---

### Phase 17 (futura): Notarización & Mac App Store *(descartada/diferida indefinidamente)*

Antiguos requisitos de Phase 16, fuera de alcance por decisión del usuario (2026-06-12): `NOTARIZE-01`, `SANDBOX-01`, `MAS-01`, `HARDENED-01`. Retomar solo si se contrata Apple Developer Program y se desea distribución más allá del DMG ad-hoc.

---

## Progress Table (v3.1)

| Phase   | Nombre                                    | Estado                | Completada   |
| ------- | ----------------------------------------- | --------------------- | ------------ |
| 13      | Native macOS Integration                  | ✅ Shipped             | 2026-06-10   |
| 14      | Keyboard & Workflow                       | ✅ Shipped             | 2026-06-11   |
| 15      | Performance & Quality                     | ✅ Shipped             | 2026-06-11   |
| 16      | Release v3.1 Distribuible (sin Apple Dev) | ✅ Shipped             | 2026-06-12   |
| 17      | Notarización & MAS (futura)               | ⏸ Descartada/diferida | —            |

---

## Milestones (v3.2)

- 🔄 **v3.2 Native Workflow & Sync** — Phases 18–21 (definido 2026-06-12)

## Phases (v3.2 — definido, pendiente research/planificación)

### Phase 18: SSE Batch Nativo

**Goal**: El lote en la app macOS muestra progreso real archivo a archivo y permite cancelar, usando los endpoints SSE existentes del backend.
**Depends on**: Phase 16 · **Requirements**: SSE-01, SSE-02, SSE-03, SSE-04
**Plans**: 3 planes
Plans:
**Wave 1**

- [x] 18-01-PLAN.md — BatchJobManager (cliente SSE) + Commands (Notification.Name + menú Traducir lote…)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 18-02-PLAN.md — BatchSheet (vista SwiftUI 3 estados: prepared / running / done)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 18-03-PLAN.md — Integración AppDelegate + MDTranslatorApp (wiring .sheet + applicationShouldTerminate)

**Success Criteria**:

1. Un lote de 10 archivos muestra barra de progreso determinada que avanza con cada archivo, y el nombre del archivo en curso
2. "Cancelar" detiene el job y la UI lo refleja sin colgar la app
3. El icono del Dock muestra el mismo progreso (sustituye al indeterminado)

### Phase 19: Asociación de archivos .md

**Goal**: Doble clic en un `.md` (o "Abrir con") abre MDTranslator con el archivo cargado en el editor.
**Depends on**: Phase 18 · **Requirements**: ASSOC-01, ASSOC-02, ASSOC-03
**Success Criteria**:

1. "Abrir con → MDTranslator" en Finder carga el archivo en el editor y activa la ventana
2. La app no se apropia de `.md` por defecto

### Phase 20: Export PDF Nativo

**Goal**: Botón Export PDF en la app sin añadir WeasyPrint ni dependencias nativas al bundle (vía WKWebView).
**Depends on**: Phase 18 · **Requirements**: PDFN-01, PDFN-02, PDFN-03
**Success Criteria**:

1. Traducir un documento y pulsar "Export PDF" produce un PDF A4 legible con los estilos del export HTML
2. El bundle no crece más de ~1 MB

### Phase 21: Glosario y TM en iCloud Drive

**Goal**: El glosario y la memoria de traducción se comparten entre Macs vía iCloud Drive, sin Apple Developer account.
**Depends on**: Phase 18 · **Requirements**: SYNC-01, SYNC-02, SYNC-03, SYNC-04
**Success Criteria**:

1. Activar la opción mueve los datos a iCloud Drive y la traducción sigue funcionando con el glosario/TM sincronizados
2. Desactivarla devuelve los datos a `data/` local sin pérdida
3. Un segundo Mac con la opción activa ve los mismos términos del glosario

## Progress Table (v3.2)

| Phase   | Nombre            | Estado         | Completada   |
| ------- | ----------------- | -------------- | ------------ |
| 18      | SSE Batch Nativo  | ✅ Shipped      | 2026-06-13   |
| 19      | Asociación .md    | ✅ Shipped      | 2026-06-17   |
| 20      | Export PDF Nativo | ✅ Shipped      | 2026-06-17   |
| 21      | iCloud Drive Sync | ✅ Shipped      | 2026-06-17   |

---
*Last updated: 2026-06-17 — Phase 21 completada (SYNC-01..04). SyncManager, toggle iCloud Drive en Settings, rutas GLOSSARY_PATH/TM_DB_PATH inyectadas en backend. Siguiente milestone: v3.3.*

---

## Milestones (v3.3)

- 🔄 **v3.3 Polish & Release** — Phases 22–26 (definido 2026-06-17)

## Phases (v3.3 — definido)

### Phase 22: Sparkle Auto-Update Mejorado

**Goal**: La app detecta y aplica actualizaciones automáticamente desde un appcast publicado con EdDSA, sin intervención manual del usuario más allá de aceptar la actualización.
**Depends on**: Phase 21
**Requirements**:

- `SPARK-01` — Appcast `docs/appcast.xml` accesible desde una URL pública (GitHub Pages o GitHub Releases); `make appcast` genera el XML con la firma EdDSA real tras cada build
- `SPARK-02` — `UpdateManager` comprueba actualizaciones al arrancar y cada 24 h; el usuario puede forzar la comprobación desde el menú "MD Translator → Buscar actualizaciones…"
- `SPARK-03` — El delta entre versiones se descarga en background sin bloquear el hilo principal; la UI muestra un badge en el menú de barra cuando hay actualización disponible
- `SPARK-04` — Tras actualizar vía Sparkle, la app relee las API keys del Keychain y reactiva el hotkey global automáticamente (hoy requiere intervención manual documentada en release notes)

**Success Criteria**:

1. Una instalación de la 3.1 recibe aviso de actualización a 3.2+ y puede instalarla con un clic
2. Después de la actualización, el hotkey global `⌥⇧M` sigue funcionando sin tocar Privacidad → Accesibilidad
3. `make appcast` no falla en CI y el XML resultante pasa la validación de Sparkle

---

### Phase 23: Notarización Apple *(condicionada a Apple Developer account)*

**Goal**: Eliminar el paso "clic derecho → Abrir" en primera ejecución mediante notarización y stapling con Apple.
**Depends on**: Phase 22
**Requiere**: Apple Developer Program ($99/año). **Aplazada indefinidamente** hasta que el usuario lo contrate.
**Requirements**:

- `NOTARIZE-01` — Hardened Runtime activado; `codesign --deep --options runtime`
- `NOTARIZE-02` — `xcrun notarytool submit` en el Makefile; `xcrun stapler staple` tras aprobación
- `NOTARIZE-03` — Gatekeeper pasa sin "clic derecho" en macOS 14 y 15

**Success Criteria**:

1. El DMG abre directamente al hacer doble clic en un Mac limpio sin mensaje de Gatekeeper
2. `spctl --assess --verbose dist/MDTranslator.app` devuelve `accepted`

> ⏸ **Estado: diferida** — ver Phase 17 para contexto histórico.

---

### Phase 24: Preferencias Adicionales

**Goal**: El usuario puede configurar el modelo OpenAI y el tono de traducción por defecto directamente desde la app, sin editar `.env`.
**Depends on**: Phase 22
**Requirements**:

- `PREF-01` — Selector de modelo en Configuración: `gpt-4o-mini` (por defecto), `gpt-4o`, `gpt-4.1`, `o4-mini`; se guarda en UserDefaults y se inyecta como `OPENAI_MODEL` en `ServerManager`
- `PREF-02` — Selector de tono por defecto: Neutro / Formal / Informal; se guarda en UserDefaults y se pasa como `tone` en cada request de traducción desde la app
- `PREF-03` — Campo de URL base alternativa (`OPENAI_BASE_URL`) en Configuración para usuarios con Ollama, Azure o proxies compatibles con OpenAI; se guarda en Keychain (puede contener credenciales)
- `PREF-04` — Los valores de modelo y tono se muestran en el tooltip del botón "Traducir" para que el usuario sepa con qué configuración va a traducir

**Success Criteria**:

1. Cambiar el modelo a `gpt-4o` y traducir un texto usa ese modelo (verificable en el log del servidor)
2. El selector de tono se respeta en la traducción (el prompt enviado al LLM incluye la instrucción de tono correcta)
3. Una URL base alternativa permite usar Ollama local sin modificar ningún archivo de configuración

---

### Phase 25: Release v3.2

**Goal**: Publicar MD Translator 3.2 como DMG distribuible con las mejoras de Phases 18–21 (SSE batch, PDF, iCloud sync), bump de versión, release notes y appcast actualizado.
**Depends on**: Phase 24 *(puede adelantarse a Phase 24 si se prioriza el release)*
**Requirements**:

- `REL22-01` — `VERSION=3.2` / `BUILD_NUM=3` en el Makefile; `make dmg` produce `MDTranslator-3.2.dmg` + `.sha256`
- `REL22-02` — `docs/RELEASE-NOTES-3.2.md` con novedades (batch SSE, PDF A4, iCloud sync), instrucciones y problemas conocidos
- `REL22-03` — Item v3.2 en `docs/appcast.xml` con edSignature/length reales
- `REL22-04` — Tags git `v3.2`; GitHub Release con DMG, ZIP, SHA-256 y release notes

**Success Criteria**:

1. `make dmg && make appcast` completan sin errores y el DMG instala y arranca
2. GitHub Release v3.2 publicada con todos los artefactos
3. Una instalación de la 3.1 recibe aviso de actualización a 3.2 vía Sparkle

---

### Phase 26: Selector de Tono Formal/Informal en la UI Web

**Goal**: La interfaz web expone el selector de tono formal/informal que ya soporta el backend, para coherencia entre web y app nativa.
**Depends on**: Phase 25
**Requirements**:

- `TONE-01` — Dropdown "Tono: Automático / Formal / Informal" en el tab Editor y en el tab Archivo de la UI web (`static/index.html` + `static/js/`)
- `TONE-02` — El valor seleccionado se envía como campo `tone` en el body JSON de `/api/translate` y `/api/translate/file`; el backend ya lo acepta en `TranslateOptions`
- `TONE-03` — La selección de tono se recuerda entre sesiones con `localStorage`
- `TONE-04` — En DeepL, el tono se mapea a `formality=more` (formal) / `formality=less` (informal) / `formality=default` (automático)

**Success Criteria**:

1. Seleccionar "Formal" y traducir al español produce `usted` en lugar de `tú` (verificable con un texto de prueba)
2. El valor persiste al recargar la página
3. DeepL respeta la configuración de formalidad cuando el idioma destino lo soporta (es, de, fr, it, pt…)

---

## Progress Table (v3.3)

| Phase   | Nombre                              | Estado    | Completada   |
| ------- | ----------------------------------- | --------- | ------------ |
| 22      | Sparkle Auto-Update Mejorado        | Pendiente | —            |
| 23      | Notarización Apple (condicionada)   | ⏸ Diferida | —           |
| 24      | Preferencias Adicionales            | Pendiente | —            |
| 25      | Release v3.2                        | Pendiente | —            |
| 26      | Selector Tono Formal/Informal (web) | Pendiente | —            |

---
*Last updated: 2026-06-17 — Phases 22–26 definidas. Siguiente fase activa: Phase 22 (Sparkle Auto-Update Mejorado).*
