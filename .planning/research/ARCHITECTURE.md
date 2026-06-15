# Architecture Patterns: SwiftUI macOS App + Python FastAPI Subprocess

**Domain:** macOS native app wrapping an embedded Python FastAPI backend
**Researched:** 2026-06-02
**Milestone:** v3.0 macOS Native App
**Confidence:** HIGH para Swift/macOS APIs (docs oficiales + Context7); MEDIUM para python-build-standalone embed (docs parcialmente accesibles); HIGH para patrones FastAPI subprocess (bien establecidos en ecosistema)

---

## Diagrama de Componentes

```text
┌──────────────────────────────────────────────────────────────┐
│  MarkDownTranslator.app (.app bundle)                        │
│                                                              │
│  ┌─────────────────────────┐   ┌──────────────────────────┐  │
│  │  SwiftUI Layer          │   │  Python Backend Layer    │  │
│  │                         │   │                          │  │
│  │  MainWindowView         │   │  Contents/               │  │
│  │  ├─ EditorView          │   │  ├─ MacOS/               │  │
│  │  ├─ FileView            │   │  │  └─ MarkDownTranslator │  │
│  │  ├─ BatchView           │   │  │     (Swift binary)    │  │
│  │  └─ GlossaryView        │   │  ├─ Helpers/             │  │
│  │                         │   │  │  └─ python/           │  │
│  │  MenuBarExtra           │   │  │     ├─ bin/python3.11 │  │
│  │  └─ QuickMenuView       │   │  │     ├─ lib/           │  │
│  │                         │   │  │     └─ lib/site-pkgs/ │  │
│  │  @StateObject           │   │  └─ Resources/           │  │
│  │  ServerManager          │   │     └─ backend/          │  │
│  │  └─ Foundation.Process  │   │        └─ src/           │  │
│  │                         │   │           ├─ main.py     │  │
│  │  APIClient              │   │           ├─ parser.py   │  │
│  │  └─ URLSession          │   │           ├─ pipeline.py │  │
│  │     async/await         │   │           └─ ...         │  │
│  └────────────┬────────────┘   └──────────────────────────┘  │
│               │  HTTP 127.0.0.1:PORT (loopback)   ↑          │
│               └──────────────────────────────────-┘          │
└──────────────────────────────────────────────────────────────┘
```

---

## 1. Gestión del Ciclo de Vida del Proceso Python

### Clase Swift: `ServerManager`

`ServerManager` es el único dueño del `Foundation.Process`. Es un `@MainActor ObservableObject` consumible como `@StateObject` / `@EnvironmentObject` en toda la app.

```swift
import Foundation

@MainActor
final class ServerManager: ObservableObject {

    enum State {
        case stopped
        case starting
        case ready(port: UInt16)
        case failed(Error)
    }

    @Published private(set) var state: State = .stopped

    private var process: Process?
    private var allocatedPort: UInt16 = 0

    func start() async {
        guard case .stopped = state else { return }
        state = .starting
        do {
            allocatedPort = try allocateFreePort()
            let p = try buildProcess(port: allocatedPort)
            process = p
            try p.run()
            // Esperar hasta que FastAPI responda antes de mostrar la UI
            try await waitUntilReady(port: allocatedPort, timeout: 15)
            state = .ready(port: allocatedPort)
        } catch {
            state = .failed(error)
        }
    }

    func stop() {
        guard let p = process, p.isRunning else {
            state = .stopped
            return
        }
        p.terminate()                        // SIGTERM — uvicorn graceful shutdown
        DispatchQueue.global().async {
            p.waitUntilExit()               // NO bloquear el main thread
        }
        process = nil
        state = .stopped
    }
}
```

**API de `Foundation.Process` verificada:**

