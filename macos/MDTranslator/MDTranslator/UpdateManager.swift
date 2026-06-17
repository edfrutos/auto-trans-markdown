// UpdateManager.swift — Integración con Sparkle 2.x para auto-actualización.
// SPUStandardUpdaterController gestiona comprobaciones automáticas en el arranque
// (SUEnableAutomaticChecks en Info.plist) y comprobaciones manuales desde el menú.
// El feed URL se configura en Info.plist → SUFeedURL.
// Phase 15 CRASH-01: SPUUpdaterDelegate para vincular el envío del perfil de sistema
//   con la preferencia de diagnóstico del usuario.
// Phase 22 SPARK-02/03: activate() fuerza la inicialización del updater al arrancar la app
//   para que SUEnableAutomaticChecks surta efecto. didFindValidUpdate postea
//   .sparkleUpdateAvailable para mostrar el badge en el menú bar (SPARK-03).
import AppKit
import Sparkle

extension Notification.Name {
    /// Posteada cuando Sparkle encuentra una actualización válida disponible (SPARK-03).
    static let sparkleUpdateAvailable = Notification.Name("sparkleUpdateAvailable")
}

/// Wrapper @MainActor sobre SPUStandardUpdaterController.
/// Se inicializa una única vez (singleton) al primer acceso desde el hilo principal.
@MainActor
final class UpdateManager: NSObject {

    static let shared = UpdateManager()

    // lazy var permite pasar `self` como updaterDelegate sin captura antes de init completo.
    // El primer acceso a updaterController siempre ocurre desde @MainActor, así que
    // la inicialización lazy es segura con respecto a la aislación de actores.
    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,       // CRASH-01 + SPARK-03: delegate para shouldSendSystemProfile y didFindValidUpdate
            userDriverDelegate: nil
        )
    }()

    override private init() { super.init() }

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

    /// SPARK-02: Inicializa el updaterController (lazy) en el arranque de la app para que
    /// SUEnableAutomaticChecks (Info.plist) arranque las comprobaciones periódicas.
    /// Sin esta llamada, Sparkle no comprueba hasta que el usuario abre el menú.
    func activate() {
        _ = updaterController
    }
}

// MARK: - SPUUpdaterDelegate (CRASH-01 + SPARK-03)

// El delegate controla:
//   - si Sparkle puede enviar el perfil anónimo del sistema (CRASH-01)
//   - notificación cuando hay actualización disponible para el badge del menú bar (SPARK-03)
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

    /// SPARK-03: Llamado cuando Sparkle encuentra una versión más nueva en el appcast.
    /// MDTranslatorApp escucha .sparkleUpdateAvailable para mostrar el badge en el menú bar.
    nonisolated
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sparkleUpdateAvailable, object: nil)
        }
    }
}
