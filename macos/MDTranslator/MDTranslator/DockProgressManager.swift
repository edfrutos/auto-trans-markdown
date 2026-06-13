// DockProgressManager.swift — Gestiona el Dock tile durante traducciones en lote nativas.
// Muestra barra de progreso determinate sobre el icono de la app y un badge con el recuento.
// Usado por AppDelegate cuando el usuario arrastra varios .md al icono del Dock.
import AppKit

@MainActor
final class DockProgressManager {
    static let shared = DockProgressManager()

    private var containerView: NSView?
    private var progressBar: NSProgressIndicator?

    private init() {}

    // MARK: - API pública

    /// Muestra (o actualiza) la barra de progreso en el Dock tile.
    /// - Parameters:
    ///   - current: Archivos ya procesados.
    ///   - total:   Total de archivos en el lote.
    func showProgress(current: Int, total: Int) {
        let tile = NSApp.dockTile
        // tile.size puede devolver .zero en contextos async antes de que AppKit inicialice el tile.
        let rawSize = tile.size
        let size = rawSize == .zero ? CGSize(width: 128, height: 128) : rawSize

        if containerView == nil {
            buildTileView(size: size, tile: tile)
        }

        let fraction = total > 0 ? Double(current) / Double(total) : 0
        progressBar?.doubleValue = fraction
        tile.display()
    }

    /// Elimina la barra de progreso y restaura el icono estándar de la app.
    func hideProgress() {
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
        containerView = nil
        progressBar   = nil
    }

    /// Muestra u oculta un badge de texto (p. ej. "3" para indicar archivos pendientes).
    func setBadge(_ text: String?) {
        NSApp.dockTile.badgeLabel = text
    }

    // MARK: - Privado

    private func buildTileView(size: CGSize, tile: NSDockTile) {
        let container = NSView(frame: NSRect(origin: .zero, size: size))

        // Icono de la app como fondo
        let iconView = NSImageView(frame: container.bounds)
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(iconView)

        // Barra de progreso anclada en la parte inferior
        let barH: CGFloat    = 14
        let inset: CGFloat   = 10
        let bar = NSProgressIndicator(frame: NSRect(
            x: inset,
            y: inset,
            width: size.width - inset * 2,
            height: barH
        ))
        bar.style           = .bar
        bar.isIndeterminate = false
        bar.minValue        = 0
        bar.maxValue        = 1
        bar.doubleValue     = 0
        container.addSubview(bar)

        tile.contentView = container
        containerView    = container
        progressBar      = bar
    }
}