| Propiedad/Método                           | Uso                                                                             |
| ------------------------------------------ | ------------------------------------------------------------------------------- |
| `executableURL: URL?`                      | Ruta al binario Python en `Contents/Helpers/python/bin/python3.11`              |
| `arguments: [String]?`                     | `["-m", "uvicorn", "src.main:app", "--host", "127.0.0.1", "--port", "\(port)"]` |
| `environment: [String: String]?`           | Entorno mínimo construido explícitamente — no heredar el del sistema            |
| `currentDirectoryURL: URL?`                | Directorio `Resources/backend/` dentro del bundle                               |
| `standardError: Any?`                      | `Pipe()` para capturar logs de uvicorn                                          |
| `terminationHandler: ((Process) -> Void)?` | Detectar crashes inesperados y actualizar `state`                               |
| `isRunning: Bool`                          | Check antes de `terminate()`                                                    |
| `terminationStatus: Int32`                 | Código de salida tras terminar                                                  |
| `try p.run()`                              | Lanza el proceso sin bloquear                                                   |
| `p.terminate()`                            | Envía SIGTERM                                                                   |
| `p.waitUntilExit()`                        | Bloquea hasta que el proceso muera — usar en background thread                  |

### `buildProcess(port:)` — configuración completa

```swift
private func buildProcess(port: UInt16) throws -> Process {
    let bundle = Bundle.main

    // Intérprete Python standalone dentro del bundle
    guard let pythonURL = bundle.url(
        forResource: "python3.11",
        withExtension: nil,
        subdirectory: "Helpers/python/bin"
    ) else {
        throw ServerError.pythonNotFound
    }

    // Directorio raíz del backend (contiene src/)
    guard let backendURL = bundle.url(
        forResource: "src",
        withExtension: nil,
        subdirectory: "Resources/backend"
    )?.deletingLastPathComponent() else {
        throw ServerError.backendNotFound
    }

    // Datos mutables en Application Support (NO en Resources — read-only en bundle firmado)
    let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first!.appendingPathComponent("MarkDownTranslator")
    try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

    let p = Process()
    p.executableURL = pythonURL
    p.arguments = [
        "-m", "uvicorn",
        "src.main:app",
        "--host", "127.0.0.1",
        "--port", String(port),
        "--no-access-log"
    ]
    p.currentDirectoryURL = backendURL

    // Entorno mínimo y explícito — no heredar variables del shell del usuario
    var env: [String: String] = [:]
    let pythonBin = pythonURL.deletingLastPathComponent().path
    env["PATH"]              = "\(pythonBin):/usr/bin:/bin"
    env["PYTHONPATH"]        = backendURL.path
    env["PYTHONUNBUFFERED"]  = "1"    // logs inmediatos sin buffer
    env["OUTPUT_DIR"]        = appSupport.appendingPathComponent("output").path

    // Inyectar API keys desde Keychain — no leer .env en el bundle
    if let openAIKey = KeychainHelper.read(service: "openai-api-key") {
        env["OPENAI_API_KEY"] = openAIKey
    }
    if let deepLKey = KeychainHelper.read(service: "deepl-api-key") {
        env["DEEPL_API_KEY"] = deepLKey
    }
    env["TRANSLATION_PROVIDER"] = UserDefaults.standard.string(
        forKey: "translationProvider"
    ) ?? "openai"

    p.environment = env

    // Capturar stderr para logging en consola de la app
    let errPipe = Pipe()
    p.standardError = errPipe
    p.standardOutput = Pipe()   // descartar stdout de uvicorn (verbose por defecto)

    // Detectar crash del proceso Python y propagar al estado de la app
    p.terminationHandler = { [weak self] proc in
        Task { @MainActor [weak self] in
            guard let self else { return }
            if proc.terminationStatus != 0 {
                self.state = .failed(
                    ServerError.unexpectedExit(code: Int(proc.terminationStatus))
                )
            }
        }
    }

    return p
}
```

---

## 2. Encontrar un Puerto Libre

El método recomendado es bind a puerto 0: el kernel asigna el siguiente disponible. Se cierra el socket inmediatamente y se pasa el número al subprocess.

```swift
import Darwin

func allocateFreePort() throws -> UInt16 {
    var addr = sockaddr_in()
    addr.sin_family    = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK)   // solo 127.0.0.1
    addr.sin_port      = 0                            // pedir asignación dinámica

    let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else {
        throw ServerError.socketFailed(errno: errno)
    }
    defer { Darwin.close(sock) }

    let bindResult = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        throw ServerError.bindFailed(errno: errno)
    }

    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.getsockname(sock, $0, &len)
        }
    }

    return UInt16(bigEndian: addr.sin_port)
}
```

**Por qué puerto dinámico en lugar de fijo:**

