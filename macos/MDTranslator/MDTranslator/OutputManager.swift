// OutputManager.swift — Gestión de la carpeta de salida para archivos traducidos.
// Usa Security-Scoped Bookmarks para persistir el acceso a carpetas elegidas por el usuario
// entre reinicios. Fallback: NSSavePanel si no hay carpeta configurada.
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class OutputManager {
    static let shared = OutputManager()

    // MARK: - UserDefaults keys

    private let bookmarkKey = "outputFolderBookmark"

    // MARK: - Init

    private init() {}

    // MARK: - Guardar archivo traducido

    /// Guarda el contenido Markdown mostrando siempre NSSavePanel.
    /// Si hay carpeta configurada, se usa como directorio inicial del panel.
    /// Así el usuario siempre puede cambiar nombre o ubicación, evitando
    /// sobreescrituras silenciosas que bloquean la app.
    func saveTranslatedFile(name: String, content: String) {
        presentSavePanel(name: name, content: content, initialFolder: resolveBookmarkedFolder())
    }

    // MARK: - Guardar en lote sin panel (DOCK-01 batch)

    /// Guarda un archivo traducido silenciosamente, sin mostrar NSSavePanel.
    /// Usa la carpeta bookmarked si existe; si no, la carpeta Descargas del usuario.
    /// Devuelve `true` si el archivo se guardó con éxito.
    @discardableResult
    func saveFileSilently(name: String, content: String) -> Bool {
        let folder = resolveBookmarkedFolder() ?? downloadsFolder()
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let dest = folder.appendingPathComponent(name)
        do {
            try content.write(to: dest, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// URL de la carpeta Descargas del usuario (fallback para batch sin carpeta configurada).
    private func downloadsFolder() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Guardar archivo binario (DOWNLOAD-01)

    /// Guarda datos binarios (ZIP, MD descargado desde WKWebView, etc.) mostrando NSSavePanel.
    /// Usa la carpeta bookmarked como directorio inicial si está configurada.
    func saveDownload(name: String, data: Data) {
        let panel = NSSavePanel()
        panel.title = "Guardar archivo"
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "zip":
            panel.allowedContentTypes = [.zip]
        case "md", "markdown":
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .text]
        default:
            panel.allowedContentTypes = [.data]
        }
        if let folder = resolveBookmarkedFolder() {
            let accessed = folder.startAccessingSecurityScopedResource()
            panel.directoryURL = folder
            if accessed { folder.stopAccessingSecurityScopedResource() }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            presentWriteError(error, filename: name)
        }
    }

    // MARK: - Elegir carpeta de salida (llamado desde SettingsView)

    /// Presenta NSOpenPanel para que el usuario elija una carpeta de salida.
    /// Persiste el acceso via Security-Scoped Bookmark.
    func chooseFolderAndSave() {
        let panel = NSOpenPanel()
        panel.title = "Carpeta de salida para traducciones"
        panel.prompt = "Seleccionar"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        persistBookmark(for: url)
    }

    /// Abre Finder mostrando la carpeta de salida configurada.
    func revealOutputFolder() {
        guard let url = resolveBookmarkedFolder() else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Elimina la carpeta de salida configurada (vuelve a NSSavePanel en la siguiente guardia).
    func clearOutputFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Devuelve el nombre de la carpeta de salida actualmente configurada, si la hay.
    var outputFolderName: String? {
        resolveBookmarkedFolder()?.lastPathComponent
    }

    // MARK: - Private helpers

    /// Resuelve el bookmark guardado y devuelve la URL si el acceso sigue siendo válido.
    private func resolveBookmarkedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // El bookmark caducó — intentar renovarlo.
                persistBookmark(for: url)
            }
            return url
        } catch {
            // Bookmark inválido — borrarlo para no intentarlo de nuevo.
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return nil
        }
    }

    /// Persiste un Security-Scoped Bookmark para la URL dada.
    private func persistBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            // Si falla la creación del bookmark no bloqueamos al usuario — la próxima
            // vez se usará NSSavePanel como fallback.
        }
    }

    /// Muestra NSSavePanel con nombre sugerido y directorio inicial opcional.
    private func presentSavePanel(name: String, content: String, initialFolder: URL? = nil) {
        let panel = NSSavePanel()
        panel.title = "Guardar archivo traducido"
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .text]
        panel.canCreateDirectories = true
        // Pre-seleccionar la carpeta configurada si existe.
        if let folder = initialFolder {
            let accessed = folder.startAccessingSecurityScopedResource()
            panel.directoryURL = folder
            if accessed { folder.stopAccessingSecurityScopedResource() }
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            presentWriteError(error, filename: name)
        }
    }

    /// Muestra una alerta de error de escritura.
    private func presentWriteError(_ error: Error, filename: String) {
        let alert = NSAlert()
        alert.messageText = "No se pudo guardar el archivo"
        alert.informativeText = "\(filename): \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
