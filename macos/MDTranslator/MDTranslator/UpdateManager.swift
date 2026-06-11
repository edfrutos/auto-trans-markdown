// UpdateManager.swift — Integración con Sparkle 2.x para auto-actualización.
// SPUStandardUpdaterController gestiona comprobaciones automáticas en el arranque
// (SUEnableAutomaticChecks en Info.plist) y comprobaciones manuales desde el menú.
// El feed URL se configura en Info.plist → SUFeedURL.
// Phase 15 CRASH-01: SPUUpdaterDelegate para vincular el envío del perfil de sistema
// con la preferencia de diagnóstico del usuario.
import AppKit
import Sparkle

/// Wrapper @MainActor sobre SPUStandardUpdaterController.
/// Se inicializa una única vez (singleton) al primer acceso desde el hilo principal.
@MainActor
final class UpdateManager {

    static let shared = UpdateManager()

    // lazy var permite pasar `self` como updaterDelegate sin captura antes de init completo.
    // El primer acceso a updaterController siempre ocurre desde @MainActor, así que
    // la inicialización lazy es segura con respecto a la aislación de actores.
    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,       // CRASH-01: delegar para shouldSendSystemProfile
            userDriverDelegate: nil
        )
    }()

    private init() {}

    // MARK: - API pública

    /// Refleja SPUUpdater.canCheckForUpdates — controla si el ítem de menú está activo.
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    /// Comprobación manual disparada desde "Buscar actualizaciones…" (⌘ menú App).
    /// Sparkle muestra su UI estándar: "Comprobando…" → alerta si hay versión nueva.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate (CRASH-01)

// El delegate controla si Sparkle puede enviar el perfil anónimo del sistema
// (versión de macOS, hardware) junto con cada comprobación de actualizaciones.
// El usuario opt-in mediante la preferencia "Enviar informes de diagnóstico"
// en Configuración → Privacidad.
extension UpdateManager: SPUUpdaterDelegate {
    nonisolated
    func updater(
        _ updater: SPUUpdater,
        shouldSendSystemProfile systemProfile: [[String: AnyHashable]]
    ) -> Bool {
        // Leer la preferencia en el hilo principal (shouldSendSystemProfile puede
        // llamarse desde un hilo background de Sparkle; assumeIsolated es seguro
        // porque Sparkle lo invoca sólo desde el runloop principal).
        MainActor.assumeIsolated {
            CrashReporterManager.shared.sendCrashReports
        }
    }
}