- Un puerto fijo (8000) colisiona con la instancia web/CLI del mismo proyecto si el usuario la tiene corriendo.
- Múltiples instancias de la app (reinicios rápidos) no colisionan.
- La race condition teórica entre `close()` y el `bind()` de uvicorn es negligible en loopback local.

---

## 3. Estructura del Bundle y Xcode

### Layout del .app

```text
MarkDownTranslator.app/
└── Contents/
    ├── MacOS/
    │   └── MarkDownTranslator          # binario Swift (firmado)
    ├── Helpers/
    │   └── python/                     # python-build-standalone descomprimido
    │       ├── bin/
    │       │   └── python3.11          # ejecutable Python
    │       ├── lib/
    │       │   └── python3.11/         # stdlib completa
    │       └── lib/python3.11/site-packages/
    │           ├── fastapi/            # deps pre-instaladas en build time
    │           ├── uvicorn/
    │           ├── openai/
    │           ├── deepl/
    │           └── ...
    ├── Resources/
    │   └── backend/                    # código Python del proyecto (read-only)
    │       └── src/
    │           ├── main.py
    │           ├── parser.py
    │           ├── translator.py
    │           ├── pipeline.py
    │           ├── glossary.py
    │           ├── memory.py
    │           └── translation_memory.py
    └── Info.plist
```

**Datos mutables → Application Support (nunca en Resources)**

`Resources/` es read-only en un bundle firmado. Todo lo que cambia en runtime va a:
```text
~/Library/Application Support/MarkDownTranslator/
├── output/          # archivos .md traducidos temporales
├── translation_memory.db  # SQLite TM
└── glossary.yaml    # glosario del usuario (editable en la app)
```

### Xcode Build Phases para incluir el backend Python

**Build Phase 1 — Run Script: preparar python-build-standalone**

```bash
# scripts/build-python-bundle.sh
set -e
PYTHON_VERSION="3.11.9"
ARCH=$(uname -m)  # arm64 o x86_64
DIST_DIR="$SRCROOT/python-dist"

if [ ! -d "$DIST_DIR" ]; then
    TARBALL="cpython-${PYTHON_VERSION}+...-${ARCH}-apple-darwin-install_only.tar.gz"
    curl -L "https://github.com/indygreg/python-build-standalone/releases/download/.../$TARBALL" \
        -o /tmp/python-standalone.tar.gz
    mkdir -p "$DIST_DIR"
    tar -xf /tmp/python-standalone.tar.gz -C "$DIST_DIR" --strip-components=1

    # Instalar dependencias Python en site-packages del bundle
    "$DIST_DIR/bin/python3.11" -m pip install --no-user \
        fastapi "uvicorn[standard]" openai deepl \
        python-dotenv python-multipart pyyaml \
        -q
fi
```

**Build Phase 2 — Copy Files: `python-dist/` → `Contents/Helpers/python/`**

- Destination: `Wrapper/Contents/Helpers/python/`
- Arrastrar directorio `python-dist/` en Xcode

**Build Phase 3 — Copy Files: `src/` → `Contents/Resources/backend/src/`**

- Destination: `Resources/backend/`
- Arrastrar carpeta `src/`
- Desmarcar "Copy only when installing" para que siempre se copie

### python-build-standalone — fuente y distribución

- Releases: `https://github.com/indygreg/python-build-standalone/releases`
- Usar build `install_only` (sin símbolos de debug): reduce tamaño de ~200MB a ~50MB.
- Targets disponibles:
  - `cpython-3.11.X-aarch64-apple-darwin-install_only.tar.gz` (Apple Silicon)
  - `cpython-3.11.X-x86_64-apple-darwin-install_only.tar.gz` (Intel)
- Para Universal Binary: compilar dos archs y combinar con `lipo` (complejo; diferir para v3.1).
- Las dependencias Python se instalan **en tiempo de build**, no en tiempo de ejecución. Sin PyPI en runtime.

---

## 4. Health Check — esperar que el servidor esté listo

FastAPI + uvicorn tarda ~1-3 segundos en arrancar. La UI solo se muestra cuando el servidor responde correctamente.

