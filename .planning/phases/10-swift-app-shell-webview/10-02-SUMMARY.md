# Plan 10-02 — SUMMARY
## Ventana nativa: menús, toolbar y UX macOS

**Estado:** COMPLETADO  
**Fecha:** 2026-06-08

---

## Archivos creados / modificados

| Archivo | Estado |
|---------|--------|
| `macos/MDTranslator/MDTranslator/Commands.swift` | NUEVO |
| `macos/MDTranslator/MDTranslator/MDTranslatorApp.swift` | MODIFICADO |

---

## Funcionalidades implementadas

### Commands.swift (`AppCommands: Commands`)
- **⌘O** — "Abrir archivo Markdown…": `NSOpenPanel` filtrado a `.md`; lee el archivo UTF-8 y publica `WebView.openMarkdownNotification` con el contenido.
- **⌘R** — "Recargar interfaz": publica `WebView.reloadNotification`; `WebView.Coordinator` llama `webView.reload()`.
- **⌘,** — "Configuración…": publica `Notification.Name.openSettings`; `MDTranslatorApp` activa el sheet de `SettingsView`.
- **About panel** — `NSApp.orderFrontStandardAboutPanel` con nombre, versión de `CFBundleShortVersionString` y créditos.
- Error de lectura de archivo → `NSAlert` con `error.localizedDescription`.

### Notification names centralizados en `Commands.swift`
```swift
Notification.Name.openSettings   // → abre SettingsView (⌘,)
Notification.Name.settingsSaved  // → señal de primera ejecución completada
```

### MDTranslatorApp
- `.commands { AppCommands(serverPort: serverManager.serverPort) }` — integra los comandos en la barra de menús macOS.
- `@State private var showSettings` + `.sheet(isPresented:)` con `SettingsView`.
- `.onReceive(NotificationCenter.default.publisher(for: .openSettings))` — activa el sheet.

---

## Criterios de aceptación

- [x] `Commands.swift` creado con `AppCommands: Commands`
- [x] ⌘O abre `NSOpenPanel` filtrado a `.md`
- [x] ⌘R recarga la WebView sin reiniciar el servidor
- [x] ⌘, abre `SettingsView` (sheet)
- [x] About panel muestra nombre y versión
- [x] Notification names `.openSettings` y `.settingsSaved` definidos y compartidos
