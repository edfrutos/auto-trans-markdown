# Plan 12-01 — DMG + Codesign ad-hoc

## Objetivo
Script reproducible que genera `MDTranslator.dmg` listo para distribuir sin Apple Developer account.
Firma ad-hoc (`--sign -`) para que el .app pase la verificación básica de Gatekeeper (clic derecho → Abrir).

## Archivos a crear/modificar

| Archivo                       | Acción                                                                      |
| ----------------------------- | --------------------------------------------------------------------------- |
| `scripts/build-app.sh`        | Nuevo — build completo: xcodebuild archive → export → codesign → create-dmg |
| `scripts/exportOptions.plist` | Nuevo — configuración export ad-hoc sin provisioning profile                |
| `BUILDING.md`                 | Nuevo — instrucciones completas para reproducir el build                    |

## Pasos del script `build-app.sh`

1. `xcodebuild -scheme MDTranslator -configuration Release archive -archivePath build/MDTranslator.xcarchive`
2. `xcodebuild -exportArchive -archivePath build/MDTranslator.xcarchive -exportPath build/export -exportOptionsPlist scripts/exportOptions.plist`
3. `codesign --deep --force --sign - build/export/MDTranslator.app`
4. Verificar: `codesign --verify --deep --strict build/export/MDTranslator.app`
5. `create-dmg --volname "MD Translator" --window-size 660 400 --icon-size 128 --icon "MDTranslator.app" 180 170 --hide-extension "MDTranslator.app" --app-drop-link 480 170 "build/MDTranslator.dmg" "build/export/"`
6. Print SHA-256 del .dmg (para el appcast de Sparkle en Plan 12-02)

## exportOptions.plist
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>ad-hoc</string>
</dict>
</plist>
```

## Prerequisitos (del usuario)

- `create-dmg` instalado: `brew install create-dmg`
- Xcode command-line tools: `xcode-select --install`
- App Sandbox desactivado (ya configurado en Phase 9)

## Gatekeeper — instrucciones para el usuario final
```text
Clic derecho en MDTranslator.app → Abrir → Abrir (confirmar)
```
O en terminal: `xattr -dr com.apple.quarantine MDTranslator.app`
