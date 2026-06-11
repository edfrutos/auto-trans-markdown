// AppDelegate.swift — NSApplicationDelegate para shutdown limpio y apertura de archivos.
// Phase 11: application(_:open:) para drag al Dock y "Abrir con…".
// Phase 13: batch nativo multi-archivo vía API Python + Dock progress + Open Recent.
// Phase 15: SERVICES-01 — nonisolated en métodos @objc del delegate para evitar thunk
//   async de Swift 6. Sin @MainActor a nivel de clase para compatibilidad con
//   @NSApplicationDelegateAdaptor en Xcode 17/Swift 6.
import AppKit

/// AppDelegate sin @MainActor a nivel de clase para que @NSApplicationDelegateAdaptor
/// la instancie correctamente en Swift 6/Xcode 17.
///
/// Patrón aplicado:
/// - Métodos @objc del delegate → nonisolated (thunk ObjC síncrono, sin actor hop)
/// - Cuerpo de esos métodos → MainActor.assumeIsolated { } (acceso seguro a APIs UIKit/AppKit)
/// - Helpers privados con acceso a AppKit/NSApp → @MainActor explícito
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Referencia al ServerManager compartido con el App struct.
    var serverManager: ServerManager?

    override init() {
        super.init()
        // Diagnóstico SERVICES-01: escritura directa a archivo (no depende de unified logging).
        // Comprueba con: cat /tmp/md-appdelegate-init.txt
        let marker = "/tmp/md-appdelegate-init.txt"
        let text = "AppDelegate.init() called at \(Date())\n"
        try? text.write(toFile: marker, atomically: true, encoding: .utf8)
        NSLog("[AppDelegate] init() — instancia creada por @NSApplicationDelegateAdaptor")
    }

    // MARK: - Launch

    /// nonisolated → Swift 6 genera thunk ObjC síncrono (no async Task).
    /// MainActor.assumeIsolated → acceso seguro a NSApp, etc.;
    /// NSApplicationDelegate siempre llama en hilo principal.
    nonisolated
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Diagnóstico: escritura directa antes del actor hop.
        // Comprueba con: cat /tmp/md-appdelegate-adfl.txt
        let marker = "/tmp/md-appdelegate-adfl.txt"
        let text = "applicationDidFinishLaunching called at \(Date())\n"
        try? text.write(toFile: marker, atomically: true, encoding: .utf8)
        MainActor.assumeIsolated {
            // SERVICES-01: registrar el proveedor del servicio del sistema.
            // MDTranslatorApp.body también lo hace como respaldo.
            NSApp.servicesProvider = ServiceHandler.shared
            NSLog("[AppDelegate] servicesProvider: %@",
                  String(describing: type(of: NSApp.servicesProvider)))
            NSUpdateDynamicServices()
            NSLog("[AppDelegate] applicationDidFinishLaunching OK")
            // HOTKEY-01: registrar hotkey global ⌥⇧M (NSEvent, necesita Accesibilidad).
            GlobalHotkeyManager.shared.register()
            // CRASH-01: inicializar el crash reporter (detecta cierre anómalo de la sesión
            // anterior) y mostrar alerta opt-in si el usuario lo ha habilitado.
            // checkAndPromptIfNeeded() aplica un delay de 2 s para no bloquear el arranque.
            _ = CrashReporterManager.shared
            CrashReporterManager.shared.checkAndPromptIfNeeded()
        }
    }

    // MARK: - Shutdown

    nonisolated
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            GlobalHotkeyManager.shared.unregister()
            serverManager?.stop()
            // CRASH-01: marcar salida limpia para que el siguiente arranque no lo
            // detecte como crash. Debe hacerse ANTES de que el proceso termine.
            CrashReporterManager.shared.markCleanExit()
        }
        Thread.sleep(forTimeInterval: 1.0)
        // Force Quit no llama a este método.
        // La limpieza de huérfanos se gestiona en ServerManager.init() via /tmp/md-translator-python.pid
    }

    // MARK: - Apertura de archivos (Dock drag & drop, "Abrir con…", Open Recent, doble clic Finder)

    nonisolated
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            let markdownURLs = urls.filter { $0.pathExtension.lowercased() == "md" }
            guard !markdownURLs.isEmpty else { return }

            NSApp.activate(ignoringOtherApps: true)
            markdownURLs.forEach { NSDocumentController.shared.noteNewRecentDocumentURL($0) }

            if markdownURLs.count == 1 {
                loadInEditor(url: markdownURLs[0])
            } else {
                confirmAndBatch(markdownURLs)
            }
        }
    }

    // MARK: - Privado: cargar en editor

    @MainActor
    private func loadInEditor(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            NotificationCenter.default.post(
                name: WebView.openMarkdownNotification,
                object: content
            )
        } catch {
            presentError("No se pudo abrir el archivo",
                         detail: "\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Privado: batch multi-archivo

    @MainActor
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
            presentError("Servidor no disponible",
                         detail: "El servidor Python aún no ha arrancado. Vuelve a intentarlo en unos segundos.")
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

        let summary = saved.isEmpty
            ? "Sin traducciones"
            : "\(saved.count) archivo\(saved.count == 1 ? "" : "s") traducido\(saved.count == 1 ? "" : "s")"
        NotificationManager.shared.sendTranslationDone(filename: summary, langs: targetLang)

        if !saved.isEmpty { OutputManager.shared.revealOutputFolder() }

        if !failed.isEmpty {
            presentError("Algunos archivos fallaron",
                         detail: "No se pudo traducir: \(failed.joined(separator: ", "))")
        }
    }

    /// POST /api/translate → devuelve el texto traducido.
    private func callTranslateAPI(text: String, targetLang: String, port: Int) async throws -> String {
        let url = URL(string: "http://127.0.0.1:\(port)/api/translate")!
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["content": text, "target_lang": targetLang]
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translation = json["content"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return translation
    }

    // MARK: - Helpers

    @MainActor
    private func targetLangLabel() -> String {
        let code = UserDefaults.standard.string(forKey: "defaultTargetLang") ?? "es"
        let locale = Locale(identifier: "es")
        return locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    @MainActor
    private func presentError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}
