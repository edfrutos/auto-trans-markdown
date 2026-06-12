// GlobalHotkeyManager.swift — Hotkey global ⌥⇧M para activar MDTranslator desde cualquier app.
// Usa NSEvent.addGlobalMonitorForEvents (Cocoa), que requiere permiso de Accesibilidad.
// Phase 14: HOTKEY-01.
import AppKit

// MARK: - Notifications

extension Notification.Name {
    /// Publicada cuando el usuario pulsa ⌥⇧M desde cualquier app.
    static let globalHotkeyActivate = Notification.Name("globalHotkeyActivate")
    /// Publicada cuando falta el permiso de Accesibilidad para el hotkey.
    static let hotkeyNeedsAccessibility = Notification.Name("hotkeyNeedsAccessibility")
}

// MARK: - Manager

/// Registra y gestiona el hotkey global ⌥⇧M.
/// Requiere permiso de Accesibilidad en Ajustes del Sistema → Privacidad → Accesibilidad.
@MainActor
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    /// Monitor global — eventos de otras apps (requiere Accesibilidad).
    private var globalMonitor: Any?
    /// Monitor local — eventos cuando MDTranslator es la app en primer plano.
    private var localMonitor: Any?

    private init() {}

    // MARK: - Registro

    /// Intenta registrar el hotkey global ⌥⇧M.
    /// Es idempotente: puede llamarse varias veces sin duplicar monitores.
    /// - El monitor local se crea una sola vez (no requiere Accesibilidad).
    /// - El monitor global se crea cuando AX está concedida y aún no existe.
    ///   Llamar cuando la app se activa permite registrarlo justo después de que
    ///   el usuario conceda el permiso sin necesidad de reiniciar la app.
    func register() {
        // Monitor local: siempre activo, no requiere Accesibilidad.
        // Solo se crea una vez — guard evita duplicados.
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if self.isHotKey(event) {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .globalHotkeyActivate, object: nil)
                    }
                }
                return event  // no consumir el evento
            }
        }

        // Monitor global: requiere Accesibilidad. Solo se crea si AX está concedida y aún no existe.
        // Si AX no está concedida, publicar notificación para que la UI muestre el banner.
        guard globalMonitor == nil else { return }
        guard AXIsProcessTrusted() else {
            NotificationCenter.default.post(name: .hotkeyNeedsAccessibility, object: nil)
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isHotKey(event) else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .globalHotkeyActivate, object: nil)
            }
        }
    }

    /// Libera todos los monitores.
    func unregister() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor  = nil }
    }

    // MARK: - Detección del hotkey

    /// `true` si el evento es ⌥⇧M sin Cmd ni Ctrl.
    /// Usa `.contains` en lugar de igualdad exacta para ignorar flags extra
    /// como `.function` o `.numericPad` que algunos teclados añaden.
    private func isHotKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 46 else { return false }          // kVK_ANSI_M
        let f = event.modifierFlags
        return f.contains(.option)
            && f.contains(.shift)
            && !f.contains(.command)
            && !f.contains(.control)
    }

    // MARK: - Permiso de Accesibilidad

    /// `true` si el permiso de Accesibilidad está concedido.
    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Muestra el diálogo nativo del sistema para conceder Accesibilidad,
    /// y abre Ajustes del Sistema como fallback por si el diálogo no aparece.
    /// Más fiable que navegar directamente con una URL (los deep-links de
    /// x-apple.systempreferences cambian entre versiones de macOS).
    func openAccessibilitySettings() {
        // 1. Diálogo nativo "MDTranslator quiere controlar este ordenador" —
        //    la forma más directa: el usuario activa el toggle en el mismo diálogo.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(opts as CFDictionary)

        // 2. Abrir Ajustes del Sistema como fallback para que el usuario
        //    pueda encontrar la sección manualmente si el diálogo no aparece.
        //    Intentar varias URLs para compatibilidad macOS 13 / 14 / 15 / 26.
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for str in candidates {
            if let url = URL(string: str) {
                NSWorkspace.shared.open(url)
                break
            }
        }
    }

    /// Solicita el permiso mostrando el diálogo del sistema (solo si no está concedido).
    func requestAccessibilityIfNeeded() {
        guard !isAccessibilityGranted else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }
}
