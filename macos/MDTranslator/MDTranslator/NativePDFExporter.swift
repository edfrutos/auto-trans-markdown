// NativePDFExporter.swift — Genera un PDF A4 multipágina a partir de HTML.
//
// Estrategia (sin NSPrintOperation — bloquea el hilo principal con WKWebView):
//  1. Inyectar CSS vía JS: quitar max-width del body → contenido a ancho completo
//  2. Obtener scrollHeight → expandir frame del WKWebView a la altura total
//  3. WKWebView.createPDF → PDF de página única con toda la altura del documento
//  4. CoreGraphics: dividir ese PDF largo en páginas A4 con márgenes propios
//
// PDFN-01: sin WeasyPrint ni dependencias externas más allá de CoreGraphics.
import AppKit
import WebKit

@MainActor
final class NativePDFExporter: NSObject {

    private var webView: WKWebView?
    private var completionHandler: ((Result<Data, Error>) -> Void)?

    // MARK: - Dimensiones A4 (puntos PDF = 1/72 in)
    private enum A4 {
        static let w: CGFloat = 595.28
        static let h: CGFloat = 841.89
        static let mH: CGFloat = 48     // margen horizontal ≈ 17 mm
        static let mV: CGFloat = 54     // margen vertical   ≈ 19 mm
        static var cW: CGFloat { w - 2 * mH }   // ancho de contenido
        static var cH: CGFloat { h - 2 * mV }   // alto  de contenido por página
    }

    // MARK: - API pública

    /// Carga el HTML en un WKWebView oculto y genera el PDF al terminar la navegación.
    func exportHTML(_ html: String, title: String,
                    completion: @escaping @MainActor (Result<Data, Error>) -> Void) {
        completionHandler = completion

        if webView == nil {
            let config = WKWebViewConfiguration()
            // 794 px ≈ ancho A4 en píxeles CSS (210 mm a 96 dpi)
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123),
                               configuration: config)
            wv.navigationDelegate = self
            webView = wv
            // Nota: WKWebView.createPDF no requiere jerarquía de ventanas
        }
        webView?.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Privado

    private func createAndDeliverPDF() {
        guard let wv = webView else { return }

        // 1. Eliminar max-width del body y obtener scrollHeight en el mismo JS
        let js = """
        (function() {
            var s = document.getElementById('__pdfStyle');
            if (!s) {
                s = document.createElement('style');
                s.id = '__pdfStyle';
                document.head.appendChild(s);
            }
            s.textContent = 'body{max-width:none!important;margin:0!important;padding:0!important;}';
            return document.documentElement.scrollHeight;
        })()
        """
        wv.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self, let wv = self.webView else { return }

            let h: CGFloat
            if let i = value as? Int         { h = CGFloat(i) }
            else if let d = value as? Double { h = CGFloat(d) }
            else                             { h = 2000 }

            // 2. Expandir frame al contenido completo para que createPDF no recorte
            wv.frame = CGRect(x: 0, y: 0, width: wv.frame.width, height: h)

            // 3. createPDF: una sola página con toda la altura
            wv.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let data):
                    // 4. Dividir en páginas A4 con CoreGraphics
                    self.completionHandler?(.success(self.paginateToA4(data) ?? data))
                case .failure(let err):
                    self.completionHandler?(.failure(err))
                }
                self.completionHandler = nil
            }
        }
    }

    // MARK: - Paginación A4 con CoreGraphics

    /// Recibe el PDF de una sola página (alta) y devuelve un PDF multipágina A4.
    private func paginateToA4(_ source: Data) -> Data? {
        guard
            let provider = CGDataProvider(data: source as CFData),
            let srcDoc   = CGPDFDocument(provider),
            srcDoc.numberOfPages >= 1,
            let srcPage  = srcDoc.page(at: 1)      // CGPDFDocument es 1-indexed
        else { return nil }

        let src = srcPage.getBoxRect(.mediaBox)
        // src ≈ { 0, 0, 794, scrollHeight }  (unidades: puntos PDF ≈ píxeles CSS)

        // Escala para ajustar el ancho del fuente (794 px) al ancho de contenido A4
        let sc  = A4.cW / src.width
        // Cuántos puntos fuente caben en el alto de contenido de una página A4
        let spp = A4.cH / sc
        let np  = Int(ceil(src.height / spp))

        let outData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: A4.w, height: A4.h)
        guard
            let consumer = CGDataConsumer(data: outData as CFMutableData),
            let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }

        for i in 0 ..< np {
            // Rango Y en el fuente para esta página
            // Coords PDF: 0 = abajo, src.height = arriba (= parte superior del doc web)
            let yTop = src.height - CGFloat(i) * spp
            let yBot = max(0, yTop - spp)

            ctx.beginPDFPage(nil as CFDictionary?)
            ctx.saveGState()

            // Recortar al área de contenido de la página destino
            ctx.clip(to: CGRect(x: A4.mH, y: A4.mV, width: A4.cW, height: A4.cH))

            // Transformación: (0, yBot) fuente → (mH, mV) destino
            ctx.translateBy(x: A4.mH, y: A4.mV - yBot * sc)
            ctx.scaleBy(x: sc, y: sc)

            // Dibujar la página fuente completa; el clip hace la "ventana"
            ctx.drawPDFPage(srcPage)

            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()

        return outData as Data
    }
}

// MARK: - WKNavigationDelegate

extension NativePDFExporter: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.createAndDeliverPDF()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                              withError error: Error) {
        Task { @MainActor [weak self] in
            self?.completionHandler?(.failure(error))
            self?.completionHandler = nil
        }
    }
}
