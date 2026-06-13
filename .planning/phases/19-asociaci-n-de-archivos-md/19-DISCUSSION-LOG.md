# Phase 19: Asociación de archivos .md - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-13
**Phase:** 19-Asociación de archivos .md
**Areas discussed:** Race condition en startup, public.plain-text secundario, Documentación usuario

---

## Race condition en startup

| Opción | Descripción | Seleccionada |
|--------|-------------|:---:|
| Cola de URLs pendientes en AppDelegate | AppDelegate guarda URLs en `pendingURLs`; MDTranslatorApp las consume tras el health check. Garantiza que el archivo nunca se pierde. | ✓ |
| Cargar inmediatamente sin esperar al servidor | Carga el texto en el editor antes de que el servidor esté listo. El servidor no hace falta para mostrar texto — solo para traducir. | |
| Ignorar (reabrir manualmente) | La app ignora la URL si llega durante el arranque. Simple pero el usuario pierde el contexto. | |

**Elección del usuario:** Cola en AppDelegate (`var pendingURLs: [URL]`)

**Pregunta de seguimiento — ubicación de la cola:**

| Opción | Descripción | Seleccionada |
|--------|-------------|:---:|
| En AppDelegate (ya existe, es el que recibe las URLs) | `var pendingURLs: [URL]` en AppDelegate. MDTranslatorApp la consulta en el `.onReceive` del health check. Simple y sin nuevo fichero. | ✓ |
| En un singleton compartido (AppState.shared) | Un observable compartido entre AppDelegate y la vista. Más desacoplado pero añade un fichero nuevo. | |

**Elección del usuario:** En AppDelegate

---

## public.plain-text secundario

| Opción | Descripción | Seleccionada |
|--------|-------------|:---:|
| Sí, añadir (paridad ASSOC-01) | Cualquier `.txt` y archivo de texto plano aparecerá en "Abrir con MDTranslator". Cumple ASSOC-01 al pie de la letra. | ✓ |
| Solo net.daringfireball.markdown | La app solo aparece en "Abrir con" para `.md` y `.markdown`. Más limpio — evita confusión con `.txt` no-Markdown. | |

**Elección del usuario:** Sí, añadir `public.plain-text`

**Pregunta de seguimiento — filtro en `application(_:open:)`:**

| Opción | Descripción | Seleccionada |
|--------|-------------|:---:|
| Aceptar cualquier extensión (.md, .markdown, .txt) | Ya que declaramos `public.plain-text`, cargamos en editor todo lo que llegue. Consistente con la declaración en Info.plist. | ✓ |
| Seguir filtrando solo .md y .markdown | El filtro existente rechaza `.txt` en silencio. Simple pero incoherente con LSItemContentTypes. | |

**Elección del usuario:** Aceptar `.md`, `.markdown`, `.txt`

---

## Documentación usuario

| Opción | Descripción | Seleccionada |
|--------|-------------|:---:|
| README.md principal — nueva sección "Asociación de archivos" | El README ya describe la app. Una sección nueva junto a la instalación es el lugar más visible. | ✓ |
| docs/BUILDING.md o INSTALL.txt existentes | Ya documentan el proceso de instalación del DMG. Se puede añadir un apartado de configuración opcional. | |
| docs/USAGE.md (nuevo archivo) | Separar la documentación de uso de la de instalación. Más orden pero un fichero nuevo. | |

**Elección del usuario:** README.md principal

**Pregunta de seguimiento — capturas:**

| Opción | Descripción | Seleccionada |
|--------|-------------|:---:|
| Solo texto (más fácil de mantener) | Pasos numerados en Markdown. Sin capturas que queden desactualizadas. | |
| Texto + captura clave del menú contextual | Una imagen del menú "Abrir con → Cambiar todo…" para orientar al usuario. | ✓ |

**Elección del usuario:** Texto + captura del menú contextual

---

## Claude's Discretion

- `CFBundleTypeRole`: mantener "Viewer" — la app nunca modifica el archivo original.
- Implementación exacta del observer de `pendingURLs` en MDTranslatorApp (`@Published`, `didSet`, `.onChange`, etc.).
- Nombre y ubicación de la captura de pantalla en `docs/`.
- Manejo de errores para archivos no-UTF8: mantener el mismo `NSAlert` ya existente en `loadInEditor`.
- Si llegan `.txt` que no son Markdown válido: cargar igualmente como texto plano.

## Deferred Ideas

- **Drag & drop sobre la ventana principal** (no Dock) — descartado en Phase 18 (D-11), sigue fuera.
- **CFBundleTypeRole: Editor + iCloud in-place editing** — requiere cambios de arquitectura; diferido indefinidamente.
- **Soporte de archivos .mdx o .rst** — no en requisitos; idea futura.
