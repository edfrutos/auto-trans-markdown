# Compilar MD Translator v3.1

Instrucciones para generar `MDTranslator.app` y `MDTranslator.dmg` desde el código fuente.

## Prerequisitos

| Herramienta | Versión mínima | Instalación |
|-------------|----------------|-------------|
| macOS | 14.0 Sonoma | — |
| Xcode | 15.x o superior | App Store |
| Command Line Tools | — | `xcode-select --install` |
| create-dmg | 1.2+ | `brew install create-dmg` |
| uv | 0.5+ | `brew install uv` |

## 1. Clonar y preparar el entorno Python

```bash
git clone https://github.com/edfrutos/auto-trans-markdown.git
cd auto-trans-markdown

# Instalar dependencias Python
uv sync

# Generar el bundle CPython portable (ejecutar UNA sola vez, ~5 min)
./scripts/build-python-bundle.sh
```

El script descarga CPython 3.11.15 (python-build-standalone) e instala todas las dependencias
en `python-bundle/`. Este directorio está gitignored (~116 MB tras la optimización de la Phase 15).

## 2. Configuración de Xcode (primera vez)

Abrir `macos/MDTranslator/MDTranslator.xcodeproj` y verificar:

| Setting | Valor requerido |
|---------|-----------------|
| Deployment Target | macOS 14.0 |
| App Sandbox | **Eliminado** (incompatible con subprocess) |
| User Script Sandboxing | No |
| Signing Certificate | Sign to Run Locally |
| Info.plist File | `MDTranslator/Info.plist` |
| "Based on dependency analysis" (Run Script) | **Desactivado** |

El **Run Script phase** ("Copy Python Bundle & Backend") copia `python-bundle/` y `src/` a
`Resources/` dentro del bundle de la app en cada build.

## 3. Build de desarrollo (Xcode)

```
⌘B  — compilar
⌘R  — compilar y ejecutar
```

La app arranca en `http://127.0.0.1:<puerto_libre>` y abre la UI web en un WKWebView.
Las API keys se configuran desde el menú **MD Translator → Configuración…** (⌘,).

## 4. Build de distribución (DMG)

**Ruta canónica (Phase 12):**

```bash
make dmg
```

El target:
1. `xcodebuild archive` (Release, arm64) — genera `build/MDTranslator.xcarchive`
2. Firma ad-hoc (`codesign --force --sign -`)
3. ZIP para Sparkle (`build/MDTranslator-3.1.zip`)
4. DMG con alias a `/Applications` e `INSTALL.txt` (`build/MDTranslator-3.1.dmg`)
5. Imprime y guarda el SHA-256 del DMG (`.dmg.sha256`)

Alternativa con `create-dmg` (ventana con layout): `./scripts/build-app.sh`.

> ⚠️ Si el `.app` resultante no contiene `Contents/Resources/python/`, el Run Script
> de Xcode no se ejecutó en el build CLI. Solución: compilar una vez desde Xcode (⌘B)
> o verificar que "Based on dependency analysis" está desactivado en el Run Script.

## 5. Auto-update con Sparkle

```bash
make appcast
```

Firma el ZIP con la clave EdDSA privada y muestra `edSignature` + `length` + `url`.
Copiar esos valores al `<enclosure>` del item correspondiente en `docs/appcast.xml`,
subir el ZIP a GitHub Releases (tag `vX.Y`) y hacer push de `docs/appcast.xml` a `main`.
La app comprueba actualizaciones al arrancar vía el feed configurado en `SUFeedURL`.

## 6. Distribución sin notarización

La app distribuida requiere que el usuario final ejecute uno de estos pasos **una sola vez**:

```bash
# Opción A — interfaz gráfica
# Clic derecho en MDTranslator.app → Abrir → Abrir (confirmar en el diálogo)

# Opción B — terminal
xattr -dr com.apple.quarantine /Applications/MDTranslator.app
```

## Estructura del bundle

```
MDTranslator.app/
└── Contents/
    ├── MacOS/MDTranslator        — ejecutable Swift
    └── Resources/
        ├── python/               — CPython 3.11 portable
        │   └── bin/python3
        └── backend/              — src/ + pyproject.toml
            └── src/main.py       — FastAPI app (arrancada como subprocess)
```

## Tests del backend Python

```bash
pytest tests/ -q        # suite completa (148 tests)
```