```swift
private func waitUntilReady(port: UInt16, timeout: TimeInterval) async throws {
    // Usar /api/languages ya existente como endpoint de health
    let url = URL(string: "http://127.0.0.1:\(port)/api/languages")!
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return   // servidor listo
            }
        } catch {
            // ConnectionRefused mientras uvicorn arranca — ignorar y reintentar
        }
        try await Task.sleep(nanoseconds: 250_000_000)   // 250ms entre intentos
    }

    throw ServerError.startupTimeout
}
```

**Por qué `GET /api/languages` como health check:**

- Ya existe en la API FastAPI actual — cero cambios en el backend.
- Responde 200 solo cuando la app está completamente inicializada (imports, dotenv, clientes providers).
- Alternativa a largo plazo: añadir `GET /health → {"status":"ok"}` en `src/main.py` (trivial con FastAPI, cero lógica extra).

**Patrón de UI durante startup:**

```swift
@main
struct MarkDownTranslatorApp: App {
    @StateObject private var server = ServerManager()
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Group {
                switch server.state {
                case .stopped, .starting:
                    SplashView(state: server.state)
                case .ready(let port):
                    ContentView()
                        .environmentObject(APIClient(port: port))
                case .failed(let error):
                    ErrorView(error: error, onRetry: { Task { await server.start() } })
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { server.stop() }
        }

        MenuBarExtra("MD Translate", systemImage: "doc.text.magnifyingglass") {
            QuickMenuView()
                .environmentObject(server)
        }
    }
}
```

---

## 5. Comunicación Swift ↔ FastAPI

### `APIClient` — URLSession async/await

```swift
import Foundation

final class APIClient: ObservableObject {
    let baseURL: URL

    init(port: UInt16) {
        baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    // Modo Editor — traducción de texto
    func translateText(
        content: String,
        targetLang: String,
        sourceLang: String = "auto"
    ) async throws -> TranslateResponse {
        var req = URLRequest(url: baseURL.appending(path: "/api/translate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            TranslateTextRequest(content: content, target_lang: targetLang, source_lang: sourceLang)
        )
        let (data, response) = try await URLSession.shared.data(for: req)
        try assertHTTP200(response)
        return try JSONDecoder().decode(TranslateResponse.self, from: data)
    }

    // Modo Archivo — subir .md, recibir .md traducido
    func translateFile(fileURL: URL, targetLang: String) async throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        let boundary = UUID().uuidString

        var req = URLRequest(url: baseURL.appending(path: "/api/translate/file"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = buildMultipart(
            fields: ["target_lang": targetLang],
            fileData: fileData,
            fileName: fileURL.lastPathComponent,
            boundary: boundary
        )
        let (data, response) = try await URLSession.shared.data(for: req)
        try assertHTTP200(response)
        return data
    }

    // Modo Batch — múltiples .md, recibir ZIP
    func translateBatch(fileURLs: [URL], targetLang: String) async throws -> Data {
        let boundary = UUID().uuidString
        var req = URLRequest(url: baseURL.appending(path: "/api/translate/batch"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = try buildBatchMultipart(fileURLs: fileURLs, targetLang: targetLang, boundary: boundary)
        let (data, response) = try await URLSession.shared.data(for: req)
        try assertHTTP200(response)
        return data   // ZIP con archivos traducidos
    }

    // Idiomas disponibles (también sirve como health check)
    func fetchLanguages() async throws -> [LanguageItem] {
        let (data, response) = try await URLSession.shared.data(
            from: baseURL.appending(path: "/api/languages")
        )
        try assertHTTP200(response)
        return try JSONDecoder().decode([LanguageItem].self, from: data)
    }

    private func assertHTTP200(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: code)
        }
    }
}
```

### Modelos Codable — espejos de los modelos Pydantic existentes

```swift
// Espejo de TranslateTextRequest en src/main.py
struct TranslateTextRequest: Encodable {
    let content: String
    let target_lang: String
    let source_lang: String
}

// Espejo de TranslateResponse en src/main.py
struct TranslateResponse: Decodable {
    let translated: String
    let provider: String
    let target_lang: String
}

// Espejo de LanguageItem en src/main.py
struct LanguageItem: Decodable {
    let code: String
    let name: String
}

enum APIError: Error {
    case httpError(statusCode: Int)
    case decodingFailed
}

enum ServerError: Error {
    case pythonNotFound
    case backendNotFound
    case startupTimeout
    case socketFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case unexpectedExit(code: Int)
}
```

