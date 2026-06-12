# Phase 18: SSE Batch Nativo — Pattern Map

**Mapeado:** 2026-06-12
**Archivos analizados:** 5 (2 nuevos + 3 modificados)
**Analogs encontrados:** 5 / 5

---

## File Classification

| Archivo nuevo/modificado | Rol | Data Flow | Analog más cercano | Calidad |
|--------------------------|-----|-----------|--------------------|---------|
| `BatchJobManager.swift` (nuevo) | manager / singleton | event-driven + request-response | `ServerManager.swift` | exact |
| `BatchSheet.swift` (nuevo) | view / SwiftUI sheet | event-driven (observa manager) | `SettingsView.swift` + `SplashView.swift` | role-match |
| `AppDelegate.swift` (mod.) | app delegate | request-response | `AppDelegate.swift` mismo | self |
| `Commands.swift` (mod.) | commands / menu | request-response | `Commands.swift` mismo | self |
| `MDTranslatorApp.swift` (mod.) | app entry point / sheet bridge | event-driven | `MDTranslatorApp.swift` mismo | self |

---

## Pattern Assignments

### `BatchJobManager.swift` (manager, event-driven)

**Analog principal:** `macos/MDTranslator/MDTranslator/ServerManager.swift`

**Imports pattern** (ServerManager.swift líneas 1–8):
```swift
// ServerManager.swift — Ciclo de vida del subprocess uvicorn embebido.
import Foundation
import Darwin
import AppKit
import Observation
```
Para BatchJobManager usar:
```swift
// BatchJobManager.swift — Cliente SSE del jobs API y estado del lote.
import Foundation
import AppKit
import Observation
```

**Declaración de clase y enum de estado** (ServerManager.swift líneas 9–19):
```swift
@MainActor
@Observable
class ServerManager {

    enum State {
        case idle, starting, running, failed
    }

    private(set) var state: State = .idle
    private var process: Process?
    private(set) var serverPort: Int = 0
```
Adaptar para BatchJobManager:
```swift
@MainActor
@Observable
final class BatchJobManager {
    static let shared = BatchJobManager()

    enum JobState {
        case idle
        case prepared(urls: [URL])
        case running(jobId: String)
        case cancelling
        case done(ok: Int, errors: [(String, String)], cancelled: Bool)
    }

    private(set) var jobState: JobState = .idle
    private var streamTask: Task<Void, Never>?
    // Progreso — actualizados por eventos SSE desde handleSSELine()
    private(set) var currentFile: String = ""
    private(set) var filesDone: Int      = 0
    private(set) var filesTotal: Int     = 0
    private(set) var segmentsDone: Int   = 0
    private(set) var segmentsTotal: Int  = 0
    private var errorMessages: [(String, String)] = []

    var isRunning: Bool {
        if case .running = jobState { return true }
        if case .cancelling = jobState { return true }
        return false
    }
    var completedCount: Int { filesDone }
    var totalCount: Int { filesTotal }
```

**Patrón de Task async con guard de estado** (ServerManager.swift líneas 80–82):
```swift
func start() async {
    guard state == .idle || state == .failed else { return }
    state = .starting
```
Adaptar:
```swift
func start(port: Int) async {
    guard case .prepared(let urls) = jobState else { return }
    // ... cambiar estado a .running tras recibir job_id
```

**Patrón de herencia de entorno en Process** (ServerManager.swift líneas 116–133):
```swift
var env = ProcessInfo.processInfo.environment
env["HOST"] = "127.0.0.1"
env["PORT"] = "\(port)"
env["PYTHONDONTWRITEBYTECODE"] = "1"
env["PYTHONUNBUFFERED"] = "1"
// ...
p.environment = env
```
Aplicar al `Process` de `/usr/bin/unzip` en `extractMarkdownFiles()`:
```swift
// NUNCA reemplazar completamente — heredar y sobreescribir solo lo necesario
var env = ProcessInfo.processInfo.environment
p.environment = env
// No se necesitan vars adicionales para unzip
```

**Patrón terminationHandler con Task @MainActor** (ServerManager.swift líneas 136–143):
```swift
p.terminationHandler = { [weak self] _ in
    Task { @MainActor [weak self] in
        if self?.state == .running { self?.state = .failed }
    }
}
```
Adaptar para unzip:
```swift
// No usar terminationHandler síncrono en MainActor — usar Task.detached para waitUntilExit
// Ver Pitfall 3 de RESEARCH.md
```

