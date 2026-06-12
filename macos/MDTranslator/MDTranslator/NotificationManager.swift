// NotificationManager.swift — Notificaciones macOS via UserNotifications.
// Envía banners cuando una traducción termina, especialmente útil con la app en segundo plano.
import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    /// Solicita permiso al usuario para mostrar notificaciones.
    /// Llamar una vez al arranque — macOS recuerda la decisión del usuario.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in
            // No es necesario manejar el resultado: si el usuario deniega,
            // simplemente no se envían notificaciones (sin error visible).
        }
    }

    /// Envía una notificación genérica con título y cuerpo personalizados.
    func send(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// Envía una notificación de traducción completada.
    /// - Parameters:
    ///   - filename: Nombre del archivo traducido (ej: "documento_es.md")
    ///   - langs: Idioma(s) destino separados por coma (ej: "es, fr")
    func sendTranslationDone(filename: String, langs: String) {
        // Comprobar autorización antes de enviar.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Traducción completada"
            content.body  = langs.isEmpty ? filename : "\(filename) → \(langs)"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil  // Inmediata
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
