// KeychainManager.swift — Wrapper de Security.framework para almacenar API keys.
// Gestiona OPENAI_API_KEY, DEEPL_API_KEY y TRANSLATION_PROVIDER en el Keychain del usuario.
// Las keys NUNCA deben aparecer en logs ni argumentos CLI.
import Foundation
import Security

enum KeychainManager {
    /// Service identifier — debe coincidir con el Bundle ID de la app.
    static let service = "com.edefrutos.md-translator"

    // MARK: - Keys gestionadas

    static let openAIKeyAccount  = "OPENAI_API_KEY"
    static let deepLKeyAccount   = "DEEPL_API_KEY"
    static let providerAccount      = "TRANSLATION_PROVIDER"
    /// PREF-03: URL base alternativa para OpenAI (Ollama, Azure, proxy). Guardada en Keychain
    /// porque puede contener credenciales embebidas (http://user:pass@host/v1).
    static let openAIBaseURLAccount = "OPENAI_BASE_URL"

    // MARK: - API pública

    /// Guarda un valor en el Keychain para la cuenta dada.
    /// Borra siempre el item existente antes de recrearlo, para garantizar
    /// que el ACL sea abierto (SecAccessCreate con trustedApps = nil).
    /// SecItemUpdate no cambia el ACL de un item ya existente: si el item
    /// fue creado por un binario distinto (otro path de build), seguiría
    /// prompting al leer desde el nuevo binario aunque el valor sea el mismo.
    static func save(account: String, value: String) throws {
        guard !value.isEmpty else {
            delete(account: account)
            return
        }
        let data = Data(value.utf8)

        // Borrar el item anterior para poder recrear con ACL abierto.
        delete(account: account)

        // Crear con ACL abierto (trustedApps = nil → cualquier binario lee sin prompt).
        // SecAccessCreate está deprecated desde macOS 10.10 pero es la única vía
        // sin kSecUseDataProtectionKeychain, que requiere entitlements no disponibles
        // con "Sign to Run Locally". El warning de compilación es esperado.
        var access: SecAccess?
        SecAccessCreate("\(service).\(account)" as CFString, nil, &access)   // deprecated OK

        var addQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data
        ]
        if let acc = access { addQuery[kSecAttrAccess] = acc }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Lee un valor del Keychain para la cuenta dada. Retorna nil si no existe.
    static func load(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Elimina la entrada del Keychain para la cuenta dada (silenciosamente si no existe).
    static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// True si al menos una API key está guardada (OpenAI o DeepL).
    static var hasAnyKey: Bool {
        load(account: openAIKeyAccount) != nil || load(account: deepLKeyAccount) != nil
    }

    // MARK: - Errores

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Error al guardar en Keychain (OSStatus \(status))"
            }
        }
    }
}
// Appended at build time — do not duplicate manually