**Patrón URLSession request HTTP** (AppDelegate.swift líneas 184–200):
```swift
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
```
El patrón de `URLRequest` + `URLSession.shared.data(for:)` + guard HTTP 200 + JSONSerialization se replica para:
- `createJob()` → POST multipart a `/api/translate/batch/jobs`
- `cancelJob()` → DELETE a `/api/translate/batch/jobs/{id}`
- `downloadZIP()` → GET a `/api/translate/batch/jobs/{id}/download`

**Patrón URLSession.bytes para SSE** (RESEARCH.md Pattern 1, verificado WWDC21):
```swift
func startSSEStream(jobId: String, port: Int) {
    streamTask = Task {
        var request = URLRequest(url: URL(string:
            "http://127.0.0.1:\(port)/api/translate/batch/jobs/\(jobId)/events")!)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }
                guard line.hasPrefix("data: ") else { continue }  // ignora líneas vacías (separador SSE)
                let jsonStr = String(line.dropFirst(6))
                guard let data = jsonStr.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = event["type"] as? String
                else { continue }
                handleSSELine(type: type, payload: event)
                if type == "complete" { break }
            }
        } catch {
            if (error as? URLError)?.code != .cancelled {
                // error real de red — actualizar estado
            }
        }
    }
}
```

**Patrón singleton con init privado** (DockProgressManager.swift líneas 7–13 y NotificationManager.swift líneas 7–10):
```swift
@MainActor
final class DockProgressManager {
    static let shared = DockProgressManager()
    private init() {}
```
Replicar exactamente en BatchJobManager.

**Patrón Process + /usr/bin/unzip** (RESEARCH.md Pattern 4):
```swift
// Llamar siempre desde Task.detached { } — waitUntilExit() BLOQUEA (Pitfall 3)
func extractMarkdownFiles(zipData: Data) async throws {
    let folder = await MainActor.run {
        OutputManager.shared.resolveBookmarkedFolder() ?? downloadsFolder()
    }
    let tmpZip = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("batch-\(UUID().uuidString).zip")
    try zipData.write(to: tmpZip, options: .atomic)
    defer { try? FileManager.default.removeItem(at: tmpZip) }

    // Security-scoped: startAccessing ANTES de p.run() (Pitfall 7 de RESEARCH.md)
    let accessed = folder.startAccessingSecurityScopedResource()
    defer { if accessed { folder.stopAccessingSecurityScopedResource() } }

    try await Task.detached {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")  // p.executableURL, no p.launchPath
        var env = ProcessInfo.processInfo.environment              // heredar siempre
        p.environment = env
        p.arguments = ["-o", "-j", tmpZip.path, "*.md", "-d", folder.path]
        try p.run()   // p.run(), no p.launch()
        p.waitUntilExit()
        // terminationStatus 11 = no hay .md en el ZIP (lote cancelado antes de completar)
    }.value
}
```

---

### `BatchSheet.swift` (view, event-driven)

**Analogs:** `SettingsView.swift` (estructura de sheet) + `SplashView.swift` (patrón .task + alert)

**Estructura de View con binding** (SettingsView.swift líneas 6–18):
```swift
struct SettingsView: View {
    @Binding var isPresented: Bool
    var serverManager: ServerManager

    @State private var openAIKey = ...
    @State private var saved = false
```
Adaptar:
```swift
struct BatchSheet: View {
    @Binding var isPresented: Bool
    var manager: BatchJobManager        // observable singleton — leer estado de aquí
    var serverManager: ServerManager    // para leer serverPort antes de start()
```

**Estructura VStack con cabecera + Divider** (SettingsView.swift líneas 27–42):
```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack {
            Image(systemName: "key.fill")
                .foregroundStyle(Color.accentColor)
            Text("Configuración de API Keys")
                .font(.headline)
            Spacer()
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 12)

        Divider()
        // ... Form / contenido
    }
}
```
Replicar layout: `VStack(alignment: .leading, spacing: 0)` con cabecera `HStack` + `Divider()` + cuerpo condicional según `manager.jobState`.

**Patrón .task en vista** (SplashView.swift líneas 19–32):
```swift
.task {
    if !KeychainManager.hasAnyKey {
        NotificationCenter.default.post(name: .openSettings, object: nil)
        for await _ in NotificationCenter.default
            .notifications(named: .settingsSaved)
            .prefix(1) { }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }
    await serverManager.start()
}
```
NO usar `.task` en BatchSheet para la SSE — el stream lo gestiona `BatchJobManager` (no la vista). La vista solo llama `manager.start(port:)` desde el botón "Traducir".

