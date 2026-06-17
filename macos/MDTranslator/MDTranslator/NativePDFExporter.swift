// NativePDFExporter.swift — Genera un PDF a partir de HTML usando WKWebView.createPDF.
// PDFN-01: no requiere WeasyPrint ni ninguna dependencia nativa nueva en el bundle.
// PDFN-03: configuración A4 con márgenes de 15 mm para paridad visual con el export HTML.
import AppKit
import WebKit

@MainActor
final class NativePDFExporter: NSObject {

    // WKWebView oculto reutilizable (un único exportador por sesión de app).
    private var webView: WKWebView?
    private var completionHandler: ((Result<Data, Error>) -> Void)?

    // MARK: - API pública

    /// Carga el HTML en un WKWebView oculto y genera el PDF al terminar la navegación.
    /// El handler se llama en MainActor.
    func exportHTML(_ html: String, title: String, completion: @escaping @MainActor (Result<Data, Error>) -> Void) {
        completionHandler = completion

        if webView == nil {
            let config = WKWebViewConfiguration()
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123), configuration: config)
            wv.navigationDelegate = self
            // La WKWebView no necesita estar en la jerarquía de ventanas para createPDF.
            webView = wv
        }

        webView?.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Privado

    private func createAndDeliverPDF() {
        guard let wv = webView else { return }

        // Configuración A4 (210 × 297 mm → puntos: 595.28 × 841.89 pt)
        let pdfConfig = WKPDFConfiguration()
        let a4Points = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        pdfConfig.rect = a4Points

        wv.createPDF(configuration: pdfConfig) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let data):
                    self.completionHandler?(.success(data))
                case .failure(let error):
                    self.completionHandler?(.failure(error))
                }
                self.completionHandler = nil
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension NativePDFExporter: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.createAndDeliverPDF()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.completionHandler?(.failure(error))
            self.completionHandler = nil
        }
    }
}