### Info.plist — permitir HTTP a loopback

App Transport Security bloquea HTTP incluso a localhost por defecto en macOS:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <false/>
        </dict>
        <key>127.0.0.1</key>
        <dict>
            <key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <false/>
        </dict>
    </dict>
</dict>
```

---

## 6. Estructura del Repositorio — dónde va el código Swift

```text
auto-trans-markdown/               # raíz del repo existente
├── src/                           # Python backend (existente — sin cambios)
├── static/                        # Web UI (existente)
├── tests/                         # Python tests (existente)
├── data/                          # SQLite TM, gitignored (existente)
├── scripts/
│   └── build-python-bundle.sh     # NUEVO — prepara python-build-standalone
├── macos/                         # NUEVO — todo lo Swift
│   ├── MarkDownTranslator.xcodeproj/
│   └── MarkDownTranslator/
│       ├── App/
│       │   ├── MarkDownTranslatorApp.swift   # @main, ServerManager init
│       │   └── AppDelegate.swift             # applicationWillTerminate
│       ├── Managers/
│       │   ├── ServerManager.swift           # Foundation.Process lifecycle
│       │   ├── APIClient.swift               # URLSession async/await
│       │   └── KeychainHelper.swift          # SecItemAdd / SecItemCopyMatching
│       ├── Views/
│       │   ├── MainWindowView.swift          # NavigationSplitView
│       │   ├── SplashView.swift              # estado startup/error
│       │   ├── EditorView.swift              # modo editor
│       │   ├── FileView.swift                # modo archivo + drop
│       │   ├── BatchView.swift               # modo batch + notificaciones
│       │   ├── GlossaryView.swift            # ver/editar glossary.yaml
│       │   └── QuickMenuView.swift           # MenuBarExtra popup
│       ├── Models/
│       │   └── APIModels.swift               # structs Codable espejo de Pydantic
│       └── Resources/
│           └── Info.plist
├── pyproject.toml
└── requirements.txt
```

**Rationale de `macos/` como directorio separado:**

- `pytest` y herramientas Python no incluyen accidentalmente `.swift` o `xcodeproj`.
- El proyecto Xcode puede referenciar `../src/` con rutas relativas para Copy Files Build Phase.
- CI puede separar el build Swift del lint Python con paths distintos.

---

## 7. Apagado Limpio del Proceso Python

### Señales de terminación

```text
Swift llama server.stop()
    └─ process.terminate()      → SIGTERM a Python
           └─ uvicorn recibe SIGTERM
                  └─ graceful shutdown: termina conexiones activas,
                     cierra sockets, libera SQLite WAL
                  └─ process exits con status 0
    └─ DispatchQueue.global(): process.waitUntilExit()
    └─ process = nil, state = .stopped
```

### Manejador de terminación con timeout de seguridad

```swift
func stop() {
    guard let p = process, p.isRunning else {
        process = nil
        state = .stopped
        return
    }

    p.terminate()   // SIGTERM — uvicorn hace graceful shutdown

    // Esperar en background thread (waitUntilExit bloquea)
    DispatchQueue.global(qos: .utility).async {
        let semaphore = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in semaphore.signal() }

        let result = semaphore.wait(timeout: .now() + .seconds(5))
        if result == .timedOut && p.isRunning {
            // SIGTERM ignorado — escalar a SIGKILL
            kill(p.processIdentifier, SIGKILL)
        }
    }

    process = nil
    state = .stopped
}
```

### Integraciones del ciclo de vida de la app

**`ScenePhase.background`** — cuando el usuario cierra todas las ventanas (sin menubar):

```swift
.onChange(of: scenePhase) { phase in
    if phase == .background { server.stop() }
}
```

**`applicationWillTerminate`** — Cmd+Q, Force Quit, cierre desde Dock:

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    var server: ServerManager?

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        // waitUntilExit aquí es síncrono pero el OS da ~2s antes de kill forzado
    }

    // La app NO termina al cerrar la ventana principal si hay MenuBarExtra
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
```

**Conexión AppDelegate ↔ ServerManager en SwiftUI:**

```swift
@main
struct MarkDownTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var server = ServerManager()

    init() {
        // No se puede usar @StateObject en init — pasar vía post-init
        // Alternativa: usar Notification o dependency injection manual
    }
}
```