**Patrón .alert** (SplashView.swift líneas 34–47):
```swift
.alert(
    "Error al iniciar el servidor",
    isPresented: .constant(serverManager.state == .failed)
) {
    Button("Reintentar") { Task { await serverManager.start() } }
    Button("Salir", role: .destructive) { NSApp.terminate(nil) }
} message: {
    Text("El servidor no respondió...")
}
```
En BatchSheet el alert de error de red seguirá el mismo patrón `.alert(isPresented: .constant(...))`.

**Patrón botones de cierre** (SettingsView.swift — patrón de botón que actualiza binding):
```swift
Button("Cancelar") { isPresented = false }
Button("Guardar") { saveKeys() }
    .disabled(!canSave)
```
En el estado `.done` de la sheet:
```swift
Button("Cerrar") { isPresented = false }
Button("Mostrar en Finder") { OutputManager.shared.revealOutputFolder() }
```

**Patrón ProgressView determinado** — no hay analog en vistas existentes; usar API nativa SwiftUI:
```swift
ProgressView(value: Double(manager.filesDone), total: Double(max(manager.filesTotal, 1)))
    .progressViewStyle(.linear)
```

---

### `AppDelegate.swift` (modificación)

**Archivo fuente:** `macos/MDTranslator/MDTranslator/AppDelegate.swift`

**Código a sustituir** (AppDelegate.swift líneas 88–93):
```swift
if markdownURLs.count == 1 {
    loadInEditor(url: markdownURLs[0])
} else {
    confirmAndBatch(markdownURLs)   // ← sustituir por openBatchSheet(_:)
}
```

**Código a sustituir — método completo** (AppDelegate.swift líneas 113–181):
```swift
// confirmAndBatch(_:) — ELIMINAR — sustituir por openBatchSheet(_:)
@MainActor
private func confirmAndBatch(_ urls: [URL]) { ... }

// batchTranslate(urls:port:targetLang:) — ELIMINAR — lógica pasa a BatchJobManager
@MainActor
private func batchTranslate(urls: [URL], port: Int, targetLang: String) async { ... }

// callTranslateAPI(text:targetLang:port:) — VERIFICAR si tiene otros usos antes de eliminar
private func callTranslateAPI(text: String, targetLang: String, port: Int) async throws -> String { ... }
```

**Nuevo método a añadir** (patrón: mismo que `loadInEditor`, @MainActor privado):
```swift
@MainActor
private func openBatchSheet(_ urls: [URL]) {
    BatchJobManager.shared.prepareWith(urls: urls)
    NotificationCenter.default.post(name: .openBatchSheet, object: nil)
}
```

**Patrón nonisolated + MainActor.assumeIsolated** para `applicationShouldTerminate` (AppDelegate.swift líneas 35–57 — mismo patrón que `applicationDidFinishLaunching`):
```swift
nonisolated
func applicationDidFinishLaunching(_ notification: Notification) {
    MainActor.assumeIsolated {
        // ... acceso a NSApp, AppKit
    }
}
```
Nuevo método a añadir, mismo patrón:
```swift
nonisolated
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    MainActor.assumeIsolated {
        guard BatchJobManager.shared.isRunning else { return .terminateNow }
        let n = BatchJobManager.shared.completedCount
        let m = BatchJobManager.shared.totalCount
        let alert = NSAlert()
        alert.messageText = "Hay un lote en curso (\(n) de \(m) archivos)"
        alert.informativeText = "Si sales ahora, el servidor Python se detendrá y se perderán los archivos que aún no se han traducido."
        alert.addButton(withTitle: "Salir y cancelar")
        alert.addButton(withTitle: "Continuar en segundo plano")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
```

**Patrón NSAlert modal existente** (AppDelegate.swift líneas 213–219 — reutilizar para cualquier alerta de error):
```swift
@MainActor
private func presentError(_ title: String, detail: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = detail
    alert.alertStyle = .warning
    alert.runModal()
}
```

---

### `Commands.swift` (modificación)

**Archivo fuente:** `macos/MDTranslator/MDTranslator/Commands.swift`

**Patrón CommandGroup existente** (Commands.swift líneas 13–19):
```swift
CommandGroup(replacing: .newItem) {
    Button("Abrir archivo Markdown…") {
        openMarkdownFile()
    }
    .keyboardShortcut("o")
}
```

