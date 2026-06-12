// MenuBarView.swift — Contenido del icono en la barra de menús (Phase 11).
// Muestra estado del servidor, acceso rápido a la ventana principal
// y acción de traducción rápida desde cualquier contexto.
import SwiftUI
import AppKit

struct MenuBarView: View {
    var serverManager: ServerManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {

        // MARK: Estado del servidor
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)

        Divider()

        // MARK: Acciones principales
        Button("Abrir MDTranslator") {
            openAndActivate()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])

        Button("Traducción rápida…") {
            // Abre la ventana principal y navega al Editor via JS
            openAndActivate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("focusEditor"),
                    object: nil
                )
            }
        }

        Divider()

        // MARK: Configuración y actualización
        Button("Preferencias…") {
            openAndActivate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Buscar actualizaciones…") {
            UpdateManager.shared.checkForUpdates()
        }
        .disabled(!UpdateManager.shared.canCheckForUpdates)

        Divider()

        // MARK: Salir
        Button("Salir MDTranslator") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    // MARK: - Helpers

    private var stateColor: Color {
        switch serverManager.state {
        case .running:  .green
        case .starting: .orange
        case .failed:   .red
        case .idle:     .secondary
        }
    }

    private var stateLabel: String {
        switch serverManager.state {
        case .running:  "Servidor activo"
        case .starting: "Iniciando…"
        case .failed:   "Error al iniciar"
        case .idle:     "Servidor detenido"
        }
    }

    private func openAndActivate() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
