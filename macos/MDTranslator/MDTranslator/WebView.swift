// WebView.swift — Wrapper NSViewRepresentable para WKWebView.
// Carga la interfaz FastAPI/HTML servida por uvicorn en localhost:{port}.
// Incluye WKNavigationDelegate, WKScriptMessageHandler para notificaciones y puente JS→Swift.
import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - Weak message handler (evita retain cycle WKWebView ↔ Coordinator)

/// Wrapper débil para WKScriptMessageHandler.
/// WKUserContentController retiene fuertemente el handler — sin este wrapper
/// el Coordinator (y con él la WKWebView) nunca se libera de memoria.
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(_ delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(controller, didReceive: message)
    }
}

// MARK: - WebView

struct WebView: NSViewRepresentable {
    let url: URL
    /// Notificación que activa una recarga externa (menú Cmd+R).
    static let reloadNotification = Notification.Name("reloadWebView")
    /// Notificación para inyectar contenido Markdown desde el sistema de archivos nativo.
    static let openMarkdownNotification = Notification.Name("openMarkdownContent")
    /// Notificación para disparar el botón Traducir vía ⌘↩ (HOTKEY-02).
    static let triggerTranslateNotification = Notification.Name("triggerTranslate")
    /// Notificación para copiar el panel de resultado al portapapeles vía ⌘⇧C (HOTKEY-03).
    static let copyResultNotification = Notification.Name("copyTranslationResult")
    /// Notificación para deshacer en el editor WKWebView vía ⌘Z (UNDO-01).
    static let undoNotification = Notification.Name("webViewUndo")
    /// Notificación para rehacer en el editor WKWebView vía ⌘⇧Z (UNDO-01).
    static let redoNotification = Notification.Name("webViewRedo")

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Habilitar el inspector web de WebKit (clic derecho → Inspeccionar elemento).
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Registrar message handlers JS→Swift (usando WeakScriptMessageHandler para evitar retain cycle).
        let handler = WeakScriptMessageHandler(context.coordinator)
        config.userContentController.add(handler, name: "translationDone")
        config.userContentController.add(handler, name: "saveTranslatedFile")
        // DOWNLOAD-01: descarga nativa de archivos (MD, ZIP) desde WKWebView.
        config.userContentController.add(handler, name: "nativeDownload")
        // PDFN-01: generación de PDF nativo vía WKWebView.createPDF (sin WeasyPrint).
        config.userContentController.add(handler, name: "nativePDF")