**Patrón CommandGroup(after:)** (Commands.swift líneas 22–31):
```swift
CommandGroup(after: .newItem) {
    Button("Traducir") {
        NotificationCenter.default.post(name: WebView.triggerTranslateNotification, object: nil)
    }
    .keyboardShortcut(.return)
    Button("Copiar traducción") {
        NotificationCenter.default.post(name: WebView.copyResultNotification, object: nil)
    }
    .keyboardShortcut("c", modifiers: [.command, .shift])
}
```

**Nuevo CommandGroup a añadir** — usar `after: .newItem` o un nuevo grupo en File:
```swift
CommandGroup(after: .newItem) {
    // ... botones existentes ("Traducir", "Copiar traducción") ...
    Divider()
    Button("Traducir lote…") {
        openBatchFiles()
    }
    .keyboardShortcut("b", modifiers: [.command, .shift])
}
```

**Patrón NSOpenPanel existente** (Commands.swift líneas 84–109):
```swift
private func openMarkdownFile() {
    let panel = NSOpenPanel()
    panel.title = "Abrir archivo Markdown"
    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .text]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true

    guard panel.runModal() == .OK, let url = panel.url else { return }
    // ...
    NSDocumentController.shared.noteNewRecentDocumentURL(url)
    NotificationCenter.default.post(name: WebView.openMarkdownNotification, object: content)
}
```
Adaptar para multi-selección (D-11):
```swift
private func openBatchFiles() {
    let panel = NSOpenPanel()
    panel.title = "Seleccionar archivos Markdown para traducir en lote"
    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .text]
    panel.allowsMultipleSelection = true    // ← diferencia clave
    panel.canChooseDirectories = false
    panel.canChooseFiles = true

    guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
    let urls = panel.urls.filter { $0.pathExtension.lowercased() == "md" }
    guard !urls.isEmpty else { return }
    urls.forEach { NSDocumentController.shared.noteNewRecentDocumentURL($0) }
    NotificationCenter.default.post(name: .openBatchSheet, object: urls)
}
```

**Patrón extensión Notification.Name** (Commands.swift líneas 126–132):
```swift
extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let settingsSaved = Notification.Name("settingsSaved")
}
```
Añadir en el mismo bloque:
```swift
extension Notification.Name {
    static let openSettings  = Notification.Name("openSettings")
    static let settingsSaved = Notification.Name("settingsSaved")
    static let openBatchSheet = Notification.Name("openBatchSheet")  // ← nuevo
}
```

---

### `MDTranslatorApp.swift` (modificación)

**Archivo fuente:** `macos/MDTranslator/MDTranslator/MDTranslatorApp.swift`

**Patrón @State + .sheet** (MDTranslatorApp.swift líneas 15–16 y 66–68):
```swift
@State private var showSettings   = false

// ...
.sheet(isPresented: $showSettings) {
    SettingsView(isPresented: $showSettings, serverManager: serverManager)
}
```
Añadir al mismo nivel:
```swift
@State private var showBatchSheet = false

// ...
.sheet(isPresented: $showBatchSheet) {
    BatchSheet(isPresented: $showBatchSheet,
               manager: BatchJobManager.shared,
               serverManager: serverManager)
}
```

**Patrón .onReceive para notificación** (MDTranslatorApp.swift líneas 70–74):
```swift
.onReceive(
    NotificationCenter.default.publisher(for: .openSettings)
) { _ in
    showSettings = true
}
```
Añadir al mismo bloque `.onReceive` encadenado:
```swift
.onReceive(
    NotificationCenter.default.publisher(for: .openBatchSheet)
) { notification in
    // Si ya hay un job activo, abrir la sheet en el estado en curso (D-04)
    // BatchJobManager.shared.prepareWith(urls:) ya habrá sido llamado por el emisor
    // (AppDelegate u openBatchFiles() en Commands)
    showBatchSheet = true
}
```

**Patrón de compartir el manager con AppDelegate** (MDTranslatorApp.swift líneas 22–25):
```swift
let _ = (delegate.serverManager = serverManager)
let _ = (ServiceHandler.shared.serverManager = serverManager)
```
No necesario para `BatchJobManager` — es singleton `static let shared`, accesible directamente desde cualquier contexto `@MainActor`.

---

## Shared Patterns

### @Observable @MainActor singleton
**Fuente:** `macos/MDTranslator/MDTranslator/ServerManager.swift` líneas 9–20 y `DockProgressManager.swift` líneas 6–13
**Aplicar a:** `BatchJobManager.swift`
```swift
@MainActor
@Observable          // NO ObservableObject — pitfall documentado en RESEARCH.md
final class BatchJobManager {
    static let shared = BatchJobManager()
    private init() {}
    // Propiedades sin @Published — @Observable las rastrea automáticamente
```

