// AppDelegate.swift — NSApplicationDelegate para shutdown limpio y apertura de archivos.
// Phase 11: application(_:open:) para drag al Dock y "Abrir con…".
// Phase 13: batch nativo multi-archivo vía API Python + Dock progress + Open Recent.
// Phase 15: SERVICES-01 — nonisolated en métodos @objc del delegate para evitar thunk
//   async de Swift 6. Sin @MainActor a nivel de clase para compatibilidad con
//   @NSApplicationDelegateAdaptor en Xcode 17/Swift 6.
// Phase 18: flujo batch reemplazado por openBatchSheet + SSE nativo; D-10 via applicationShouldTerminate+.terminateLater.
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
            NSUpdateDynamicServices()
            NSLog("[AppDelegate] applicationDidFinishLaunching OK")
            // HOTKEY-01: registrar hotkey global ⌥⇧M (NSEvent, necesita Accesibilidad).
            GlobalHotkeyManager.shared.register()
            // D-10: interceptar ⌘Q a nivel de evento, antes del sistema de menús.
            // Fiable aunque @NSApplicationDelegateAdaptor cree dos instancias de AppDelegate
            // y applicationShouldTerminate se llame en la instancia incorrecta.
            // NSEvent monitors corren en el hilo principal → MainActor.assumeIsolated seguro.
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers == "q" else { return event }
                // consumeEvent: Bool cruza contexto como Sendable; NSEvent no se pasa al actor.
                var consumeEvent = false
                MainActor.assumeIsolated {
                    guard BatchJobManager.shared.isRunning else { return }
                    let n = BatchJobManager.shared.completedCount
                    let m = BatchJobManager.shared.totalCount
                    let alert = NSAlert()
                    alert.messageText = "Hay un lote en curso (\(n) de \(m) archivos)"
                    alert.informativeText = "Si sales ahora, el servidor Python se detendrá y se perderán los archivos que aún no se han traducido."
                    alert.addButton(withTitle: "Salir y cancelar")
                    alert.addButton(withTitle: "Continuar en segundo plano")
                    alert.alertStyle = .warning
                    consumeEvent = true  // siempre consumir ⌘Q cuando hay lote activo
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSApp.terminate(nil)
                    }
                }
                return consumeEvent ? nil : event
            }
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

    // MARK: - Shutdown: D-10 — interceptar ⌘Q con lote activo

    // applicationShouldTerminate se llama en el hilo principal antes de que NSApp termine.
    // Devolver .terminateLater congela el ciclo de terminación; NSApp.reply() lo desbloquea.
    // Task { @MainActor } evita MainActor.assumeIsolated desde el contexto nonisolated.
    nonisolated
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Diagnóstico D-10: confirmar que el método se invoca en este proceso.
        // Comprueba con: cat /tmp/md-shouldterminate.txt
        let diagText = "applicationShouldTerminate called at \(Date()) — delegate=\(type(of: self))\n"
        try? diagText.write(toFile: "/tmp/md-shouldterminate.txt", atomically: true, encoding: .utf8)
        NSLog("[D-10] applicationShouldTerminate — returning .terminateLater")

        Task { @MainActor in
            NSLog("[D-10] Task @MainActor running — isRunning=%@",
                  BatchJobManager.shared.isRunning ? "true" : "false")
            guard BatchJobManager.shared.isRunning else {
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }
            let n = BatchJobManager.shared.completedCount
            let m = BatchJobManager.shared.totalCount
            let alert = NSAlert()
            alert.messageText = "Hay un lote en curso (\(n) de \(m) archivos)"
            alert.informativeText = "Si sales ahora, el servidor Python se detendrá y se perderán los archivos que aún no se han traducido."
            alert.addButton(withTitle: "Salir y cancelar")
            alert.addButton(withTitle: "Continuar en segundo plano")
            alert.alertStyle = .warning
            NSApp.reply(toApplicationShouldTerminate: alert.runModal() == .alertFirstButtonReturn)
        }
        return .terminateLater
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
                openBatchSheet(markdownURLs)
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

    // MARK: - Privado: abrir BatchSheet

    /// Prepara el BatchJobManager con las URLs indicadas y publica la notificación
    /// .openBatchSheet para que MDTranslatorApp presente la sheet (Phase 18).
    @MainActor
    private func openBatchSheet(_ urls: [URL]) {
        BatchJobManager.shared.prepareWith(urls: urls)
        NotificationCenter.default.post(name: .openBatchSheet, object: nil)
    }

    // MARK: - Helpers

    @MainActor
    private func presentError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}
