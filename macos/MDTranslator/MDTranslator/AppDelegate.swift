// AppDelegate.swift — NSApplicationDelegate para shutdown limpio y apertura de archivos.
// Phase 11: application(_:open:) para drag al Dock y "Abrir con…".
// Phase 13: batch nativo multi-archivo vía API Python + Dock progress + Open Recent.
// Phase 15: SERVICES-01 — nonisolated en métodos @objc del delegate para evitar thunk
//   async de Swift 6. Sin @MainActor a nivel de clase para compatibilidad con
//   @NSApplicationDelegateAdaptor en Xcode 17/Swift 6.
// Phase 18: flujo batch reemplazado por openBatchSheet + applicationShouldTerminate (SSE nativo).
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
    // D-10: la intercepción de ⌘Q se gestiona en MDTranslatorApp.commands via
    // CommandGroup(replacing: .appTermination) — patrón correcto para SwiftUI apps.

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