La forma más limpia es que `AppDelegate` cree y posea su propia referencia a `ServerManager`, y la app la exponga como `@EnvironmentObject`. Alternativamente, usar `NotificationCenter.default.post(name: .appWillTerminate, ...)` que `ServerManager` observa.

---

## 8. Data Flow por Modo

### Modo Editor

```text
TextEditor (SwiftUI) — usuario escribe Markdown
    ↓ toca botón "Traducir"
APIClient.translateText(content:targetLang:)
    ↓ POST /api/translate
    ↓ JSON {"content":..., "target_lang":...}
FastAPI → pipeline.translate_markdown()
    ↓ JSON {"translated":..., "provider":..., "target_lang":...}
EditorView: muestra resultado en panel derecho (TextEditor read-only)
```

**Consideraciones Swift:**

- `TextEditor` nativo para entrada y salida.
- Deshabilitar botón durante la llamada (`@State var isTranslating = false`).
- Debounce no necesario — el usuario decide cuándo traducir (botón explícito).

### Modo Archivo

```text
Botón "Abrir archivo" o zona drop
    ↓ fileImporter(allowedContentTypes: [.init(filenameExtension: "md")!])
    ↓  o  dropDestination(for: URL.self)
file.startAccessingSecurityScopedResource()  ← OBLIGATORIO en sandbox
    ↓ leer Data(contentsOf: url)
APIClient.translateFile(fileURL:targetLang:)
    ↓ POST /api/translate/file  multipart/form-data
FastAPI → pipeline → FileResponse (.md)
    ↓ Data recibida
file.stopAccessingSecurityScopedResource()
NSSavePanel → guardar .md traducido en destino elegido por el usuario
```

**Consideraciones Swift:**

- `fileImporter` modifier en SwiftUI — `allowsMultipleSelection: false` para este modo.
- Security-scoped resource: obligatorio cuando sandbox está activo. Sin él, la lectura del archivo devuelve "permission denied".
- El archivo de salida se guarda con `NSSavePanel` para respetar sandbox y las preferencias de ubicación del usuario.

### Modo Batch

```text
fileImporter(allowsMultipleSelection: true)
    ↓ [URL] de archivos .md seleccionados
Por cada file: startAccessingSecurityScopedResource()
APIClient.translateBatch(fileURLs:targetLang:)
    ↓ POST /api/translate/batch  multipart/form-data (N archivos)
FastAPI → loop pipeline × N → ZIP en memoria → StreamingResponse
    ↓ Data (ZIP)
Por cada file: stopAccessingSecurityScopedResource()
NSSavePanel → guardar .zip
UNUserNotificationCenter: notificación local "Lote completado (N archivos)"
```

**Consideraciones Swift:**

- `fileImporter(allowsMultipleSelection: true)` — `[URL]` en el closure `.success`.
- Progreso: la API backend soporta SSE (job endpoint). En v3.0 usar `ProgressView` indeterminado. Para v3.1: `URLSession.bytes(for:)` para consumir SSE.
- Notificación local requiere `requestAuthorization` en el primer arranque.

---

## 9. Keychain — API Keys sin `.env`

El proceso Python no tiene `.env` en el bundle. Las claves se inyectan como variables de entorno al lanzar el proceso.

```swift
import Security

enum KeychainHelper {
    static func write(service: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "app-user",
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)   // borrar existente antes de añadir
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(service: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  "app-user",
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

**Compatibilidad con `src/main.py`:** `load_dotenv()` en el backend no lanza error si no hay `.env`. Las variables de entorno inyectadas por Swift están disponibles vía `os.getenv()` igual que si viniera de `.env`. No requiere modificar el backend.

---

## 10. Sandbox y Entitlements

### v3.0 — Distribución ad-hoc (sin Apple Developer Account)

Sin sandbox. La firma ad-hoc no impone restricciones:

```bash
# Firma ad-hoc
codesign --force --deep --sign - MarkDownTranslator.app
# El usuario puede bypassar Gatekeeper en macOS con:
# xattr -dr com.apple.quarantine MarkDownTranslator.app
```

Con firma ad-hoc:

- `Foundation.Process` puede lanzar cualquier ejecutable sin restricciones.
- No hay entitlements requeridos para el subprocess.
- Acceso libre al filesystem (sin scoping).

### Entitlements mínimos necesarios aun sin sandbox

```xml
<!-- MarkDownTranslator.entitlements -->
<dict>
    <!-- Requerido para URLSession a localhost -->
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
```

### Para distribución futura por Mac App Store (sandbox requerido)

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>   <!-- para fileImporter -->
```

