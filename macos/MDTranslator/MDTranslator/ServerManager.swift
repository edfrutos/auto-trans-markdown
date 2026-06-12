// ServerManager.swift — Ciclo de vida del subprocess uvicorn embebido.
// Responsabilidades: puerto libre (BSD sockets), arranque del proceso Python,
// health check HTTP, shutdown graceful (SIGINT→SIGKILL) y limpieza de huérfanos.
import Foundation
import Darwin
import AppKit
import Observation

@MainActor
@Observable
class ServerManager {

    enum State {
        case idle, starting, running, failed
    }

    private(set) var state: State = .idle
    private var process: Process?
    private(set) var serverPort: Int = 0
    private let pidFilePath = "/tmp/md-translator-python.pid"

    init() {
        // Limpieza de procesos huérfanos (Pitfall 4: Force Quit no llama applicationWillTerminate).
        // Si existe un PID guardado de una sesión anterior, matar el proceso si sigue corriendo.
        if let pidString = try? String(contentsOfFile: pidFilePath, encoding: .utf8),
           let pid = Int(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let pidT = pid_t(pid)
            if kill(pidT, 0) == 0 {
                // El proceso existe — eliminarlo
                kill(pidT, SIGKILL)
            }
        }
        try? FileManager.default.removeItem(atPath: pidFilePath)

        // Arrancar el servidor inmediatamente para que esté listo si pbs lanza la app
        // en segundo plano (sin ventana) para atender un servicio del sistema (SERVICES-01).
        // SplashView.task también llama a start(); la guardia "state == .idle || .failed"
        // lo convierte en no-op si el servidor ya está arrancando o corriendo.
        Task { [weak self] in
            await self?.start()
        }
    }

    // MARK: - Puerto libre

    /// Solicita al kernel un puerto TCP libre en loopback vía BSD sockets.
    /// Retorna 0 en caso de error (el llamador debe tratar 0 como fallo).
    func findFreePort() -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return 0 }
        defer { Darwin.close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        // INADDR_LOOPBACK.bigEndian convierte host→network byte order en Apple Silicon (little-endian).
        addr.sin_addr.s_addr = in_addr_t(INADDR_LOOPBACK).bigEndian
        addr.sin_port = 0 // El kernel asignará el puerto

        let bindResult = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return 0 }

        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(sock, sockPtr, &addrLen)
            }
        }
        guard nameResult == 0 else { return 0 }

        return Int(CFSwapInt16BigToHost(boundAddr.sin_port))
    }

    // MARK: - Arranque

    func start() async {
        guard state == .idle || state == .failed else { return }
        state = .starting

        let port = findFreePort()
        guard port != 0 else {
            state = .failed
            return
        }
        serverPort = port

        guard let pythonURL = Bundle.main.resourceURL?.appendingPathComponent("python/bin/python3"),
              let backendURL = Bundle.main.resourceURL?.appendingPathComponent("backend") else {
            state = .failed
            return
        }

        let p = Process()
        // p.executableURL (no p.launchPath — obsoleto)
        p.executableURL = pythonURL
        // --host 127.0.0.1 como argumento CLI explícito (Pitfall 3: no confiar solo en env var HOST).
        // PERF-03: --log-level warning elimina mensajes INFO de uvicorn en startup,
        // reduciendo I/O y tiempo hasta que la app está lista.
        p.arguments = [
            "-m", "uvicorn", "src.main:app",
            "--port", "\(port)",
            "--host", "127.0.0.1",
            "--no-access-log",
            "--log-level", "warning"
        ]
        // currentDirectoryURL = backend/ para que src/main.py resuelva rutas relativas correctamente.
        p.currentDirectoryURL = backendURL
        // Hereda el entorno del proceso padre (incluye HOME, TMPDIR, PATH, USER…)
        // y sobreescribe solo las variables específicas del servidor.
        // Reemplazar el entorno completamente privaba a Python de HOME/TMPDIR
        // y causaba que subprocesos shell fallasen con "getcwd: no such directory".
        var env = ProcessInfo.processInfo.environment
        env["HOST"] = "127.0.0.1"
        env["PORT"] = "\(port)"
        // PYTHONDONTWRITEBYTECODE: evita PermissionError al escribir .pyc en /Applications (Pitfall 2).
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        // Inyectar API keys desde el Keychain macOS.
        // NUNCA incluirlas en p.arguments ni en los logs del servidor.
        if let openAIKey = KeychainManager.load(account: KeychainManager.openAIKeyAccount) {
            env["OPENAI_API_KEY"] = openAIKey
        }
        if let deepLKey = KeychainManager.load(account: KeychainManager.deepLKeyAccount) {
            env["DEEPL_API_KEY"] = deepLKey
        }
        if let provider = KeychainManager.load(account: KeychainManager.providerAccount) {
            env["TRANSLATION_PROVIDER"] = provider
        }
        p.environment = env

        // terminationHandler DEBE usar Task { @MainActor [weak self] in } para Swift 6 (Pitfall 5).
        // El bloque de terminationHandler corre en un hilo background de Foundation.
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                // Solo marcar como fallido si todavía estaba .running (proceso muerto inesperadamente).
                // Si stop() ya lo puso en .idle o .starting (restart voluntario), no sobreescribir.
                if self?.state == .running { self?.state = .failed }
            }
        }

        // DEBUG: redirigir stdout+stderr del subprocess a un archivo de log.
        // Eliminar o deshabilitar en producción (Fase 10+).
        let logPath = NSTemporaryDirectory() + "md-translator-server.log"
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
        if let logHandle = FileHandle(forWritingAtPath: logPath) {
            p.standardOutput = logHandle
            p.standardError = logHandle
        }

        do {
            // p.run() (no p.launch() — obsoleto)
            try p.run()
        } catch {
            state = .failed
            return
        }

        // Guardar PID para limpieza en caso de Force Quit (Pitfall 4).
        try? String(p.processIdentifier).write(toFile: pidFilePath, atomically: true, encoding: .utf8)
        process = p

        await waitForHealthCheck(port: port)
    }

    // MARK: - Health check

    private func waitForHealthCheck(port: Int) async {
        let deadline = Date().addingTimeInterval(15)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.0
        let session = URLSession(configuration: config)
        let url = URL(string: "http://127.0.0.1:\(port)/api/languages")!

        while Date() < deadline {
            do {
                let (_, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    state = .running
                    return
                }
            } catch {
                // Servidor aún no listo — reintentar
            }
            // PERF-03: 200 ms en lugar de 500 ms → en promedio 1–2 reintentos menos
            // antes de que el health check pase (~0.3–0.6 s ahorrados).
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        // Timeout: el servidor no respondió en 15 segundos
        stop()
        state = .failed
    }

    // MARK: - Shutdown

    func stop() {
        // Resetear el estado ANTES de matar el proceso para que start() pueda llamarse
        // inmediatamente después sin esperar al terminationHandler (que corre en background).
        state = .idle
        guard let p = process, p.isRunning else {
            process = nil
            return
        }
        // SIGINT primero — uvicorn realiza graceful shutdown.
        p.interrupt()
        // SIGKILL diferido 5 s si el proceso no terminó (p.terminate() = SIGKILL en Foundation).
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if p.isRunning { p.terminate() }
        }
        process = nil
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }
}
