# Plan 12-02 — Sparkle Auto-Update

## Objetivo
Integrar Sparkle 2.x para que la app compruebe actualizaciones automáticamente y ofrezca el ítem
"Buscar actualizaciones…" en el menú. Usa firma EdDSA (independiente de notarización).

## Archivos a crear/modificar

| Archivo | Acción |
|---------|--------|
| `macos/MDTranslator/MDTranslator/UpdateManager.swift` | Nuevo — wrapper SPUUpdater |
| `macos/MDTranslator/MDTranslator/Commands.swift` | Añadir "Buscar actualizaciones…" |
| `macos/MDTranslator/MDTranslator/MDTranslatorApp.swift` | Inicializar UpdateManager en `@main` |
| `macos/MDTranslator/MDTranslator/Info.plist` | Añadir `SUFeedURL` y `SUPublicEDKey` |
| `docs/appcast.xml` | Nuevo — plantilla de appcast para publicar releases |

## Pasos manuales en Xcode (una vez)
1. File → Add Package Dependencies → `https://github.com/sparkle-project/Sparkle` → versión `2.9.2`
2. Target → Frameworks, Libraries → añadir `Sparkle.framework`
3. Generar claves EdDSA: `./bin/generate_keys` (incluido en Sparkle) → copiar clave pública a `SUPublicEDKey` en Info.plist

## UpdateManager.swift
```swift
import Sparkle

@MainActor
final class UpdateManager {
    static let shared = UpdateManager()
    private let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
```

## Info.plist additions
```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/edefrutos/auto-trans-markdown/main/docs/appcast.xml</string>
<key>SUPublicEDKey</key>
<string><!-- PEGAR CLAVE PÚBLICA EdDSA AQUÍ --></string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

## appcast.xml template
```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MD Translator</title>
    <link>https://github.com/edefrutos/auto-trans-markdown</link>
    <language>es</language>
    <item>
      <title>MD Translator 3.0</title>
      <pubDate>Mon, 08 Jun 2026 18:00:00 +0000</pubDate>
      <sparkle:version>3.0</sparkle:version>
      <sparkle:shortVersionString>3.0</sparkle:shortVersionString>
      <enclosure
        url="https://github.com/edefrutos/auto-trans-markdown/releases/download/v3.0/MDTranslator.dmg"
        length="0"
        type="application/octet-stream"
        sparkle:edSignature="FIRMA_AQUÍ"
      />
    </item>
  </channel>
</rss>
```

## Firma del DMG (tras Plan 12-01)
```bash
./bin/sign_update MDTranslator.dmg
# Pegar sparkle:edSignature en appcast.xml
```

## Notas
- `SUFeedURL` apunta a `docs/appcast.xml` en `main` — necesita ser público en GitHub
- Sin notarización: los usuarios deben hacer clic derecho → Abrir la primera vez
- `SPUStandardUpdaterController(startingUpdater: true)` lanza el check en background al arrancar
