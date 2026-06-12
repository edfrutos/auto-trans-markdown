// CrashReporterManager.swift — Detección de crashes y envío opcional de informes anónimos.
// Mecánica: al arrancar se comprueba si la sesión anterior terminó limpiamente
// (sentinel en UserDefaults que se activa en applicationWillTerminate).
// Si no terminó limpiamente Y el usuario optó por enviar reportes, se muestra
// una alerta y se abre una URL de GitHub Issues con información de diagnóstico.
// Phase 15: CRASH-01.
import Foundation
import AppKit

@MainActor
final class CrashReporterManager {
    static let shared = CrashReporterManager()

    // MARK: - Keys UserDefaults (privados, con prefijo de bundle)
    private static let sentinelKey      = "MDTranslator.cleanExit"
    private static let hasLaunchedKey   = "MDTranslator.hasLaunchedBefore"
    static         let sendReportsKey   = "MDTranslator.sendCrashReports"

    /// true si en el arranque actual se detectó un cierre anómalo de la sesión anterior.
    private(set) var crashDetectedOnLaunch: Bool

    private init() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: Self.hasLaunchedKey)
        let cleanExit         = UserDefaults.standard.bool(forKey: Self.sentinelKey)
        // Solo consideramos crash si la app ya se había lanzado antes.
        // En el primer arranque, cleanExit=false (valor por defecto del bool) no es un crash.
        crashDetectedOnLaunch = hasLaunchedBefore && !cleanExit
        // Restablecer sentinel; se re-activará en applicationWillTerminate.
        UserDefaults.standard.set(false,  forKey: Self.sentinelKey)
        UserDefaults.standard.set(true,   forKey: Self.hasLaunchedKey)
    }

    // MARK: - API pública

    /// Guardar el sentinel de "salida limpia". Llamar desde applicationWillTerminate.
    func markCleanExit() {
        UserDefaults.standard.set(true, forKey: Self.sentinelKey)
    }

    /// Preferencia del usuario: enviar informes anónimos de diagnóstico.
    var sendCrashReports: Bool {
        get { UserDefaults.standard.bool(forKey: Self.sendReportsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.sendReportsKey) }
    }

    /// Comprobar si hubo un crash en la sesión anterior y, si el usuario optó por
    /// enviar reportes, mostrar la alerta de diagnóstico.
    /// Llamar desde applicationDidFinishLaunching (el delay de 2 s espera a que la
    /// ventana principal sea visible).
    func checkAndPromptIfNeeded() {
        guard crashDetectedOnLaunch, sendCrashReports else { return }
        // Task heredará el actor (@MainActor) de este método; el sleep evita bloquear el arranque.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showCrashReportAlert()
        }
    }

    // MARK: - Privado

    private func showCrashReportAlert() {
        let alert = NSAlert()
        alert.messageText = "La sesión anterior no terminó correctamente"
        alert.informativeText = """
        MD Translator detectó que la sesión anterior no se cerró de forma limpia.
        ¿Deseas enviar un informe de diagnóstico anónimo al autor para ayudar a mejorar la app?
        """
        alert.addButton(withTitle: "Enviar informe")
        alert.addButton(withTitle: "No, gracias")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            openGitHubIssue()
        }
    }

    private func openGitHubIssue() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os      = ProcessInfo.processInfo.operatingSystemVersionString
        let arch    = ProcessInfo.processInfo.environment["PROCESSOR_ARCHITEW6432"] ?? "arm64"

        // Últimas 30 líneas del log del servidor Python (información de diagnóstico clave).
        let logPath = NSTemporaryDirectory() + "md-translator-server.log"
        let logTail: String
        if let logContent = try? String(contentsOfFile: logPath, encoding: .utf8) {
            let lines = logContent
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .suffix(30)
            logTail = lines.joined(separator: "\n")
        } else {
            logTail = "(log no disponible)"
        }

        let body = """
        **Versión:** \(version) (build \(build))
        **macOS:** \(os) · \(arch)

        **Últimas líneas del log del servidor:**
        ```
        \(logTail)
        ```

        **Pasos para reproducir:**
        <!-- Describe qué estabas haciendo antes del crash -->

        **Comportamiento esperado:**
        <!-- La app debería... -->
        """

        // Abrir una URL de GitHub Issues pre-rellena. No requiere ningún backend.
        let title   = "Crash report v\(version)"
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://github.com/edfrutos/auto-trans-markdown/issues/new"
            + "?title=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            + "&body=\(encoded)"

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
