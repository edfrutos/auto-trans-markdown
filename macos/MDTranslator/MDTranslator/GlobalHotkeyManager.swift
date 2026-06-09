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
    /// Si falta el permiso de Accesibilidad publica `hotkeyNeedsAccessibility`.
    func register() {
        guard globalMonitor == nil else { return }

        // Monitor local: siempre activo, no requiere Accesibilidad.
        // Permite probar el atajo con MDTranslator en primer plano.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.isHotKey(event) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .globalHotkeyActivate, object: nil)
                }
            }
            return event  // no consumir el evento
        }

        guard AXIsProcessTrusted() else {
            NotificationCenter.default.post(name: .hotkeyNeedsAccessibility, object: nil)
            return
        }

        // Monitor global: eventos de cualquier otra app.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard self.isHotKey(event) else { return }
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

    /// Abre Ajustes del Sistema en la pantalla de Accesibilidad.
    func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    /// Solicita el permiso mostrando el diálogo del sistema (solo si no está concedido).
    func requestAccessibilityIfNeeded() {
        guard !isAccessibilityGranted else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }
}
