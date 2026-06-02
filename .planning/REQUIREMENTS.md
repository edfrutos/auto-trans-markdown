# Requirements: MarkDown Auto Translator v3.0 — macOS Native App

## Overview

Milestone v3.0 añade una aplicación macOS nativa SwiftUI que embebe el servidor Python/FastAPI existente como subprocess autocontenido. La app macOS no modifica el backend Python — consume la misma API REST que la web UI.

**Stack:** Swift 6.3.2 / Xcode 26.5 / macOS 14+ (Sonoma) · python-build-standalone CPython 3.11.15 · Sparkle 2.9.2 · create-dmg 1.2.3

---

## v3.0 Requirements

### BUNDLE — Python Embedding & Subprocess Management

- [ ] **BUNDLE-01**: El bundle `.app` incluye CPython 3.11.15 (python-build-standalone `install_only_stripped`, release 20260510) y todas las dependencias del proyecto instaladas en build time
- [ ] **BUNDLE-02**: El script `scripts/build-python-bundle.sh` verifica tras la instalación que `import fastapi` funciona desde la ruta del bundle (smoke test)
- [ ] **BUNDLE-03**: El servidor uvicorn arranca en un puerto libre asignado dinámicamente por el kernel (`bind(port:0)`), pasado al subprocess como `--port`
- [ ] **BUNDLE-04**: La app hace health check (`GET /api/languages`) con retry cada 500 ms y timeout de 15 s antes de mostrar la UI principal
- [ ] **BUNDLE-05**: Al cerrar la app (ventana + Cmd+Q + Force Quit), el proceso Python recibe SIGTERM; si no termina en 5 s, recibe SIGKILL

### CORE — App Shell & Navegación

- [ ] **CORE-01**: `NavigationSplitView` con sidebar (Editor / Archivo / Lote / Glosario / Memoria TM) y panel de contenido principal
- [ ] **CORE-02**: Selector de idioma destino persistente entre sesiones (UserDefaults)
- [ ] **CORE-03**: Settings scene (Cmd+,) con selector de proveedor (OpenAI/DeepL) y campos de configuración de modelos/URLs
- [ ] **CORE-04**: Soporte automático de tema claro/oscuro vía SwiftUI (sin configuración adicional)

### AUTH — Keychain API Keys

- [ ] **AUTH-01**: Las API keys (OPENAI_API_KEY, DEEPL_API_KEY) se guardan en el Keychain de macOS mediante Security.framework (`kSecClassGenericPassword`)
- [ ] **AUTH-02**: Las API keys se inyectan como variables de entorno (`Process.environment`) al subprocess Python antes de lanzarlo; nunca se pasan como argumentos CLI
- [ ] **AUTH-03**: La UI de Settings tiene campos `SecureField` para introducir, actualizar y eliminar cada API key del Keychain

### EDITOR — Modo Texto Directo

- [ ] **EDITOR-01**: `TextEditor` nativo para escribir/pegar Markdown con botón "Traducir" que llama a `POST /api/translate`
- [ ] **EDITOR-02**: El Markdown traducido se muestra en un segundo panel con botón para copiar al portapapeles

### FILE — Modo Archivo Único

- [ ] **FILE-01**: Botón "Abrir archivo" usa `fileImporter` nativo para seleccionar un `.md`
- [ ] **FILE-02**: Drag & drop de archivos `.md` desde el Finder sobre la ventana usando `onDrop(of: [.fileURL])`
- [ ] **FILE-03**: El archivo `.md` traducido se guarda vía `fileExporter` o panel de guardado nativo (no en carpeta temporal oculta)

### BATCH — Modo Lote

- [ ] **BATCH-01**: Selección de múltiples `.md` o carpeta completa mediante `fileImporter` con `allowsMultipleSelection: true`
- [ ] **BATCH-02**: `ProgressView` indeterminado visible durante la traducción batch (SSE diferido a v3.1)
- [ ] **BATCH-03**: Resumen al completar: número de archivos traducidos, lista de errores si los hay

### NOTIF — Notificaciones Nativas

- [ ] **NOTIF-01**: Notificación vía `UNUserNotificationCenter` al completar una traducción batch, con título y conteo de archivos

### GLOS — Glosario & Memoria de Traducción

- [ ] **GLOS-01**: Vista de lista para los términos del glosario YAML existente con opción de añadir/editar/eliminar términos
- [ ] **TM-01**: Vista de búsqueda y listado de entradas de la Memoria de Traducción SQLite existente

### MENU — Menubar Integration

- [ ] **MENU-01**: `MenuBarExtra` visible en la barra de menús aunque la ventana principal esté cerrada
- [ ] **MENU-02**: Desde el menú de la barra se puede abrir la ventana principal y acceder a traducción rápida de texto

### UPDATE — Auto-Update

- [ ] **UPDATE-01**: Sparkle 2.9.2 integrado vía SPM con firma EdDSA independiente de Apple Developer account

### DIST — Distribución DMG

- [ ] **DIST-01**: `make dmg` firma todos los `.dylib`/`.so` de Python bottom-up con `codesign --force --sign -` antes de firmar el bundle completo
- [ ] **DIST-02**: El DMG incluye `INSTALL.txt` visible con instrucciones para bypassear Gatekeeper (clic derecho → Abrir) en macOS 14+/15+
- [ ] **DIST-03**: El appcast XML de Sparkle se genera automáticamente como parte de `make dmg`

---

## Future Requirements (deferred to v3.1+)

- SSE streaming real para progreso de batch — en v3.0 se usa ProgressView indeterminado
- Universal Binary (arm64 + x86_64) — v3.0 es Apple Silicon only
- Notarización con Apple Developer account — v3.0 es ad-hoc
- iCloud sync para glosario y TM
- File association: apertura de `.md` con doble-click en Finder
- Mac App Store (requiere sandboxing y entitlements adicionales)
- Modo offline con `NWPathMonitor` para detección de conectividad
- Export PDF desde la app macOS

---

## Out of Scope (v3.0)

| Item | Reason |
|------|--------|
| Modificación del backend Python | La API REST existente es suficiente; zero cambios en `src/` |
| Web UI changes | La UI web sigue funcionando de forma independiente |
| CLI changes | `md-translate` CLI no se ve afectada |
| WeasyPrint/PDF en app macOS | Deps nativas Cairo/Pango complican el bundle; diferido a v3.1 |
| SSE streaming en batch | URLSession SSE añade complejidad; v3.0 usa ProgressView indeterminado |
| Apple Developer account | Sin notarización en v3.0; firma ad-hoc para uso personal/interno |
| Universal Binary | Apple Silicon only en v3.0; Intel si hay demanda en v3.1 |
| Lockfile v2.1 (LOCK-01) | Incorporado en el build system de v3.0 (uv install en build script) |

---

## Traceability

| REQ-ID | Phase | Plan |
|--------|-------|------|
| BUNDLE-01..05 | Phase 9 | TBD |
| CORE-01..04 | Phase 10 | TBD |
| AUTH-01..03 | Phase 10 | TBD |
| EDITOR-01..02 | Phase 11 | TBD |
| FILE-01..03 | Phase 11 | TBD |
| BATCH-01..03 | Phase 11 | TBD |
| NOTIF-01 | Phase 11 | TBD |
| GLOS-01, TM-01 | Phase 11 | TBD |
| MENU-01..02 | Phase 11 | TBD |
| UPDATE-01 | Phase 12 | TBD |
| DIST-01..03 | Phase 12 | TBD |

---

*Last updated: 2026-06-02 — v3.0 requirements defined*
