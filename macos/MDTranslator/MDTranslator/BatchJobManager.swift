// BatchJobManager.swift — Cliente SSE del jobs API y estado del lote.
// Singleton @Observable @MainActor que encapsula el estado del job, el cliente SSE,
// la cancelación cooperativa (D-09), la descarga del ZIP y su extracción con /usr/bin/unzip.
// Sigue el mismo patrón que ServerManager.swift: @Observable @MainActor, Task async, guard de estado.
import Foundation
import AppKit
import Observation

// MARK: - Estado del lote

/// Estado de la máquina de estados del lote SSE (5 estados, análogo a ServerManager.State).
/// Nombre BatchJobState para evitar colisión conceptual con src/jobs.py (JobState Python).
enum BatchJobState {
    /// Sin job activo — sheet no mostrada.
    case idle
    /// Lista de archivos lista para traducir (D-13: confirmar + traducir en 1 componente).
    case prepared(urls: [URL])
    /// SSE stream activo — job_id conocido.
    case running(jobId: String)
    /// DELETE enviado, esperando evento complete del stream (D-09 cancelación cooperativa).
    case cancelling
    /// Traducción finalizada — resumen para mostrar en la sheet (D-03).
    case done(ok: Int, errors: [(String, String)], cancelled: Bool)
}

// MARK: - Manager

@MainActor
@Observable
final class BatchJobManager {

    // MARK: - Singleton

    static let shared = BatchJobManager()
    private init() {}

    // MARK: - Propiedades observables (progreso)

    /// Estado de la máquina de estados del lote.
    private(set) var jobState: BatchJobState = .idle

    /// Nombre del archivo en traducción actualmente (evento file_start).
    private(set) var currentFile: String = ""

    /// Archivos completados (file_done + error acumulados).
    private(set) var filesDone: Int = 0

    /// Total de archivos del lote (de file_start.total_files).
    private(set) var filesTotal: Int = 0

    /// Segmentos traducidos del archivo en curso (evento segment_progress.done).
    private(set) var segmentsDone: Int = 0

    /// Total de segmentos del archivo en curso (evento segment_progress.total).
    private(set) var segmentsTotal: Int = 0

    // MARK: - Propiedades privadas

    private var errorMessages: [(String, String)] = []
    private var streamTask: Task<Void, Never>?
    private var currentJobId: String?

    /// Puerto del servidor local — almacenado al inicio de start(port:targetLang:).
    private var serverPort: Int = 0

    /// Idioma destino del job — almacenado para usarlo en el evento complete.
    private var targetLangStored: String = ""

    // MARK: - Propiedades computadas públicas

    /// true si hay un job activo (running) o pendiente de cancelar (cancelling).
    var isRunning: Bool {
        if case .running = jobState { return true }
        if case .cancelling = jobState { return true }
        return false
    }

    /// Alias de filesDone — para el alert D-10 (applicationShouldTerminate).
    var completedCount: Int { filesDone }

    /// Alias de filesTotal — para el alert D-10.
    var totalCount: Int { filesTotal }

    // MARK: - API pública

    /// Transición a .prepared — llamada desde AppDelegate o Commands antes de mostrar la sheet.
    func prepareWith(urls: [URL]) {
        jobState = .prepared(urls: urls)
        // Resetear contadores del job anterior
        currentFile   = ""
        filesDone     = 0
        filesTotal    = 0
        segmentsDone  = 0
        segmentsTotal = 0
        errorMessages = []
        currentJobId  = nil
    }

    /// Resetea a .idle — llamada por BatchSheet al cerrarse sin traducir.
    func reset() {
        jobState = .idle
    }

    /// Cancela el job en curso: envía DELETE y pone estado a .cancelling.
    /// NO cancela streamTask aquí (pitfall 2 de RESEARCH.md):
    /// el stream debe seguir recibiendo hasta el evento complete{cancelled:true}.
    func cancel() {
        guard case .running(let jobId) = jobState else { return }
        jobState = .cancelling
        // Enviar DELETE en background — no bloquear el MainActor
        let port = serverPort
        Task {
            await sendDelete(jobId: jobId, port: port)
        }
    }

    /// Lanza el job SSE completo: POST multipart → guarda job_id → inicia stream SSE.
    /// - Parameters:
    ///   - port: Puerto del servidor backend (de ServerManager.serverPort).
    ///   - targetLang: Código ISO del idioma destino (D-12: un solo idioma).
    func start(port: Int, targetLang: String) async {
        guard case .prepared(let urls) = jobState else { return }

        // Guardar port y targetLang para usarlos en cancel() y en el evento complete
        serverPort = port
        targetLangStored = targetLang

        // Paso 1: POST multipart → obtener job_id
        let jobId: String
        do {
            jobId = try await createJob(urls: urls, targetLang: targetLang, port: port)
        } catch {
            jobState = .done(
                ok: 0,
                errors: [("upload", error.localizedDescription)],
                cancelled: false
            )
            return
        }

        // Paso 2: Actualizar estado y mostrar progreso en el Dock
        currentJobId = jobId
        jobState = .running(jobId: jobId)
        DockProgressManager.shared.showProgress(current: 0, total: urls.count)
        DockProgressManager.shared.setBadge("\(urls.count)")

        // Paso 3: Iniciar stream SSE en una Task (no bloquea el MainActor)
        let capturedPort = port
        streamTask = Task {
            await self.runSSEStream(jobId: jobId, port: capturedPort)
        }
        // Esperar a que el stream termine (complete o error de red)
        await streamTask?.value
    }

