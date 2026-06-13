# Phase 19: Asociación de archivos .md - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

La app macOS aparece en el submenú "Abrir con" del Finder para archivos `.md`, `.markdown` y `.txt`, y al abrirlos (doble clic o "Abrir con") carga el contenido en el editor reutilizando la ruta `application(_:open:)` ya existente desde Phase 13. La app **no** se auto-proclama handler por defecto; el usuario decide vía "Abrir con → Cambiar todo…".

Entregables: completar Info.plist (ASSOC-01), cola de URLs pendientes para arranque en frío (ASSOC-02), documentación en README.md (ASSOC-03).

</domain>

<decisions>
## Implementation Decisions

### Startup race condition

- **D-01:** Cola de URLs pendientes en `AppDelegate` — `var pendingURLs: [URL] = []`. Si `application(_:open:)` se llama mientras la SplashView está activa (servidor aún arrancando), las URLs se acumulan en `pendingURLs` en lugar de publicar `openMarkdownNotification` inmediatamente. MDTranslatorApp las consume y llama `loadInEditor` / `openBatchSheet` justo después de que el health check confirme `serverManager.state == .running`.

### Info.plist — tipos de contenido

- **D-02:** Añadir `public.plain-text` como segundo ítem en `LSItemContentTypes` dentro de `CFBundleDocumentTypes`. Esto hace que archivos `.txt` también aparezcan en "Abrir con MDTranslator".
- **D-03:** Ampliar el filtro en `application(_:open:)` de `pathExtension == "md"` a `.md`, `.markdown`, `.txt`. Consistente con la declaración en Info.plist; el filtro actual rechazaría `.txt` en silencio.

### Documentación usuario

- **D-04:** Nueva sección **"Asociación de archivos"** en `README.md` (el principal, no docs/). Contenido: pasos numerados en texto + una captura del menú contextual "Abrir con → Cambiar todo…". Sin capturas adicionales (se desactualizan rápido). La sección aclara que la app no reclama la asociación por defecto.

### Claude's Discretion

- `CFBundleTypeRole`: mantener `Viewer` — la app nunca modifica el archivo original, solo lee y traduce a un nuevo destino.
- Implementación exacta de cómo MDTranslatorApp observa `pendingURLs` (puede ser `@Published`, `didSet` + NotificationCenter, o lectura directa en `.onChange`).
- Nombre y ubicación de la captura de pantalla en `docs/` o junto al README.
- Manejo de errores para archivos no-UTF8 abiertos desde Finder: mantener el mismo `NSAlert` de error que `loadInEditor` ya tiene.
- Si llegan `.txt` que no son Markdown válido, cargar igualmente (el editor los acepta como texto plano).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### App macOS — archivos a modificar

- `macos/MDTranslator/MDTranslator/Info.plist` — `CFBundleDocumentTypes` existente: base para añadir `public.plain-text` (ASSOC-01); `LSHandlerRank: Alternate` ya presente
- `macos/MDTranslator/MDTranslator/AppDelegate.swift` — `application(_:open:)`, `loadInEditor(url:)`, `openBatchSheet(_:)` (ruta a reutilizar en ASSOC-02); aquí vive `pendingURLs` (D-01)
- `macos/MDTranslator/MDTranslator/MDTranslatorApp.swift` — punto de integración donde consumir `pendingURLs` tras el health check
- `macos/MDTranslator/MDTranslator/WebView.swift` — `openMarkdownNotification` (receptor de la URL en el editor)

### Requisitos

- `.planning/REQUIREMENTS.md` §ASSOC — ASSOC-01, ASSOC-02, ASSOC-03 literales

### Documentación a actualizar

- `README.md` — raíz del proyecto; aquí va la sección "Asociación de archivos" (D-04)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `AppDelegate.application(_:open:)` (líneas 134–148): ya filtra `.md`, llama `loadInEditor` para un archivo o `openBatchSheet` para varios, y añade a `NSDocumentController.shared.noteNewRecentDocumentURL`. Solo necesita la lógica de cola (D-01) y ampliar el filtro de extensión (D-03).
- `WebView.openMarkdownNotification` (`WebView.swift:31`): la notificación ya existe y la WebView ya está suscrita — no hay que crearla, solo hay que publicarla en el momento correcto.
- `AppDelegate.loadInEditor(url:)`: ya maneja errores con `NSAlert` — reutilizar sin cambios para archivos `.txt`.

### Established Patterns

- Swift 6 + macOS 14: `@Observable`, `@State`, `@MainActor`. `AppDelegate` usa el patrón `nonisolated` + `MainActor.assumeIsolated {}` — cualquier nueva propiedad en AppDelegate debe seguirlo.
- `ServerManager.state` como señal de readiness — el punto de consumo de `pendingURLs` debe observar esta señal, no crear un mecanismo nuevo.
- Mensajes de UI en español (alerts, botones) — consistente con los alerts existentes de `loadInEditor`.

### Integration Points

- `MDTranslatorApp` observa `serverManager.state` para cambiar de SplashView a ContentView — este mismo punto es donde consumir `pendingURLs` (D-01).
- `AppDelegate.openBatchSheet(_:)` ya existe (Phase 18) — si llegan múltiples URLs de Finder durante la splash, también se encolan y se abren como batch al terminar el arranque.

</code_context>

<specifics>
## Specific Ideas

- La cola `pendingURLs` en AppDelegate debe ser `@MainActor` o protegida, ya que `application(_:open:)` llega en el hilo principal pero MDTranslatorApp podría observarla desde SwiftUI.
- La captura del menú "Abrir con → Cambiar todo…" se añade en `docs/` (o junto al README) y se referencia en la sección del README con ruta relativa Markdown.

</specifics>

<deferred>
## Deferred Ideas

- **Drag & drop de archivos .md sobre la ventana principal** (no Dock) — ya descartado en Phase 18 (D-11); sigue fuera de esta fase.
- **Registro como editor in-place** (CFBundleTypeRole: Editor + iCloud) — requiere cambios de arquitectura y posiblemente entitlements; diferido indefinidamente.
- **Soporte de archivos .mdx o .rst** — no mencionado en requisitos; capturado como idea futura.

</deferred>

---

*Phase: 19-Asociación de archivos .md*
*Context gathered: 2026-06-13*
