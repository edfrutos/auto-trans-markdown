# Feature Landscape — macOS Native App (v3.0)

**Domain:** macOS native translation app (SwiftUI + embedded Python backend)
**Researched:** 2026-06-02
**Scope:** Solo features nuevas o significativamente diferentes respecto a la web app existente.
**Overall confidence:** HIGH (Context7 + documentación oficial Apple + Sparkle docs)

---

## Table Stakes

Features que un usuario macOS espera. Su ausencia hace que la app parezca un port barato.

| Feature | Por qué se espera | Complejidad | Patrón SwiftUI | Backend Python |
|---------|-------------------|-------------|----------------|----------------|
| **Sidebar + content area (NavigationSplitView)** | Estándar en apps macOS con múltiples modos (Mail, Finder, Notes) | Media | `NavigationSplitView(sidebar:detail:)` — macOS 13+ | No |
| **Drag & drop de archivos .md desde Finder** | Comportamiento nativo macOS esperado en cualquier editor de texto | Media | `onDrop(of: [.fileURL], isTargeted:perform:)` + `NSItemProvider.loadFileRepresentation` | No |
| **API keys en Keychain (no .env)** | Estándar de seguridad macOS; los usuarios esperan no manejar ficheros de config | Alta | `SecItemAdd` / `SecItemCopyMatching` con `kSecClassGenericPassword` | No (Keychain → env vars antes de lanzar subprocess) |
| **Ventana Preferencias nativa (Cmd+,)** | Convención macOS inviolable | Baja | `Settings { SettingsView() }` scene en `App.body` — macOS 11+ | No |
| **Atajos de teclado en menú** | Usuarios power user esperan Cmd+T (traducir), Cmd+O (abrir), etc. | Baja | `.commands { CommandMenu(...) }` + `.keyboardShortcut("T")` | No |
| **Notificaciones nativas al completar batch** | Feedback sin mantener ventana abierta; la app puede estar en background | Media | `UNUserNotificationCenter.current().add(request)` + `requestAuthorization` al arrancar | No (disparo desde Swift al recibir respuesta HTTP de la API local) |
| **Backend Python embebido (sin instalar Python)** | App autocontenida; el usuario no instala nada extra | Muy Alta | `Process()` + `executableURL` apuntando a python-build-standalone en `Bundle.main.resourceURL` | Sí — el .app bundle contiene el intérprete + deps |
| **Health check antes de primera request** | El subprocess tarda ~1-2 s en arrancar; sin esto hay race condition | Media | Loop `URLSession` con retry en Swift hasta recibir 200 en `/health` | Requiere endpoint `/health` en FastAPI (trivial añadir si no existe) |

---

## Differentiators

Features que la web app no puede ofrecer o que en macOS son significativamente mejor.

| Feature | Valor añadido | Complejidad | Patrón SwiftUI | Backend Python |
|---------|---------------|-------------|----------------|----------------|
| **Menubar icon (MenuBarExtra)** | Traducción rápida sin abrir ventana principal; acceso desde cualquier contexto | Media | `MenuBarExtra("MDTranslate", systemImage: "doc.text")` con `.menuBarExtraStyle(.menu)` para acciones rápidas o `.window` para UI rica. Coexiste con `WindowGroup` en el mismo `App.body` | No (solo llama a la API local) |
| **File association: abrir .md con doble-click** | El usuario puede registrar la app como editora de .md en Finder | Media | `CFBundleDocumentTypes` + `UTExportedTypeDeclarations` en `Info.plist` con `public.utf8-plain-text` conformance | No |
| **Auto-update (Sparkle 2)** | Distribución fuera del App Store con updates automáticos | Alta | SPM: `https://github.com/sparkle-project/Sparkle`. `SPUStandardUpdaterController` en `App.init()`. `CheckForUpdatesView` en `CommandGroup(after: .appInfo)`. Requiere appcast XML en servidor y firma EdDSA | No |
| **Drop zone visual con feedback isTargeted** | En la web hay un botón; en macOS el drop desde Finder con feedback visual es más natural | Baja-Media | `dropDestination(for:action:isTargeted:)` con animación de borde en `isTargeted = true` | No |
| **Glosario y TM en `~/Library/Application Support/`** | Ubicación estándar macOS para datos de usuario; backup automático con Time Machine | Media | `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` para resolver ruta | Sí — el servidor Python recibe la ruta via variable de entorno `GLOSSARY_PATH` / `TM_DB_PATH` |
| **Badge en Dock al completar batch** | Feedback visible incluso cuando la app está minimizada | Baja | `NSApplication.shared.dockTile.badgeLabel = "\(count)"` + resetear al activar la app | No |
| **Modo offline con mensaje claro** | Detección de red antes de intentar llamada a API; en la web simplemente falla con error HTTP | Baja | `NWPathMonitor` (Network framework) para detectar conectividad antes de disparar request | No |

