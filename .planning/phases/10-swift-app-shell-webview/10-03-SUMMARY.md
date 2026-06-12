# Plan 10-03 — SUMMARY
## Keychain: API keys seguras

**Estado:** COMPLETADO  
**Fecha:** 2026-06-08

---

## Archivos creados / modificados

| Archivo | Estado |
|---------|--------|
| `macos/MDTranslator/MDTranslator/KeychainManager.swift` | NUEVO |
| `macos/MDTranslator/MDTranslator/SettingsView.swift` | NUEVO |
| `macos/MDTranslator/MDTranslator/ServerManager.swift` | MODIFICADO (inyección Keychain en `start()`) |
| `macos/MDTranslator/MDTranslator/SplashView.swift` | MODIFICADO (flujo primera ejecución) |

---

## Funcionalidades implementadas

### KeychainManager (Security.framework)
- `save(account:value:)` — SecItemUpdate primero; si `errSecItemNotFound`, SecItemAdd. Vacío → elimina la entrada.
- `load(account:)` → `String?` — SecItemCopyMatching, retorna nil si no existe.
- `delete(account:)` — silencioso si no existe.
- `hasAnyKey: Bool` — true si `OPENAI_API_KEY` o `DEEPL_API_KEY` están guardadas.
- Cuentas gestionadas: `OPENAI_API_KEY`, `DEEPL_API_KEY`, `TRANSLATION_PROVIDER`.
- Service: `com.edefrutos.md-translator`.

### SettingsView
- `SecureField` para ambas API keys (contenido enmascarado).
- Picker segmentado OpenAI / DeepL.
- Botón "Guardar" deshabilitado si ambos campos están vacíos.
- Al guardar: publica `Notification.Name.settingsSaved` → desbloquea SplashView en primera ejecución.
- Alert de confirmación tras guardar con éxito.
- Error de Keychain mostrado inline sobre los botones.
- `#Preview` funcional.

### ServerManager.start() — inyección de keys
```swift
if let key = KeychainManager.load(account: KeychainManager.openAIKeyAccount) {
    env["OPENAI_API_KEY"] = key
}
// ídem DEEPL_API_KEY y TRANSLATION_PROVIDER
```
Las keys se inyectan en `p.environment` — **nunca en `p.arguments` ni en logs**.

### SplashView — flujo primera ejecución
- Comprueba `KeychainManager.hasAnyKey` antes de llamar `serverManager.start()`.
- Si no hay keys: publica `.openSettings` → espera `.settingsSaved` via `AsyncSequence`.
- 400ms de pausa tras el guardado para que el sheet se cierre antes del arranque.
- Mensaje del alert de error actualizado: sugiere revisar Configuración (⌘,).

---

## Garantías de seguridad

- Las API keys nunca se escriben en disco fuera del Keychain.
- Las keys no aparecen en `md-translator-server.log` (uvicorn no loguea variables de entorno).
- `SecureField` impide que las keys sean visibles en la UI de configuración.
- En Phase 12 (App Store): añadir entitlement `keychain-access-groups` y revisar `kSecAttrAccessGroup`.

---

## Criterios de aceptación

- [x] `KeychainManager.swift` creado con save/load/delete/hasAnyKey
- [x] `SettingsView.swift` creado con SecureField y picker de proveedor
- [x] Keys inyectadas en `ServerManager.start()` desde Keychain
- [x] Primera ejecución: SettingsView abierto antes de arrancar uvicorn
- [x] Notificación `.settingsSaved` publicada al guardar
- [x] Keys nunca en logs ni argumentos CLI
