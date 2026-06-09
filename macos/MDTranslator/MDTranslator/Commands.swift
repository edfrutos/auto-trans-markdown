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

    /// Muestra el About panel estándar de macOS con metadatos de la app.
    private func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName:    "MD Translator",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0",
            .credits: NSAttributedString(
                string: "MarkDown Auto Translator v3.0\nFastAPI + uvicorn embebido\n\nhttps://github.com/edefrutos",
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
}