---

## Nice-to-Have (diferir post-MVP macOS)

| Feature | Motivo de diferimiento | Alternativa inmediata |
|---------|------------------------|----------------------|
| **iCloud Drive sync del glosario/TM** | Requiere entitlement + Apple Developer account ($99/año); PROJECT.md dice distribuir ad-hoc | `~/Library/Application Support/` con sync manual |
| **Quick Look preview del .md traducido** | Buena UX pero requiere `QLPreviewPanel` y plugin separado | Split view con texto renderizado como `Text` scrollable |
| **Spotlight indexing (NSMetadataItem)** | Permite buscar traducciones pasadas desde Spotlight | Omitir en v3.0 |
| **Notarización con Apple Developer** | PROJECT.md dice ad-hoc explícitamente | Instrucciones para bypassear Gatekeeper (clic derecho → Abrir) en README |
| **Touch Bar support** | Deprecado en hardware actual (MacBook Pro M3+) | Omitir |

---

## Anti-Features

Features a NO construir en v3.0.

| Anti-Feature | Por qué evitar | En su lugar |
|--------------|----------------|-------------|
| **WebView embebido de la UI web existente** | Derrota el propósito; pierde integración nativa; PROJECT.md eligió SwiftUI explícitamente | SwiftUI nativo desde cero |
| **Autenticación multi-usuario / Bearer en app** | La app es mono-usuario local; la API key es del usuario, no multi-tenant | Keychain con un conjunto de keys por proveedor |
| **Plugin manager en app** | Scope demasiado grande para v3.0 | Plugin Obsidian/VS Code es backlog separado (V2-02) |
| **Redux-style state management** | Sobre-ingeniería para una app de escritorio con poco estado compartido | `@StateObject` + `@EnvironmentObject` es suficiente |
| **Servidor expuesto en red local** | Sin auth Bearer, el servidor embebido solo debe escuchar `127.0.0.1` | `HOST=127.0.0.1` forzado en subprocess env |

---

## Diferenciadores macOS vs Web (resumen ejecutivo)

| Dimensión | App Web | App macOS nativa |
|-----------|---------|-----------------|
| **Ingesta de archivos** | Botón upload en browser | Drag desde Finder, doble-click en .md, file association |
| **Gestión de credenciales** | .env en disco (riesgo) | Keychain encriptado del OS |
| **Accesibilidad del servicio** | Requiere abrir browser y navegar | Menubar icon siempre accesible desde cualquier app |
| **Feedback de completado** | Visible solo si la pestaña está abierta | Notificación nativa con sonido + badge en Dock |
| **Persistencia de preferencias** | localStorage / sin backup | `~/Library/Application Support/` + Time Machine |
| **Updates** | Recargar página | Auto-update Sparkle sin intervención del usuario |
| **Arranque** | Depende de un servidor externo en ejecución | Backend embebido se lanza y termina con la app |
| **Privacidad** | Los archivos transitan por el browser + servidor | Todo local; los .md nunca salen del Mac salvo a la API de traducción |

---

## Feature Dependencies

```
Backend embebido (subprocess Python)
  → Health check en /health (FastAPI)
    → Todo el resto de features de traducción

Keychain (API keys)
  → Inyectar como env vars al subprocess antes de Process.run()
    → Backend Python las lee como os.getenv() sin cambios en su código

Notificaciones nativas
  → requestAuthorization en onAppear o applicationDidFinishLaunching
    → Disparar desde Swift al recibir respuesta de la API local
    → Badge en Dock = complementario, no sustituye la notificación

Glosario/TM en Application Support
  → Backend Python recibe ruta via variable de entorno GLOSSARY_PATH / TM_DB_PATH
    → Leer con FileManager en Swift, pasar al subprocess en su environment

Sparkle (auto-update)
  → Appcast XML en servidor HTTPS
    → Firma EdDSA de los binarios distribuidos (generate_keys + sign_update)
    → Re-firma manual de XPC services de Sparkle con codesign antes de distribuir

MenuBarExtra
  → Coexiste con WindowGroup sin conflicto (mismo App.body, macOS 13+)
    → Para abrir ventana principal desde menu:
      NSApp.windows.first { !$0.isFloatingPanel }?.makeKeyAndOrderFront(nil)

File association (.md)
  → Info.plist CFBundleDocumentTypes con LSItemContentTypes
    → UTExportedTypeDeclarations con conformance a public.utf8-plain-text
```