### Puente NotificationCenter AppDelegate → SwiftUI
**Fuente:** `macos/MDTranslator/MDTranslator/Commands.swift` líneas 69–72 + `MDTranslatorApp.swift` líneas 70–74
```swift
// Emisor (AppDelegate o Commands):
NotificationCenter.default.post(name: .openSettings, object: nil)

// Receptor (MDTranslatorApp):
.onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
    showSettings = true
}
```

### nonisolated + MainActor.assumeIsolated en AppDelegate
**Fuente:** `macos/MDTranslator/MDTranslator/AppDelegate.swift` líneas 35–57, 62–74, 79–93
**Aplicar a:** `applicationShouldTerminate(_:)` (nuevo método en AppDelegate)
```swift
nonisolated
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    MainActor.assumeIsolated {
        // código síncrono con acceso a AppKit y BatchJobManager.shared
    }
}
```

### Textos de UI en español
**Fuente:** `AppDelegate.swift` líneas 116–122, `Commands.swift` líneas 15, 22, 27
**Aplicar a:** todos los textos visibles en `BatchSheet.swift`, alerts en `AppDelegate.swift`
- Labels de botones: "Traducir", "Cancelar", "Cerrar", "Mostrar en Finder", "Continuar en segundo plano"
- Mensajes de estado: "Cancelando — terminando archivo en curso…"
- Resumen: "Cancelado: N de M traducidos", "N archivos traducidos"
- Alert ⌘Q: "Hay un lote en curso (N de M archivos)"

### Acceso security-scoped antes de operación de archivo
**Fuente:** `macos/MDTranslator/MDTranslator/OutputManager.swift` líneas 38–39, 105–107
```swift
let accessed = folder.startAccessingSecurityScopedResource()
defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
// ... operación de archivo
```
**Aplicar a:** extracción ZIP en `BatchJobManager.extractMarkdownFiles()` — el `startAccessingSecurityScopedResource()` debe estar activo durante toda la ejecución del `Process` de unzip.

### Uso de DockProgressManager
**Fuente:** `macos/MDTranslator/MDTranslator/AppDelegate.swift` líneas 140–141, 147, 167–168
```swift
DockProgressManager.shared.showProgress(current: 0, total: total)
DockProgressManager.shared.setBadge("\(total)")
// ... por evento file_done:
DockProgressManager.shared.showProgress(current: filesDone, total: filesTotal)
// ... al completar:
DockProgressManager.shared.hideProgress()
DockProgressManager.shared.setBadge(nil)
```
**Aplicar a:** `BatchJobManager.handleSSELine()` — llamar desde los eventos `file_done`, `error` y `complete` en lugar de desde el bucle de índice.

### Uso de NotificationManager
**Fuente:** `macos/MDTranslator/MDTranslator/AppDelegate.swift` línea 173
```swift
NotificationManager.shared.sendTranslationDone(filename: summary, langs: targetLang)
```
**Aplicar a:** `BatchJobManager` al recibir evento `complete` — llamar con el resumen (N archivos traducidos) y el `targetLang` del job.

### Uso de OutputManager.saveFileSilently
**Fuente:** `macos/MDTranslator/MDTranslator/AppDelegate.swift` líneas 157–160 y `OutputManager.swift` líneas 36–47
```swift
// AppDelegate usa saveFileSilently con String (contenido)
if OutputManager.shared.saveFileSilently(name: outName, content: translation) {
    saved.append(outName)
}
```
En Phase 18 los `.md` se extraen vía `/usr/bin/unzip` directamente a la carpeta de OutputManager — `saveFileSilently` no se llama por archivo, pero `resolveBookmarkedFolder()` sí se necesita para obtener la URL destino del unzip.

---

## No Analog Found

No hay archivos sin analog en esta fase. Todos los patrones tienen referencia directa en el codebase.

---

## Metadata

**Scope de búsqueda:** `macos/MDTranslator/MDTranslator/`
**Archivos Swift leídos:** 8
- `ServerManager.swift` (219 líneas)
- `MDTranslatorApp.swift` (145 líneas)
- `AppDelegate.swift` (220 líneas)
- `Commands.swift` (133 líneas)
- `DockProgressManager.swift` (78 líneas)
- `OutputManager.swift` (192 líneas)
- `NotificationManager.swift` (62 líneas)
- `SettingsView.swift` (primeras 80 líneas)
- `SplashView.swift` (48 líneas)

**Fecha de extracción:** 2026-06-12
**Dependencias externas añadidas:** ninguna
