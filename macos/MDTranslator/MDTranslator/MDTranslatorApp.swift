// MDTranslatorApp.swift — Punto de entrada de la app macOS.
// Conecta ServerManager con AppDelegate, gestiona la ventana principal y
// los menús nativos. Phase 10: WKWebView + Commands + SettingsView.
// Phase 11: reinicio automático del servidor al cambiar API keys + menu bar icon.
// Phase 13: DROP-01 — onDrop de archivos .md sobre la ventana.
// Phase 14: HOTKEY-01 — hotkey global ⌥⇧M para activar la app (requiere Accesibilidad).
import SwiftUI
import UniformTypeIdentifiers

@main
struct MDTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var serverManager  = ServerManager()
    @State private var showSettings   = false
    @State private var isDropTargeted = false   // resalta la ventana durante el arrastre

    // Dimensiones de ventana según estado del servidor.
    private var windowWidth: CGFloat  { serverManager.state == .running ? 1_100 : 400 }
    private var windowHeight: CGFloat { serverManager.state == .running ? 720   : 220 }

    var body: some Scene {
        // Compartir serverManager con AppDelegate y ServiceHandler.
        let _ = (delegate.serverManager = serverManager)
        let _ = (ServiceHandler.shared.serverManager = serverManager)

        // Solicitar permiso de notificaciones al primer arranque (macOS recuerda la decisión).
        let _ = { NotificationManager.shared.requestPermission() }()

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
            // Escuchar notificación de apertura de settings desde Commands.swift.
            .onReceive(
                NotificationCenter.default.publisher(for: .openSettings)
            ) { _ in
                showSettings = true
            }
            // HOTKEY-01: ⌥⇧M — activar ventana desde cualquier app.
            .onReceive(
                NotificationCenter.default.publisher(for: .globalHotkeyActivate)
            ) { _ in
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.isVisible || !$0.isMiniaturized })?.makeKeyAndOrderFront(nil)
            }
            // HOTKEY-01: re-intentar registrar el hotkey cuando la app vuelve al primer plano.
            // Útil en desarrollo (nueva build → nuevo hash → AX pierde el permiso)
            // y para cuando el usuario concede Accesibilidad sin reiniciar la app.
            .onReceive(
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            ) { _ in
                guard !GlobalHotkeyManager.shared.isAccessibilityGranted else { return }
                // AX no concedida: silencio (el banner en SettingsView ya avisa si está abierto).
                // Cuando se conceda, el próximo activate registrará el hotkey.
                GlobalHotkeyManager.shared.register()
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
