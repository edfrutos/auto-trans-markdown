// ServiceHandler.swift — Proveedor del servicio del sistema "Traducir con MDTranslator".
// Se registra con NSApp.servicesProvider al arrancar la app.
// macOS llama a translateWithMDTranslator(_:userData:error:) cuando el usuario selecciona
// texto en cualquier app y elige Services > Traducir con MDTranslator.
// Phase 13: SERVICES-01.
// NSReturnTypes declarado en Info.plist: la traducción se escribe de vuelta al pasteboard
// del servicio y macOS reemplaza la selección original automáticamente en la app origen.
import AppKit
import Foundation

@MainActor
final class ServiceHandler: NSObject {
    static let shared = ServiceHandler()

    /// Referencia al ServerManager para obtener el puerto activo.
    /// Asignada en MDTranslatorApp.body igual que AppDelegate.
    var serverManager: ServerManager?

    private override init() {}

    // MARK: - Debug log (nonisolated — llamable desde cualquier hilo sin actor hop)

    nonisolated private func dbg(_ msg: String) {
        // NSLog → visible en Console.app (filtrar por proceso MDTranslator o "ServiceHandler")
        NSLog("[ServiceHandler] %@", msg)
        // También en fichero para referencia
        let line = "\(Date()): \(msg)\n"
        let path = "/tmp/md-service-debug.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(Data(line.utf8))
            try? fh.close()
        } else {
            try? Data(line.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    // MARK: - Services handler

    /// macOS llama a este método cuando el usuario invoca el servicio desde otra app.
    /// CRÍTICO: debe ser `nonisolated` para que el runtime Swift 6 no envuelva la llamada
    /// Objective-C en un Task asíncrono. Con @MainActor sin nonisolated, el handler retorna
    /// vacío inmediatamente y el cuerpo real nunca se ejecuta (NSServices espera respuesta sync).
    /// NSServices siempre llama en el hilo principal → MainActor.assumeIsolated es seguro.
    @objc
    nonisolated func translateWithMDTranslator(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        dbg("SERVICE CALLED")
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            dbg("EXIT: no text in pasteboard")
            error?.pointee = "No hay texto seleccionado" as NSString
            return
        }
        dbg("text length=\(text.count)")

        // Acceder a propiedades @MainActor de forma segura: NSServices siempre llama en hilo principal.
        // MainActor.assumeIsolated permite leer serverManager sin el overhead del actor-hop asíncrono.
        let (port, targetLang): (Int, String) = MainActor.assumeIsolated {
            guard let mgr = self.serverManager else {
                self.dbg("serverManager is nil inside assumeIsolated")
                return (0, "es")
            }
            self.dbg("state=\(mgr.state) port=\(mgr.serverPort)")

            // Si pbs acaba de lanzar la app en background, el servidor puede estar aún arrancando.
            let readyDeadline = Date().addingTimeInterval(15)
            while mgr.state != .running && Date() < readyDeadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.15))
            }
            guard mgr.state == .running else {
                self.dbg("EXIT: state not running after wait")
                return (0, "es")
            }
            let lang = UserDefaults.standard.string(forKey: "defaultTargetLang") ?? "es"
            self.dbg("server ready port=\(mgr.serverPort) lang=\(lang)")
            return (mgr.serverPort, lang)
        }

        guard port != 0 else {
            error?.pointee = "El servidor tardó demasiado en arrancar. Ábrelo y espera a que cargue." as NSString
            return
        }

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
        let body: [String: String] = ["content": text, "target_lang": targetLang]
        req.httpBody = try? JSONEncoder().encode(body)

        let task = URLSession.shared.dataTask(with: req) { [self] data, response, netErr in
            // TranslateResponse: { content: str, segments_total: int, segments_translated: int, ... }
            // JSONSerialization tolera campos no-String que romperían JSONDecoder<[String:String]>.
            // El campo es "content", no "translation".
            if let err = netErr {
                self.dbg("HTTP error: \(err)")
            } else if let http = response as? HTTPURLResponse {
                self.dbg("HTTP status: \(http.statusCode)")
            }
            if let data {
                let raw = String(data: data.prefix(200), encoding: .utf8) ?? "(binary)"
                self.dbg("HTTP body: \(raw)")
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["content"] as? String {
                    translation = result
                    self.dbg("translation OK (\(result.count) chars)")
                } else {
                    self.dbg("JSON parse failed or 'content' key missing")
                }
            } else {
                self.dbg("data is nil")
            }
            semaphore.signal()  // señal desde la cola interna de URLSession (background)
        }
        task.resume()
        dbg("semaphore waiting...")
        semaphore.wait()  // espera en el hilo del servicio (NSServices siempre es síncrono)
        dbg("semaphore released, translation=\(translation != nil ? "OK" : "nil")")

        if let result = translation {
            // Con NSReturnTypes: escribir de vuelta al pasteboard del servicio.
            // macOS reemplaza automáticamente el texto seleccionado en la app origen
            // (TextEdit, Safari, etc.) sin que el usuario tenga que ⌘V.
            pasteboard.clearContents()
            pasteboard.setString(result, forType: .string)
            dbg("pasteboard written OK")
        } else {
            dbg("translation nil -> setting error")
            error?.pointee = "No se pudo traducir. Comprueba tu API key en MDTranslator." as NSString
        }
    }
}
