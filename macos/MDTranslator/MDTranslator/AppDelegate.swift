// AppDelegate.swift — NSApplicationDelegate para shutdown limpio y apertura de archivos.
// Phase 11: application(_:open:) para drag al Dock y "Abrir con…".
// Phase 13: batch nativo multi-archivo vía API Python + Dock progress + Open Recent.
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Referencia al ServerManager compartido con el App struct.
    var serverManager: ServerManager?

    // MARK: - Launch

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SERVICES-01: registrar el proveedor del servicio del sistema.
        // Debe hacerse en applicationDidFinishLaunching, no en el body de SwiftUI.
        NSApp.servicesProvider = ServiceHandler.shared
        // Notificar a macOS que actualice el menú de servicios de todas las apps en curso.
        NSUpdateDynamicServices()

        // HOTKEY-01: registrar hotkey global ⌥⇧M (NSEvent, necesita Accesibilidad).
        GlobalHotkeyManager.shared.register()
    }

    // MARK: - Shutdown

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkeyManager.shared.unregister()   // liberar monitor de eventos ⌥⇧M
        serverManager?.stop()
        Thread.sleep(forTimeInterval: 1.0)
        // Force Quit no llama a este método.
        // La limpieza de huérfanos se gestiona en ServerManager.init() via /tmp/md-translator-python.pid
    }

    // MARK: - Apertura de archivos (Dock drag & drop, "Abrir con…", Open Recent, doble clic Finder)

    func application(_ application: NSApplication, open urls: [URL]) {
        let markdownURLs = urls.filter { $0.pathExtension.lowercased() == "md" }
        guard !markdownURLs.isEmpty else { return }

        // Traer la ventana principal al frente
        NSApp.activate(ignoringOtherApps: true)

        // Registrar en Open Recent (RECENT-01)
        markdownURLs.forEach { NSDocumentController.shared.noteNewRecentDocumentURL($0) }

        if markdownURLs.count == 1 {
            // Un solo archivo → cargar en el editor (comportamiento original)
            loadInEditor(url: markdownURLs[0])
        } else {
            // Múltiples archivos → confirmar y lanzar batch nativo (DOCK-01)
            confirmAndBatch(markdownURLs)
        }
    }

    // MARK: - Privado: cargar en editor

    private func loadInEditor(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            NotificationCenter.default.post(
                name: WebView.openMarkdownNotification,
                object: content
            )
        } catch {
            presentError("No se pudo abrir el archivo", detail: "\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Privado: batch multi-archivo

    private func confirmAndBatch(_ urls: [URL]) {
        let alert = NSAlert()
        alert.messageText = "Traducir \(urls.count) archivos"
        alert.informativeText = """
        Se han arrastrado \(urls.count) archivos .md.
        Idioma destino: \(targetLangLabel())
        Los archivos traducidos se guardarán en la carpeta de salida configurada (o en Descargas si no hay ninguna).
        """
        alert.addButton(withTitle: "Traducir")
        alert.addButton(withTitle: "Cancelar")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let port = serverManager?.serverPort,
              serverManager?.state == .running else {
            presentError("Servidor no disponible", detail: "El servidor Python aún no ha arrancado. Vuelve a intentarlo en unos segundos.")
            return
        }
        let targetLang = UserDefaults.standard.string(forKey: "defaultTargetLang") ?? "es"
        Task { await batchTranslate(urls: urls, port: port, targetLang: targetLang) }
    }

    /// Llama a /api/translate para cada archivo, actualiza el Dock tile y guarda los resultados.
    @MainActor
    private func batchTranslate(urls: [URL], port: Int, targetLang: String) async {
        let total = urls.count
        DockProgressManager.shared.showProgress(current: 0, total: total)
        DockProgressManager.shared.setBadge("\(total)")

        var saved: [String]  = []
        var failed: [String] = []

        for (index, url) in urls.enumerated() {
            DockProgressManager.shared.showProgress(current: index, total: total)

            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                failed.append(url.lastPathComponent)
                continue
            }

            do {
                let translation = try await callTranslateAPI(text: text, targetLang: targetLang, port: port)
                let outName = url.deletingPathExtension().lastPathComponent + ".\(targetLang).md"
                if OutputManager.shared.saveFileSilently(name: outName, content: translation) {
                    saved.append(outName)
                } else {
                    failed.append(url.lastPathComponent)
                }
            } catch {
                failed.append(url.lastPathComponent)
            }
        }

        DockProgressManager.shared.hideProgress()
        DockProgressManager.shared.setBadge(nil)

        // Notificación del sistema
        let summary = saved.isEmpty ? "Sin traducciones" : "\(saved.count) archivo\(saved.count == 1 ? "" : "s") traducido\(saved.count == 1 ? "" : "s")"
        NotificationManager.shared.sendTranslationDone(filename: summary, langs: targetLang)

        // Revelar carpeta de salida si hubo éxito
        if !saved.isEmpty { OutputManager.shared.revealOutputFolder() }

        // Resumen de errores
        if !failed.isEmpty {
            presentError(
                "Algunos archivos fallaron",
                detail: "No se pudo traducir: \(failed.joined(separator: ", "))"
            )
        }
    }

    /// POST /api/translate → devuelve el texto traducido.
    private func callTranslateAPI(text: String, targetLang: String, port: Int) async throws -> String {
        let url = URL(string: "http://127.0.0.1:\(port)/api/translate")!
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["text": text, "target_lang": targetLang]
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        // La respuesta es {"translation": "...", ...}
        let json = try JSONDecoder().decode([String: String].self, from: data)
        guard let translation = json["translation"] else {
            throw URLError(.cannotParseResponse)
        }
        return translation
    }

    // MARK: - Helpers

    private func targetLangLabel() -> String {
        let code = UserDefaults.standard.string(forKey: "defaultTargetLang") ?? "es"
        let locale = Locale(identifier: "es")
        return locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private func presentError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}