    // MARK: - Privado: POST multipart

    /// Construye el cuerpo multipart/form-data y hace POST a /api/translate/batch/jobs.
    /// Patrón: Pattern 3 de RESEARCH.md (multipart sin librerías).
    /// T-18-02: URL hardcodeada a 127.0.0.1:{port} — sin interpolación de input de usuario.
    private func createJob(urls: [URL], targetLang: String, port: Int) async throws -> String {
        let boundary = UUID().uuidString
        var body = Data()

        func append(_ string: String) {
            if let d = string.data(using: .utf8) { body += d }
        }

        // Campo target_lang (D-12: un solo idioma destino)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"target_lang\"\r\n\r\n")
        append("\(targetLang)\r\n")

        // Un campo "files" por archivo — T-18-05: Data(contentsOf:) acotado por MAX_BATCH_UPLOAD_MB=50MB
        for url in urls {
            let raw = try Data(contentsOf: url)
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"files\"; filename=\"\(url.lastPathComponent)\"\r\n")
            append("Content-Type: text/markdown; charset=utf-8\r\n\r\n")
            body += raw
            append("\r\n")
        }
        append("--\(boundary)--\r\n")

        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/api/translate/batch/jobs")!,
            timeoutInterval: 30
        )
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobId = json["job_id"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return jobId
    }

    // MARK: - Privado: Stream SSE

    /// Lee el stream SSE del job línea a línea con URLSession.bytes.
    /// Pitfall 5: guard hasPrefix("data: ") ignora líneas vacías (separadores SSE \n\n).
    /// Pitfall 2: NO cancelar streamTask desde cancel() — dejar que el stream llegue a complete.
    private func runSSEStream(jobId: String, port: Int) async {
        // T-18-02: URL hardcodeada a loopback
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/api/translate/batch/jobs/\(jobId)/events")!
        )
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // API_TOKEN vacío en entorno local = auth no-op (Q1 resuelto en RESEARCH.md)

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run {
                    jobState = .done(
                        ok: 0,
                        errors: [("stream", "Respuesta inesperada del servidor SSE")],
                        cancelled: false
                    )
                }
                return
            }

            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }
                // Pitfall 5: ignorar líneas vacías (separador SSE \n\n) y cualquier otro prefijo
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))
                guard let data = jsonStr.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = event["type"] as? String
                else { continue }

                // Actualizar estado en MainActor
                await MainActor.run {
                    self.handleSSELine(type: type, payload: event)
                }

                // El stream termina con "complete" — pitfall 4: descargar ZIP solo después de aquí
                if type == "complete" { break }
            }
        } catch {
            // URLError.cancelled ocurre si la Task es cancelada — silenciar (pitfall 2)
            if (error as? URLError)?.code != .cancelled {
                await MainActor.run {
                    self.jobState = .done(
                        ok: 0,
                        errors: [("red", error.localizedDescription)],
                        cancelled: false
                    )
                    DockProgressManager.shared.hideProgress()
                    DockProgressManager.shared.setBadge(nil)
                }
            }
        }
    }

    // MARK: - Privado: Procesado de eventos SSE

    /// Actualiza el estado del job según el tipo de evento SSE recibido.
    /// Llamado desde runSSEStream en el @MainActor.
    private func handleSSELine(type: String, payload: [String: Any]) {
        switch type {

        case "file_start":
            // Nuevo archivo comenzando: actualizar nombre y totales
            currentFile   = payload["filename"] as? String ?? ""
            filesTotal    = payload["total_files"] as? Int ?? filesTotal
            segmentsDone  = 0
            segmentsTotal = 0

        case "segment_progress":
            // Progreso de segmentos del archivo en curso
            segmentsDone  = payload["done"]  as? Int ?? segmentsDone
            segmentsTotal = payload["total"] as? Int ?? segmentsTotal

        case "file_done":
            // Archivo completado con éxito — SSE-04: actualizar Dock
            filesDone += 1
            DockProgressManager.shared.showProgress(current: filesDone, total: filesTotal)

        case "error":
            // Archivo fallido — registrar error y contabilizar como "procesado"
            let filename = payload["filename"] as? String ?? "?"
            let msg      = payload["message"]  as? String ?? "Error desconocido"
            errorMessages.append((filename, msg))
            filesDone += 1
            DockProgressManager.shared.showProgress(current: filesDone, total: filesTotal)

        case "complete":
            // Fin del stream — pitfall 4: el ZIP está disponible AHORA (build_batch_zip ya ocurrió)
            let ok        = payload["ok_count"]  as? Int  ?? 0
            let cancelled = payload["cancelled"] as? Bool ?? false
            jobState = .done(ok: ok, errors: errorMessages, cancelled: cancelled)

            // Limpiar Dock — SSE-04
            DockProgressManager.shared.hideProgress()
            DockProgressManager.shared.setBadge(nil)

            // Notificación macOS — D-04 (modo segundo plano)
            let summary = "\(ok) archivo\(ok == 1 ? "" : "s") traducido\(ok == 1 ? "" : "s")"
            NotificationManager.shared.sendTranslationDone(
                filename: summary,
                langs: targetLangStored
            )

            // Descargar y extraer ZIP en background (D-05, D-06, D-08)
            // Pitfall 3: downloadAndExtractZIP se llama en Task.detached para no bloquear MainActor
            guard let jobId = currentJobId else { break }
            let port = serverPort
            Task {
                await downloadAndExtractZIP(jobId: jobId, port: port)
            }

        default:
            break
        }
    }

    // MARK: - Privado: Cancelar job (DELETE)

    /// Envía DELETE /api/translate/batch/jobs/{jobId} para cancelación cooperativa.
    private func sendDelete(jobId: String, port: Int) async {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/translate/batch/jobs/\(jobId)") else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: request)
        // No manejar el resultado — el stream SSE confirma la cancelación vía complete{cancelled:true}
    }

    // MARK: - Privado: Descarga y extracción ZIP

    /// Descarga el ZIP del job y lo extrae (D-05: éxito; D-08: cancelación parcial).
    /// Pitfall 4: llamar solo DESPUÉS de recibir el evento "complete" del stream SSE.
    private func downloadAndExtractZIP(jobId: String, port: Int) async {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/translate/batch/jobs/\(jobId)/download") else { return }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // 409 = job aún en curso (no debería ocurrir aquí — pitfall 4 prevenido)
                return
            }
            // Extraer .md en background — Pitfall 3: waitUntilExit bloquea el hilo
            try await extractMarkdownFiles(zipData: data)
        } catch {
            // Error de red descargando ZIP — no crítico; los archivos pueden estar en el servidor
        }
    }

    /// Escribe el ZIP a un archivo temporal y extrae solo los .md con /usr/bin/unzip.
    /// D-06: el flag "*.md" en unzip excluye *.validation.json y errors.json.
    /// D-07: el flag -o sobreescribe sin preguntar.
    /// T-18-03: el flag -j (junk paths) previene zip slip (elimina estructura de directorios del ZIP).
    /// Pitfall 3: se llama desde Task.detached — waitUntilExit no bloquea el MainActor.
    /// Pitfall 7: startAccessingSecurityScopedResource activo durante todo el run del Process.
    private func extractMarkdownFiles(zipData: Data) async throws {
        // Obtener carpeta destino en el MainActor — resolvedOutputFolder() es la API pública
        let folder: URL = await MainActor.run {
            OutputManager.shared.resolvedOutputFolder() ?? downloadsFolder()
        }

        // Escribir ZIP en directorio temporal — se elimina al salir (defer)
        let tmpZip = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("batch-\(UUID().uuidString).zip")
        try zipData.write(to: tmpZip, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmpZip) }

        // Pitfall 7: activar acceso security-scoped ANTES de p.run()
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }

        // Pitfall 3: Task.detached para que waitUntilExit no bloquee el MainActor
        try await Task.detached {
            let p = Process()
            // p.executableURL, no p.launchPath (deprecated) — pitfall de CLAUDE.md
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            // Heredar entorno del proceso padre (pitfall 1 — nunca reemplazar completamente)
            var env = ProcessInfo.processInfo.environment
            p.environment = env
            // -o: overwrite (D-07)
            // -j: junk paths / T-18-03: previene zip slip
            // *.md: D-06 — solo archivos .md, excluye *.validation.json y errors.json
            // -d: carpeta destino
            p.arguments = ["-o", "-j", tmpZip.path, "*.md", "-d", folder.path]
            // p.run(), no p.launch() (deprecated) — pitfall de CLAUDE.md
            try p.run()
            p.waitUntilExit()
            // terminationStatus 11 = no hay archivos .md en el ZIP (lote cancelado inmediatamente)
            // No es error fatal — no propagar
        }.value
    }

    // MARK: - Helpers privados

    /// URL de la carpeta Descargas del usuario (fallback cuando OutputManager no tiene carpeta configurada).
    private func downloadsFolder() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}
