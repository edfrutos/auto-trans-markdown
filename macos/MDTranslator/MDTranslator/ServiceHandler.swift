// ServiceHandler.swift — Proveedor del servicio del sistema "Traducir con MDTranslator".
// Se registra con NSApp.servicesProvider al arrancar la app.
// macOS llama a translateWithMDTranslator(_:userData:error:) cuando el usuario selecciona
// texto en cualquier app y elige Services > Traducir con MDTranslator.
// Phase 13: SERVICES-01.
// Nota: sin NSReturnTypes (send-only) — la traducción se copia al portapapeles general
// y una notificación avisa al usuario. Así el ítem es visible sin necesidad de foreground.
import AppKit
import Foundation

@MainActor
final class ServiceHandler: NSObject {
    static let shared = ServiceHandler()

    /// Referencia al ServerManager para obtener el puerto activo.
    /// Asignada en MDTranslatorApp.body igual que AppDelegate.
    var serverManager: ServerManager?

    private override init() {}

    // MARK: - Services handler

    /// macOS llama a este método cuando el usuario invoca el servicio desde otra app.
    /// El texto seleccionado llega en `pasteboard`; devolvemos la traducción en el mismo.
    /// El nombre del método DEBE coincidir con NSMessage en Info.plist.
    @objc
    func translateWithMDTranslator(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error?.pointee = "No hay texto seleccionado" as NSString
            return
        }
        guard let manager = serverManager,
              manager.state == .running else {
            error?.pointee = "MDTranslator no está en ejecución. Ábrelo primero." as NSString
            return
        }

        let port       = manager.serverPort
        let targetLang = UserDefaults.standard.string(forKey: "defaultTargetLang") ?? "es"

        // Llamada síncrona a la API Python usando URLSession + semáforo.
        // El completion handler de URLSession corre en su cola interna (background),
        // por lo que el semaphore.wait() en el hilo actual no produce deadlock.
        let semaphore = DispatchSemaphore(value: 0)
        var translation: String?

        guard let url = URL(string: "http://127.0.0.1:\(port)/api/translate") else {
            error?.pointee = "URL de API inválida" as NSString
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["text": text, "target_lang": targetLang]
        req.httpBody = try? JSONEncoder().encode(body)

        let task = URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data,
               let json = try? JSONDecoder().decode([String: String].self, from: data),
               let result = json["translation"] {
                translation = result
            }
            semaphore.signal()  // señal desde la cola interna de URLSession (background)
        }
        task.resume()
        semaphore.wait()  // espera en el hilo del servicio; no bloquea el hilo principal de UI

        if let result = translation {
            // Sin NSReturnTypes: escribimos en el portapapeles general en lugar de
            // devolver al pasteboard del servicio (que reemplazaría la selección).
            // El usuario pega con ⌘V donde lo necesite.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)
            NotificationManager.shared.send(
                title: "Traducción copiada",
                body: "Pega con ⌘V para insertar el resultado."
            )
        } else {
            error?.pointee = "No se pudo traducir. Comprueba tu API key en MDTranslator." as NSString
        }
    }
}
