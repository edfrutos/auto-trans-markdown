// MDTranslatorApp.swift — Punto de entrada de la app macOS.
// Conecta ServerManager con AppDelegate, gestiona la ventana principal y
// los menús nativos. Phase 10: WKWebView + Commands + SettingsView.
// Phase 11: reinicio automático del servidor al cambiar API keys + menu bar icon.
// Phase 13: DROP-01 — onDrop de archivos .md sobre la ventana.
// Phase 14: HOTKEY-01 — hotkey global ⌥⇧M para activar la app (requiere Accesibilidad).
// Phase 18: showBatchSheet + .sheet(BatchSheet) + .onReceive(.openBatchSheet) (SSE batch nativo).
// Phase 19: ASSOC-02 — consumir delegate.pendingURLs al pasar a .running.
import SwiftUI
import UniformTypeIdentifiers

@main
struct MDTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var serverManager  = ServerManager()
    @State private var showSettings   = false
    @State private var showBatchSheet = false
    @State private var isDropTargeted = false   // resalta la ventana durante el arrastre

    // Dimensiones de ventana según estado del servidor.
    private var windowWidth: CGFloat  { serverManager.state == .running ? 1_100 : 400 }
    private var windowHeight: CGFloat { serverManager.state == .running ? 720   : 220 }

    var body: some Scene {
        // Compartir serverManager con AppDelegate y ServiceHandler.
        let _ = (delegate.serverManager = serverManager)
        let _ = (ServiceHandler.shared.serverManager = serverManager)

        // SERVICES-01 (respaldo): garantizar que servicesProvider quede registrado una vez.
        // Usa flag estático para que sea inmune a re-evaluaciones de body y a que SwiftUI
        // inicialice NSApp.servicesProvider internamente (lo que rompería el guard == nil).
        let _ = {
            struct Once { static var done = false }
            guard !Once.done else { return }
            Once.done = true
            NSApp.servicesProvider = ServiceHandler.shared
            NSUpdateDynamicServices()
            NSLog("[App] servicesProvider = ServiceHandler.shared (body respaldo)")
        }()

        // Solicitar permiso de notificaciones al primer arranque (macOS recuerda la decisión).
        let _ = { NotificationManager.shared.requestPermission() }()

        // SYNC-01: comprobar conflictos SQLite iCloud al arrancar (aviso en SettingsView).
        let _ = { SyncManager.shared.onAppLaunch() }()

        // Hotkey global ⌥⇧M: registrado en AppDelegate.applicationDidFinishLaunching (HOTKEY-01).

        // WindowGroup(id:) garantiza que macOS persiste el frame de la ventana entre reinicios.
        WindowGroup(id: "main") {
            Group {
                if serverManager.state == .running {
                    WebView(url: URL(string: "http://127.0.0.1:\(serverManager.serverPort)")!)
                        .frame(width: windowWidth, height: windowHeight)
                        // DROP-01: acepta .md arrastrados directamente sobre la ventana
                        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                            handleFileDrop(providers: providers)
                        }
                        // Borde de acento visible mientras se arrastra un archivo
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor, lineWidth: isDropTargeted ? 3 : 0)
                                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
                        )
                } else {
                    SplashView(serverManager: serverManager)
                        .frame(width: 400, height: 220)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: serverManager.state == .running)
            // Sheet de configuración de API keys — se activa con ⌘, o en primera ejecución.
            .sheet(isPresented: $showSettings) {
                SettingsView(isPresented: $showSettings, serverManager: serverManager)
            }
            // Sheet de lote SSE — se activa desde AppDelegate (drag Dock) o Commands (⌘⇧B).
            .sheet(isPresented: $showBatchSheet) {
                BatchSheet(isPresented: $showBatchSheet,
                           manager: BatchJobManager.shared,
                           serverManager: serverManager)
            }
            // Escuchar notificación de apertura de settings desde Commands.swift.
            .onReceive(
                NotificationCenter.default.publisher(for: .openSettings)
            ) { _ in
                showSettings = true
            }
            // Escuchar notificación de apertura de la sheet de lote (Phase 18).
            // BatchJobManager.shared.prepareWith(urls:) ya habrá sido llamado por el emisor
            // (AppDelegate.openBatchSheet o Commands.openBatchFiles).
            // Si isRunning, la sheet abre directamente en estado de progreso (D-04).
            .onReceive(
                NotificationCenter.default.publisher(for: .openBatchSheet)
            ) { _ in
                showBatchSheet = true
            }
            // HOTKEY-01: ⌥⇧M — activar ventana desde cualquier app.
            .onReceive(
                NotificationCenter.default.publisher(for: .globalHotkeyActivate)
            ) { _ in
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.isVisible || !$0.isMiniaturized })?.makeKeyAndOrderFront(nil)
            }
            // HOTKEY-01: re-intentar registrar el hotkey cuando la app vuelve al primer plano.
            // register() es idempotente: si AX acaba de concederse (y globalMonitor == nil),
            // añade el monitor global en ese momento. Si ya estaba registrado, es no-op.
            .onReceive(
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            ) { _ in
                GlobalHotkeyManager.shared.register()
            }
            // ASSOC-02: consumir URLs encoladas durante el arranque en frío.
            // Se dispara cuando serverManager.state cambia a .running (health check OK).
            .onChange(of: serverManager.state) { _, newState in
                guard newState == .running else { return }
                let queued = delegate.pendingURLs
                guard !queued.isEmpty else { return }
                delegate.pendingURLs = []
                delegate.dispatchURLs(queued)
            }
            // Reiniciar el servidor cuando el usuario guarda nuevas API keys en medio de sesión.
            .onReceive(
                NotificationCenter.default.publisher(for: .settingsSaved)
            ) { _ in
                guard serverManager.state == .running else { return }
                Task {
                    serverManager.stop()
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await serverManager.start()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: windowWidth, height: windowHeight)
        .commands {
            AppCommands(serverPort: serverManager.serverPort)
        }

        // MARK: Menu bar icon (Phase 11)
        MenuBarExtra {
            MenuBarView(serverManager: serverManager)
        } label: {
            Label("MDTranslator", systemImage: "translate")
        }
        .menuBarExtraStyle(.menu)
    }

    // MARK: - DROP-01: manejo de archivos arrastrados sobre la ventana

    /// Procesa los providers de un drop de URLs sobre la ventana activa.
    /// Un archivo → editor; varios → misma lógica batch que el Dock (vía AppDelegate).
    @discardableResult
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        var markdownURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url  = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "md" else { return }
                DispatchQueue.main.sync { markdownURLs.append(url) }
            }
        }

        group.notify(queue: .main) {
            guard !markdownURLs.isEmpty else { return }
            // Reutilizar la misma lógica que AppDelegate (recientes + editor/batch)
            NSApp.delegate?.application?(NSApp, open: markdownURLs)
        }
        return !providers.isEmpty
    }
}