        // Inyectar funciones globales que el frontend puede llamar opcionalmente.
        let helperScript = WKUserScript(source: """
        window.__notifyTranslationDone = function(filename, langs) {
            window.webkit?.messageHandlers?.translationDone?.postMessage({
                filename: filename || 'traducción',
                langs: langs || ''
            });
        };
        window.__saveTranslatedFile = function(filename, content) {
            window.webkit?.messageHandlers?.saveTranslatedFile?.postMessage({
                filename: filename || 'traduccion.md',
                content: content || ''
            });
        };
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(helperScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView

        webView.load(URLRequest(url: url))

        // Escuchar notificación de "Traducción rápida" desde el menu bar icon.
        context.coordinator.focusEditorObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("focusEditor"),
            object: nil,
            queue: .main
        ) { [weak webView] _ in
            // Activar el tab Editor y enfocar el textarea de entrada.
            let js = """
            (function() {
                const tab = document.getElementById('tab-editor');
                if (tab) tab.click();
                const ta = document.getElementById('input-md');
                if (ta) { ta.focus(); ta.select(); }
            })();
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        // Escuchar notificación ⌘↩ para disparar el botón Traducir (HOTKEY-02)
        context.coordinator.translateObserver = NotificationCenter.default.addObserver(
            forName: WebView.triggerTranslateNotification,
            object: nil,
            queue: .main
        ) { [weak webView] _ in
            let js = """
            (function() {
                const btn = document.getElementById('btn-translate');
                if (btn && !btn.disabled) btn.click();
            })();
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        // Escuchar notificación de recarga (Cmd+R desde Commands.swift)
        context.coordinator.reloadObserver = NotificationCenter.default.addObserver(
            forName: WebView.reloadNotification,
            object: nil,
            queue: .main
        ) { [weak webView] _ in
            webView?.reload()
        }

        // HOTKEY-03: ⌘⇧C — copiar el panel de resultado al portapapeles
        context.coordinator.copyResultObserver = NotificationCenter.default.addObserver(
            forName: WebView.copyResultNotification,
            object: nil,
            queue: .main
        ) { [weak webView] _ in
            let js = """
            (function() {
                const val = document.getElementById('output-md')?.value;
                if (val) navigator.clipboard.writeText(val);
            })();
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        // UNDO-01: ⌘Z — deshacer en el textarea del editor
        context.coordinator.undoObserver = NotificationCenter.default.addObserver(
            forName: WebView.undoNotification,
            object: nil,
            queue: .main
        ) { [weak webView] _ in
            webView?.evaluateJavaScript("document.execCommand('undo')", completionHandler: nil)
        }

        // UNDO-01: ⌘⇧Z — rehacer en el textarea del editor
        context.coordinator.redoObserver = NotificationCenter.default.addObserver(
            forName: WebView.redoNotification,
            object: nil,
            queue: .main
        ) { [weak webView] _ in
            webView?.evaluateJavaScript("document.execCommand('redo')", completionHandler: nil)
        }

        // Escuchar notificación de apertura de Markdown (Cmd+O desde Commands.swift)
        context.coordinator.markdownObserver = NotificationCenter.default.addObserver(
            forName: WebView.openMarkdownNotification,
            object: nil,
            queue: .main
        ) { [weak webView] notification in
            guard let content = notification.object as? String,
                  let webView = webView else { return }
            // Inyectar el contenido en el textarea del editor vía JS.
            // El frontend guarda el editor en window.state.editorContent o similar;
            // disparar un evento input para que los listeners reaccionen.
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
            let js = """
            (function() {
                // Activar el tab Editor antes de inyectar (por si está en otra pestaña).
                const tabEditor = document.getElementById('tab-editor');
                if (tabEditor) tabEditor.click();
                // id real del textarea de entrada en static/index.html
                const ta = document.getElementById('input-md');
                if (ta) {
                    ta.value = `\(escaped)`;
                    ta.dispatchEvent(new Event('input', { bubbles: true }));
                    ta.focus();
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Solo recargar si el host o puerto cambiaron (no ocurre en condiciones normales
        // porque el puerto es estático durante la vida de la app).
        let current = nsView.url
        if current?.host != url.host || current?.port != url.port {
            nsView.load(URLRequest(url: url))
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        weak var webView: WKWebView?
        var reloadObserver: NSObjectProtocol?
        var markdownObserver: NSObjectProtocol?
        var focusEditorObserver: NSObjectProtocol?
        var translateObserver: NSObjectProtocol?
        var copyResultObserver: NSObjectProtocol?   // HOTKEY-03
        var undoObserver: NSObjectProtocol?          // UNDO-01
        var redoObserver: NSObjectProtocol?          // UNDO-01
        // PDFN-01: exportador PDF nativo (WKWebView oculto).
        let pdfExporter = NativePDFExporter()

        deinit {
            if let obs = reloadObserver       { NotificationCenter.default.removeObserver(obs) }
            if let obs = markdownObserver     { NotificationCenter.default.removeObserver(obs) }
            if let obs = focusEditorObserver  { NotificationCenter.default.removeObserver(obs) }
            if let obs = translateObserver    { NotificationCenter.default.removeObserver(obs) }
            if let obs = copyResultObserver   { NotificationCenter.default.removeObserver(obs) }
            if let obs = undoObserver         { NotificationCenter.default.removeObserver(obs) }
            if let obs = redoObserver         { NotificationCenter.default.removeObserver(obs) }
        }

        // MARK: - WKScriptMessageHandler (mensajes JS→Swift)

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else { return }

            switch message.name {
            case "translationDone":
                // El frontend notifica que una traducción terminó.
                let filename = body["filename"] as? String ?? "traducción"
                let langs    = body["langs"]    as? String ?? ""
                Task { @MainActor in
                    NotificationManager.shared.sendTranslationDone(filename: filename, langs: langs)
                }

            case "saveTranslatedFile":
                // El frontend pide guardar el archivo traducido en la carpeta de salida.
                let filename = body["filename"] as? String ?? "traduccion.md"
                let content  = body["content"]  as? String ?? ""
                Task { @MainActor in
                    OutputManager.shared.saveTranslatedFile(name: filename, content: content)
                }

            case "nativeDownload":
                // DOWNLOAD-01: descarga nativa para archivos binarios (ZIP) y MD desde WKWebView.
                // El JS lee el Blob como DataURL base64 y lo envía aquí para
                // decodificarlo y guardarlo vía NSSavePanel (OutputManager.saveDownload).
                let filename = body["filename"] as? String ?? "descarga"
                let base64   = body["base64"]   as? String ?? ""
                guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return }
                Task { @MainActor in
                    OutputManager.shared.saveDownload(name: filename, data: data)
                }

            case "nativePDF":
                // PDFN-01: genera un PDF A4 a partir del HTML devuelto por /api/export/html.
                // NativePDFExporter carga el HTML en un WKWebView oculto y usa createPDF(configuration:).
                let html  = body["html"]  as? String ?? ""
                let title = body["title"] as? String ?? "traduccion"
                guard !html.isEmpty else { return }
                Task { @MainActor in
                    self.pdfExporter.exportHTML(html, title: title) { result in
                        switch result {
                        case .success(let pdfData):
                            // PDFN-02: guardar vía NSSavePanel (o carpeta configurada).
                            OutputManager.shared.saveDownload(name: "\(title).pdf", data: pdfData)
                            // Notificar al frontend que el PDF está listo.
                            self.webView?.evaluateJavaScript(
                                "window.showStatus && window.showStatus('PDF exportado.');",
                                completionHandler: nil
                            )
                        case .failure(let error):
                            self.webView?.evaluateJavaScript(
                                "window.showStatus && window.showStatus('Error al generar PDF: \(error.localizedDescription)', 'error');",
                                completionHandler: nil
                            )
                        }
                    }
                }

            default:
                break
            }
        }

        // PREF-02/04: inyectar tono por defecto y tooltip del botón de traducción
        // tras cada carga de página (incluidos reloads del servidor).
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let tone  = UserDefaults.standard.string(forKey: "MDTranslator.defaultTone") ?? ""
            let model = UserDefaults.standard.string(forKey: "MDTranslator.openAIModel") ?? "gpt-4o-mini"
            let toneLabel = tone == "formal" ? "Formal" : tone == "informal" ? "Informal" : "Neutro"
            let toneValue = tone.isEmpty ? "auto" : tone
            let safeModel     = model.replacingOccurrences(of: "'", with: "\\'")
            let safeToneLabel = toneLabel.replacingOccurrences(of: "'", with: "\\'")
            let js = """
            (function() {
              var ts = document.getElementById('tone-select');
              if (ts) ts.value = '\(toneValue)';
              var btn = document.getElementById('btn-translate');
              if (btn) btn.title = 'Modelo: \(safeModel) | Tono: \(safeToneLabel)';
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // Error de navegación provisional (servidor no responde, URL inválida…)
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            handleLoadError(error, in: webView)
        }

        // Error durante la carga (página devuelve error tras empezar a cargar)
        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            handleLoadError(error, in: webView)
        }

        // Links con target="_blank" → abrir en navegador del sistema, no en la WebView.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // MARK: - WKUIDelegate: confirm() nativo

        /// WKWebView suprime confirm() por defecto; este delegate lo muestra como NSAlert nativo.
        /// Sin él, clearMemory() retorna inmediatamente (confirm devuelve false) sin borrar nada.
        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Aceptar")
            alert.addButton(withTitle: "Cancelar")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        // MARK: - WKUIDelegate (file picker nativo para <input type="file">)

        /// WKWebView llama este método cuando el frontend hace click en un <input type="file">.
        /// Sin este delegate el picker nunca se abre en una app macOS embebida.
        func webView(
            _ webView: WKWebView,
            runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping ([URL]?) -> Void
        ) {
            let panel = NSOpenPanel()
            panel.canChooseFiles       = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            // Limitar a Markdown (.md, .markdown) — el frontend solo acepta estos tipos.
            panel.allowedContentTypes = [
                .init(filenameExtension: "md")!,
                .init(filenameExtension: "markdown")!,
            ]
            panel.begin { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }

        private func handleLoadError(_ error: Error, in webView: WKWebView) {
            // Ignorar cancelaciones de carga (ocurren al llamar a .reload() mientras ya carga)
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            // Ignorar WebKitErrorFrameLoadInterruptedByPolicyChange (102) — se dispara cuando
            // WKWebView intenta navegar a un blob: URL. Con DOWNLOAD-01 esto no debería ocurrir,
            // pero lo ignoramos de forma defensiva para no mostrar la página de error.
            if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }

            // Mostrar página de error inline con botón de reintento.
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <style>
              body { font-family: -apple-system, sans-serif; display: flex; flex-direction: column;
                     align-items: center; justify-content: center; height: 100vh; margin: 0;
                     color: #555; background: #f9f9f9; }
              h2 { font-size: 1.2rem; margin-bottom: 0.5rem; }
              p  { font-size: 0.9rem; color: #888; margin: 0 0 1.5rem; }
              button { padding: 8px 20px; border: none; border-radius: 6px;
                       background: #007AFF; color: white; font-size: 0.9rem; cursor: pointer; }
            </style>
            </head>
            <body>
              <h2>No se pudo cargar la interfaz</h2>
              <p>\(nsError.localizedDescription)</p>
              <button onclick="location.reload()">Reintentar</button>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}