El subprocess Python en `Contents/Helpers/python/` necesita un entitlements file separado con `com.apple.security.inherit` para heredar el sandbox del padre. Esto es una restricción para v3.x si se apunta al MAS; en v3.0 no aplica.

---

## 11. MenuBarExtra y Notificaciones

### MenuBarExtra (macOS 13+)

```swift
MenuBarExtra("MD Translate", systemImage: "doc.text.magnifyingglass") {
    QuickMenuView()
        .environmentObject(server)
}
.menuBarExtraStyle(.window)   // popover con UI SwiftUI completa
```

Requiere macOS 13 Ventura o posterior — compatible con el target macOS 14+ del proyecto.

### Notificaciones locales al completar batch

```swift
import UserNotifications

func notifyBatchComplete(fileCount: Int) {
    let center = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    content.title = "Traducción completada"
    content.body  = "\(fileCount) archivo\(fileCount == 1 ? "" : "s") traducido\(fileCount == 1 ? "" : "s") correctamente."
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil    // nil = enviar inmediatamente
    )
    center.add(request)
}

// Solicitar autorización al primer arranque (en @main init o onAppear)
func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .sound]
    ) { granted, _ in
        // guardar preferencia si es necesario
    }
}
```

---

## 12. Sparkle — Auto-Update

```swift
// En @main App struct
import Sparkle

private let updaterController: SPUStandardUpdaterController

init() {
    updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
}

// En el menú Commands:
CommandGroup(after: .appInfo) {
    CheckForUpdatesView(updater: updaterController.updater)
}
```

Sparkle se integra via Swift Package Manager. Requiere un `appcast.xml` público para las actualizaciones. Para v3.0 ad-hoc, puede diferirse — añadir el framework vacío no rompe nada.

---

## 13. Patrones a Seguir

### ServerManager como single source of truth del backend

Todos los views obtienen el puerto vía `@EnvironmentObject var server: ServerManager`. Nunca hardcodear el puerto ni pasarlo como `Int` por el árbol de vistas. `APIClient` se instancia **solo cuando** `state == .ready(port:)`.

### APIClient sin singleton global

Instanciar `APIClient(port:)` cuando el servidor está listo y pasarlo como `@EnvironmentObject`. Si el servidor se reinicia con un puerto diferente, se crea una nueva instancia — el singleton global tendría el puerto desactualizado.

### ViewModels para lógica de traducción

`EditorView`, `FileView`, `BatchView` no llaman a `URLSession` directamente. Cada una tiene su `@StateObject ViewModel` que llama a `APIClient`. Esto permite tests unitarios sin construir vistas SwiftUI.

### No bloquear `@MainActor` con I/O bloqueante

`process.waitUntilExit()` bloquea. Siempre en `DispatchQueue.global()` o `Task.detached`. `URLSession.data(for:)` es async — correcto en `@MainActor`.

---

## 14. Anti-Patrones a Evitar

### No usar WKWebView cargando la UI web existente

Embeber la UI HTML en un `WKWebView` parece el camino fácil pero elimina drag & drop nativo, Keychain, notificaciones y apariencia macOS. La ventaja de v3.0 es la UX nativa.

### No instalar `pip install` en tiempo de ejecución

`pip install` en `ServerManager.start()` requiere red, es lento (~10-30s), puede fallar y crea estado mutable difícil de auditar. Las dependencias van en `Contents/Helpers/python/lib/site-packages/` instaladas en build time.

### No hardcodear el puerto

Un puerto fijo (8000) colisiona con la instancia web del mismo proyecto. Siempre `allocateFreePort()`.

### No heredar el entorno del sistema sin filtrar

`process.environment = ProcessInfo.processInfo.environment` expone `PATH`, `HOME`, tokens de shell y variables de otros proyectos. Construir un entorno mínimo y explícito.

### No crear un proceso Python por request HTTP