---

## Patrones SwiftUI Concretos (referencia de implementación)

### 1. NavigationSplitView — sidebar + content — macOS 13+

```swift
// Fuente: developer.apple.com/documentation/swiftui/navigationsplitview (Context7, HIGH)
NavigationSplitView {
    SidebarView()                            // Lista de modos/archivos recientes
        .navigationSplitViewColumnWidth(220)
} detail: {
    TranslationDetailView()                  // Editor o resultados
}
// Para 3 columnas (sidebar + lista + detail):
// NavigationSplitView(sidebar:content:detail:)
// Control programático de visibilidad: NavigationSplitViewVisibility
```

### 2. Drag & drop de archivos .md

```swift
// Fuente: developer.apple.com/documentation/swiftui/view/ondrop (Context7, HIGH)
// CRITICO: loadFileRepresentation debe iniciarse DENTRO del closure perform (restricción de seguridad)
@State private var isDropTargeted = false

RoundedRectangle(cornerRadius: 12)
    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
        for provider in providers {
            provider.loadFileRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier
            ) { url, _ in
                guard let url, url.pathExtension == "md" else { return }
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
                // leer contenido y enviar a la API local
            }
        }
        return true
    }
// UTType para .md: no existe tipo nativo en Apple.
// Usar .fileURL para drop y filtrar por extensión,
// o UTType(tag: "md", tagClass: .filenameExtension, conformingTo: .plainText)
```

### 3. App híbrida: WindowGroup + MenuBarExtra + Settings

```swift
// Fuente: developer.apple.com/documentation/swiftui/menubarextra (Context7, HIGH)
@main
struct MDTranslateApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandMenu("Traducir") {
                Button("Traducir selección") { /* ... */ }
                    .keyboardShortcut("T")
                Button("Abrir archivo .md…") { /* ... */ }
                    .keyboardShortcut("O", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        MenuBarExtra("MDTranslate", systemImage: "doc.text.magnifyingglass") {
            Button("Traducir texto…") { /* abre ventana o inline */ }
            Button("Abrir ventana principal") {
                NSApp.windows.first { !$0.isFloatingPanel }?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Salir") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)   // .window si se necesita UI más rica

        Settings {
            SettingsView()          // Cmd+, — paneles: General, Proveedores, Avanzado
        }
    }
}
```

### 4. Notificaciones locales al completar batch

```swift
// Fuente: developer.apple.com/documentation/usernotifications/unusernotificationcenter (WebFetch oficial Apple, HIGH)

// Paso 1: solicitar permiso una vez al arrancar la app
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

// Paso 2: disparar cuando la API local responde con batch completo
func notifyBatchComplete(fileCount: Int) {
    let content = UNMutableNotificationContent()
    content.title = "Traducción completada"
    content.body = "\(fileCount) archivo(s) traducido(s) correctamente."
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil            // nil = inmediato
    )
    UNUserNotificationCenter.current().add(request)

    // Badge en Dock (complementario)
    NSApplication.shared.dockTile.badgeLabel = "\(fileCount)"
}
```

### 5. Keychain para API keys

```swift
// Fuente: developer.apple.com/documentation/security/keychain_services (WebFetch oficial Apple, HIGH)
import Security

struct KeychainManager {
    static let service = "com.tuapp.mdtranslate"

    static func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)     // eliminar si ya existe
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// Antes de lanzar el subprocess Python:
// env["OPENAI_API_KEY"] = KeychainManager.load(forKey: "openai_api_key") ?? ""
// env["DEEPL_API_KEY"]  = KeychainManager.load(forKey: "deepl_api_key") ?? ""
```

### 6. Backend Python como subprocess embebido

