// SplashView.swift — Vista de arranque que muestra progreso y gestiona errores del servidor.
// En primera ejecución (sin API keys en Keychain) publica openSettings antes de arrancar.
import SwiftUI
import AppKit

struct SplashView: View {
    var serverManager: ServerManager

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(.circular)
            Text("Iniciando servidor...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(width: 400, height: 220)
        // .task es cancelable y está ligado al ciclo de vida de la vista.
        .task {
            // Primera ejecución: si no hay ninguna API key guardada, abrir settings
            // y esperar a que el usuario guarde antes de arrancar el servidor.
            if !KeychainManager.hasAnyKey {
                NotificationCenter.default.post(name: .openSettings, object: nil)
                // Esperar notificación .settingsSaved (publicada por SettingsView.saveKeys())
                for await _ in NotificationCenter.default
                    .notifications(named: .settingsSaved)
                    .prefix(1) { }
                // Breve pausa para que el sheet se cierre visualmente antes del arranque.
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            await serverManager.start()
        }
        .alert(
            "Error al iniciar el servidor",
            isPresented: .constant(serverManager.state == .failed)
        ) {
            Button("Reintentar") {
                Task { await serverManager.start() }
            }
            Button("Salir", role: .destructive) {
                NSApp.terminate(nil)
            }
        } message: {
            Text("El servidor no respondió en 15 segundos. Revisa que la API key es correcta en Configuración (⌘,).")
        }
    }
}