Un único proceso uvicorn sirve todos los requests. Crear/destruir procesos por solicitud sería extremadamente lento y costoso.

### No modificar `src/parser.py` ni `src/translator.py` para adaptar a la app macOS

El backend Python ya tiene la arquitectura correcta. La app macOS es un frontend que consume la misma API REST que la web UI. Zero cambios en el pipeline Python para el frontend Swift.

---

## 15. Build Order Recomendado

| Fase   | Entregable                                                  | Dependencias   | Verifica que                                        |
| ------ | ----------------------------------------------------------- | -------------- | --------------------------------------------------- |
| **1**  | `scripts/build-python-bundle.sh` + python-build-standalone  | Ninguna        | Python arranca dentro del bundle                    |
| **2**  | `ServerManager` + `allocateFreePort()`                      | (1)            | `server.start()` llega a `.ready` en tests manuales |
| **3**  | `waitUntilReady` + `SplashView`                             | (2)            | La UI espera correctamente                          |
| **4**  | `APIClient.fetchLanguages()` + `APIClient.translateText()`  | (3)            | Editor traduce texto desde la app                   |
| **5**  | `KeychainHelper` + pantalla de settings                     | (4)            | Claves persisten entre reinicios                    |
| **6**  | `FileView` + `fileImporter` + `APIClient.translateFile()`   | (4)            | Traducción de archivo end-to-end                    |
| **7**  | `BatchView` + `APIClient.translateBatch()` + notificaciones | (4), (6)       | Batch con ZIP descargable                           |
| **8**  | `MenuBarExtra` + `QuickMenuView`                            | (3)            | Icono menubar funcional                             |
| **9**  | `AppDelegate.applicationWillTerminate` + stop con timeout   | (2)            | Cierre limpio en Cmd+Q                              |
| **10** | DMG + firma ad-hoc                                          | Todo           | App ejecutable sin Xcode                            |

---

## Sources

| Fuente                                                                                                                             | Confianza   | Notas                                                                                         |
| ---------------------------------------------------------------------------------------------------------------------------------- | ----------- | --------------------------------------------------------------------------------------------- |
| Swift Foundation Process/Subprocess proposal: `github.com/swiftlang/swift-foundation/blob/main/Proposals/0007-swift-subprocess.md` | HIGH        | Fuente directa swiftlang                                                                      |
| Apple Developer — Foundation Process class (docs oficiales)                                                                        | HIGH        | API estable desde macOS 10.0                                                                  |
| SwiftUI ScenePhase — Context7 `/websites/developer_apple_swiftui`                                                                  | HIGH        | Verificado con ejemplos de código                                                             |
| SwiftUI MenuBarExtra — Context7                                                                                                    | HIGH        | macOS 13+ confirmado                                                                          |
| SwiftUI fileImporter — Context7                                                                                                    | HIGH        | Ejemplo multiselect verificado                                                                |
| SwiftUI dropDestination — Context7                                                                                                 | HIGH        | Protocolo DropDelegate verificado                                                             |
| URLSession async/await — docs oficiales                                                                                            | HIGH        | Swift 5.5+, `data(from:)` y `data(for:)`                                                      |
| NSAppTransportSecurity localhost — docs oficiales                                                                                  | HIGH        | Config XML verificada                                                                         |
| Keychain Services SecItemAdd/Copy — docs oficiales                                                                                 | HIGH        | Patrón estándar                                                                               |
| UNUserNotificationCenter — docs oficiales                                                                                          | HIGH        | Patrón standard macOS                                                                         |
| Sparkle SPM integration — Context7 `/websites/sparkle-project`                                                                     | HIGH        | Ejemplo SPUStandardUpdaterController verificado                                               |
| python-build-standalone releases — `github.com/indygreg/python-build-standalone`                                                   | MEDIUM      | Docs running.html no accesibles; releases públicos verificados                                |
| Xcode helper tool embedding — docs Apple parciales                                                                                 | MEDIUM      | Contenido parcialmente recuperado; patrón `Contents/Helpers/` verificado en múltiples fuentes |
| BSD sockets `bind(port:0)` para puerto libre                                                                                       | HIGH        | Patrón estándar POSIX, independiente del docs Apple                                           |

---

*Architecture research para milestone v3.0 (macOS Native App) — 2026-06-02*