```swift
// Fuente: developer.apple.com/documentation/foundation/process (WebFetch oficial Apple, HIGH)
@MainActor
class BackendManager: ObservableObject {
    private var process: Process?
    @Published var isReady = false
    @Published var startError: String?

    func start() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let pythonBin    = resourceURL.appendingPathComponent("python/bin/python3")
        let serverScript = resourceURL.appendingPathComponent("server/src/main.py")

        let proc = Process()
        proc.executableURL       = pythonBin
        proc.arguments           = [serverScript.path]
        proc.currentDirectoryURL = serverScript.deletingLastPathComponent()
        proc.environment         = buildEnvironment()   // API keys de Keychain + HOST=127.0.0.1 + PORT=8000

        let errPipe = Pipe()
        proc.standardError = errPipe

        do {
            try proc.run()
            self.process = proc
            Task { await waitForReady() }
        } catch {
            startError = error.localizedDescription
        }
    }

    private func waitForReady() async {
        // Polling /health hasta 200 o timeout ~10 s
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000)   // 0.5 s
            guard let url = URL(string: "http://127.0.0.1:8000/health") else { continue }
            if let (_, resp) = try? await URLSession.shared.data(from: url),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                isReady = true
                return
            }
        }
        startError = "El servidor Python no respondió en 10 s. Verifica los logs."
    }

    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOST"]             = "127.0.0.1"
        env["PORT"]             = "8000"
        env["OPENAI_API_KEY"]   = KeychainManager.load(forKey: "openai_api_key") ?? ""
        env["DEEPL_API_KEY"]    = KeychainManager.load(forKey: "deepl_api_key") ?? ""
        env["TRANSLATION_PROVIDER"] = UserDefaults.standard.string(forKey: "provider") ?? "openai"
        // Rutas de datos en Application Support
        if let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = appSupport.appendingPathComponent("MDTranslate")
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            env["GLOSSARY_PATH"] = appDir.appendingPathComponent("glossary.yaml").path
            env["TM_DB_PATH"]    = appDir.appendingPathComponent("translation_memory.db").path
        }
        return env
    }

    func stop() {
        process?.terminate()
        process?.waitUntilExit()
    }
}
```

### 7. Auto-update con Sparkle 2 (SPM)

```swift
// Fuente: sparkle-project.org/documentation/programmatic-setup (Context7, HIGH)
// Añadir en Xcode: File > Add Packages > https://github.com/sparkle-project/Sparkle
// Requiere: appcast.xml en servidor HTTPS, firma EdDSA del .dmg de update
// Requiere re-firma XPC services con codesign antes de distribuir (ver PITFALLS.md)

import Sparkle

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater
    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }
    var body: some View {
        Button("Buscar actualizaciones…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
```

---

## MVP Recommendation

Priorizar para entrega inicial de v3.0 (orden de implementación):

1. **Backend embebido + health check** — fundamento de todo lo demás; sin esto nada funciona
2. **NavigationSplitView** con modos Editor / Archivo / Batch — paridad funcional con la web
3. **Keychain** para API keys — seguridad no negociable; sustituye al .env
4. **Settings scene** con `TabView` (General, Proveedores, Avanzado) — necesario para introducir las keys
5. **Drag & drop** de archivos .md — diferenciador de primera impresión, baja complejidad
6. **Notificaciones** al completar batch — UX completion loop, pocas líneas de código

Diferir a iteración posterior dentro de v3.0:

- **MenuBarExtra** — nice-to-have; añadir tras tener la ventana principal funcional
- **Sparkle auto-update** — requiere infraestructura de distribución; añadir antes del primer release público
- **File association** — menor impacto; añadir cuando la app sea estable

---

## Sources

| Fuente | Usado para | Confianza |
|--------|-----------|-----------|
| Context7 `/websites/developer_apple_swiftui` | NavigationSplitView, onDrop, MenuBarExtra, Settings, CommandMenu, AppStorage | HIGH |
| developer.apple.com/documentation/usernotifications | UNUserNotificationCenter, requestAuthorization, UNNotificationRequest | HIGH |
| developer.apple.com/documentation/security/keychain_services | SecItemAdd, SecItemCopyMatching, kSecClassGenericPassword | HIGH |
| developer.apple.com/documentation/foundation/process | Process, executableURL, standardError, terminate | HIGH |
| Context7 `/websites/sparkle-project` | SPUStandardUpdaterController, appcast, EdDSA, XPC signing, SPM setup | HIGH |
| developer.apple.com (UTType) | No existe UTType nativo para .md; usar .fileURL + filtro por extensión | MEDIUM |
| .planning/PROJECT.md | Restricciones del proyecto, decisiones clave (ad-hoc DMG, no notarización) | HIGH |
