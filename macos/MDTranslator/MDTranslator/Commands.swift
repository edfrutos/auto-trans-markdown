// Commands.swift — Comandos de menú nativos macOS para MD Translator.
// Integra acciones en la barra de menús: abrir .md (⌘O), recargar UI (⌘R),
// configuración de API keys (⌘,), About panel y comprobación de actualizaciones.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppCommands: Commands {
    let serverPort: Int

    var body: some Commands {
        // MARK: File — Abrir Markdown
        // Reemplaza "New" (no aplica en esta app) por "Abrir archivo Markdown…"
        CommandGroup(replacing: .newItem) {
            Button("Abrir archivo Markdown…") {
                openMarkdownFile()
            }
            .keyboardShortcut("o")
        }

        // MARK: Translate — Disparar traducción con ⌘↩
        CommandGroup(after: .newItem) {
            Button("Traducir") {
                NotificationCenter.default.post(name: WebView.triggerTranslateNotification, object: nil)
            }
            .keyboardShortcut(.return)
            // HOTKEY-03: copiar el panel de resultado al portapapeles con ⌘⇧C
            Button("Copiar traducción") {
                NotificationCenter.default.post(name: WebView.copyResultNotification, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            // SSE-01/D-11: traducción en lote — posta .openBatchSheet vía openBatchFiles()
            Divider()
            Button("Traducir lote…") {
                openBatchFiles()  // → NotificationCenter.post(.openBatchSheet, object: [URL])
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }

        // MARK: Undo / Redo — interceptar ⌘Z y ⌘⇧Z para redirigirlos al WKWebView (UNDO-01).
        // SwiftUI captura ⌘Z antes de que llegue al WKWebView (que lo necesita para el textarea).
        // Al reemplazar el CommandGroup de undoRedo, enviamos la acción via JS.
        CommandGroup(replacing: .undoRedo) {
            Button("Deshacer") {
                NotificationCenter.default.post(name: WebView.undoNotification, object: nil)
            }
            .keyboardShortcut("z")
            Button("Rehacer") {
                NotificationCenter.default.post(name: WebView.redoNotification, object: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        // MARK: View — Recargar interfaz + Mostrar carpeta de salida
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Recargar interfaz") {
                NotificationCenter.default.post(name: WebView.reloadNotification, object: nil)
            }
            .keyboardShortcut("r")
            Button("Mostrar carpeta de salida en Finder") {
                OutputManager.shared.revealOutputFolder()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        // MARK: App — Configuración (⌘,), actualizaciones y About
        CommandGroup(replacing: .appInfo) {
            Button("Acerca de MD Translator") {
                showAboutPanel()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Configuración…") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .keyboardShortcut(",")

            Button("Buscar actualizaciones…") {
                UpdateManager.shared.checkForUpdates()
            }
            .disabled(!UpdateManager.shared.canCheckForUpdates)
        }
    }

    // MARK: - Acciones privadas

    /// Abre un NSOpenPanel filtrado a archivos .md y publica el contenido vía notificación.
    private func openMarkdownFile() {
        let panel = NSOpenPanel()
        panel.title = "Abrir archivo Markdown"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            // Registrar en Open Recent (RECENT-01)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            NotificationCenter.default.post(
                name: WebView.openMarkdownNotification,
                object: content
            )
        } catch {
            // Si el archivo no es UTF-8 válido, mostrar alerta.
            let alert = NSAlert()
            alert.messageText = "No se pudo leer el archivo"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// Abre un NSOpenPanel con selección múltiple de archivos .md y publica la lista vía notificación.
    /// Si BatchJobManager ya tiene un job activo, abre la sheet igualmente (D-04: reabrir en curso).
    private func openBatchFiles() {
        let panel = NSOpenPanel()
        panel.title = "Seleccionar archivos Markdown para traducir en lote"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .text]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        // T-18-01: filtrar solo .md (lowercased) — silencia archivos no Markdown (pitfall Tampering)
        let urls = panel.urls.filter { $0.pathExtension.lowercased() == "md" }
        guard !urls.isEmpty else { return }
        // Registrar cada URL en Open Recent
        urls.forEach { NSDocumentController.shared.noteNewRecentDocumentURL($0) }
        // Postear siempre, incluso si hay un job en curso (D-04: la sheet muestra el estado en curso)
        NotificationCenter.default.post(name: .openBatchSheet, object: urls)
    }

    /// Muestra el About panel estándar de macOS con metadatos de la app.
    private func showAboutPanel() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.1"
        // macOS añade CFBundleVersion automáticamente en paréntesis; no lo duplicamos.
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName:    "MD Translator",
            .applicationVersion: version,
            .credits: NSAttributedString(
                string: "Traductor de Markdown con backend FastAPI + uvicorn embebido.\n\nhttps://github.com/edfrutos/auto-trans-markdown",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            )
        ])
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Publicada por Commands para abrir SettingsView (⌘,).
    static let openSettings = Notification.Name("openSettings")
    /// Publicada por SettingsView cuando el usuario guarda las keys con éxito.
    static let settingsSaved = Notification.Name("settingsSaved")
    /// Publicada por Commands (openBatchFiles) y AppDelegate para abrir BatchSheet.
    /// El objeto adjunto es [URL] con los archivos .md seleccionados.
    static let openBatchSheet = Notification.Name("openBatchSheet")
}
