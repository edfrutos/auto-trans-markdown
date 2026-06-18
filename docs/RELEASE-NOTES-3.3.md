# MD Translator 3.3 — Release Notes

**Fecha:** 2026-06-18
**Build:** 7
**Requisitos:** macOS 14.0 (Sonoma) o superior

---

## Novedades

### Preferencias avanzadas (Phase 24)

- **Selector de modelo OpenAI** — elige entre `gpt-4o-mini`, `gpt-4o`, `gpt-4.1` y `o4-mini` directamente desde Configuración (⌘,). El modelo activo se muestra en el tooltip del botón "Traducir".
- **Tono de traducción por defecto** — Neutro / Formal / Informal. El valor elegido en Configuración se pre-selecciona automáticamente en la interfaz web al abrirla.
- **URL base alternativa** — campo para usuarios de Ollama, Azure OpenAI o cualquier proxy compatible con la API de OpenAI. Se guarda en el Keychain. Solo visible con proveedor OpenAI.
- **Tooltip en el botón Traducir** — indica el modelo y tono activos (`Modelo: gpt-4o | Tono: Formal`) al pasar el cursor.

### Selector de tono persistente en la web (Phase 26)

- El valor del selector de tono (Automático / Formal / Informal) se guarda en `localStorage` y se restaura automáticamente al recargar la página o abrir una nueva sesión.

### Sparkle auto-update mejorado (Phase 22)

- Las comprobaciones automáticas de actualización arrancan al lanzar la app.
- Un punto naranja en el icono del menú bar indica cuando hay una actualización disponible.
- Tras una actualización, la app detecta si el permiso de Accesibilidad (atajo ⌥⇧M) fue revocado y abre Configuración para recuperarlo.

---

## Correcciones

- **SyncManager.swift** — faltaba `import Combine`; los `@Published` y `ObservableObject` fallaban al compilar. Fix incluido en build 7.
- **iCloud Drive URL** — corregido `guard let` sobre `URL` no-opcional en `iCloudDir`.

---

## Incluido desde v3.2

- Exportación PDF nativa desde WKWebView (Phase 20)
- Sincronización glosario y TM vía iCloud Drive (Phase 21)
- Traducción de lotes grandes con SSE y progreso en tiempo real (Phase 18)
- Asociación de archivos `.md`, `.markdown` y `.txt` con la app (Phase 19)

---

## Instalación

1. Descarga `MDTranslator-3.3.dmg` desde GitHub Releases.
2. Abre el DMG y arrastra MDTranslator a la carpeta Applications.
3. En el primer arranque, introduce tu API key de OpenAI o DeepL en Configuración (⌘,).

**Actualización desde 3.2:** Sparkle mostrará la notificación automáticamente. Haz clic en "Actualizar" y la app se reiniciará con la nueva versión.

---

## Problemas conocidos

- **iCloud Drive y SQLite:** Si tienes sync activado en dos Macs simultáneamente, la memoria de traducción puede corromperse. Usa sync desde un solo Mac a la vez.
- **Permiso de Accesibilidad tras update:** Si el atajo ⌥⇧M deja de funcionar después de actualizar, ve a Ajustes del Sistema → Privacidad → Accesibilidad, elimina MDTranslator y vuelve a añadirlo.
- **App Sandbox desactivado:** La app no está notarizada. En el primer arranque macOS puede mostrar un aviso de seguridad; haz clic en "Abrir de todos modos" en Ajustes del Sistema → Privacidad y Seguridad.

---

## SHA-256

El hash SHA-256 del DMG se incluye en el archivo `MDTranslator-3.3.dmg.sha256` junto al instalador.
