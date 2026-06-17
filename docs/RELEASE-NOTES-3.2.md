# MD Translator 3.2 — Release Notes

**Fecha:** 2026-06-17
**Build:** 6
**Requisitos:** macOS 14.0 (Sonoma) o superior

---

## Novedades

### Preferencias avanzadas (Phase 24)

- **Selector de modelo OpenAI** — elige entre `gpt-4o-mini`, `gpt-4o`, `gpt-4.1` y `o4-mini` directamente desde Configuración (⌘,). El modelo se aplica de inmediato sin reiniciar.
- **Tono de traducción por defecto** — Neutro / Formal / Informal. Se pre-selecciona en el selector de tono de la interfaz web cada vez que la abres.
- **URL base alternativa** — campo para usuarios de Ollama, Azure OpenAI o cualquier proxy compatible con la API de OpenAI. Se guarda en el Keychain (soporta credenciales embebidas en la URL). Solo visible cuando el proveedor activo es OpenAI.
- **Tooltip en el botón Traducir** — al pasar el cursor sobre "Traducir" se muestra el modelo y tono activos (`Modelo: gpt-4o | Tono: Formal`).

### Sparkle auto-update mejorado (Phase 22)

- Las comprobaciones automáticas de actualización arrancan al lanzar la app, sin esperar a que abras el menú.
- Un punto naranja en el icono del menú bar indica cuando hay una actualización disponible.
- Tras una actualización de Sparkle, la app detecta si el permiso de Accesibilidad (atajo ⌥⇧M) fue revocado y abre automáticamente Configuración para recuperarlo.

### Exportación PDF nativa (Phase 20)

- El PDF se genera desde WKWebView directamente, sin depender de WeasyPrint ni del servidor Python. Produce PDF A4 de alta calidad con el mismo estilo visual de la interfaz.
- Funciona sin conexión a internet una vez que la app está arrancada.

### Sincronización iCloud Drive (Phase 21)

- Toggle en Configuración para mover el glosario (`glossary.yaml`) y la memoria de traducción (`translation_memory.db`) a iCloud Drive, compartiendo datos entre Macs.
- Migración asistida: los archivos existentes se copian al activar y se restauran al desactivar.
- Aviso de conflicto: SQLite no admite escritura simultánea desde varios Macs; la UI advierte de esto.

---

## Mejoras anteriores incluidas en esta build

- **Phase 19** — La app se registra como handler de `.md`, `.markdown` y `.txt`; arrastrar un archivo al icono del Dock lo traduce directamente.
- **Phase 18** — Traducción de lotes grandes con SSE (Server-Sent Events): progreso en tiempo real sin timeouts.
- **Phase 15** — Exportación ZIP de lotes, descarga nativa desde WKWebView, opt-in para informes de diagnóstico anónimos.

---

## Instalación

1. Descarga `MDTranslator-3.2.dmg` desde GitHub Releases.
2. Abre el DMG y arrastra MDTranslator a la carpeta Applications.
3. En el primer arranque, introduce tu API key de OpenAI o DeepL en Configuración (⌘,).

**Actualización desde 3.1:** Sparkle mostrará la notificación automáticamente. Haz clic en "Actualizar" y la app se reiniciará con la nueva versión.

---

## Problemas conocidos

- **iCloud Drive y SQLite:** Si tienes sync activado en dos Macs simultáneamente, la memoria de traducción puede corromperse. Usa sync desde un solo Mac a la vez.
- **Permiso de Accesibilidad tras update:** Si el atajo ⌥⇧M deja de funcionar después de actualizar, ve a Ajustes del Sistema → Privacidad → Accesibilidad, elimina MDTranslator de la lista y vuelve a añadirlo. La app te avisará si detecta este problema.
- **App Sandbox desactivado:** La app no está notarizada por Apple. En el primer arranque macOS mostrará un aviso de seguridad; haz clic en "Abrir de todos modos" en Ajustes del Sistema → Privacidad y Seguridad.

---

## SHA-256

El hash SHA-256 del DMG se incluye en el archivo `MDTranslator-3.2.dmg.sha256` junto al instalador.
