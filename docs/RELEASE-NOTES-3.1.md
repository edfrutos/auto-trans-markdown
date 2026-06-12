# MD Translator 3.1 — Native macOS Polish

App nativa para macOS que traduce archivos Markdown preservando el formato y los bloques de código. Backend Python embebido (no requiere instalar nada más), proveedores OpenAI o DeepL.

## Novedades en 3.1

### Integración macOS de primera clase

- **Dock**: arrastra uno o varios `.md` al icono del Dock — un archivo se abre en el editor, varios lanzan traducción en lote. Durante traducciones largas el icono muestra una barra de progreso.
- **Open Recent**: menú `Archivo > Abrir reciente` con los últimos 10 archivos.
- **Drag & drop**: suelta archivos `.md` directamente sobre la ventana para cargarlos en el editor.
- **Services**: selecciona texto en cualquier app → menú Services → "Traducir con MDTranslator" — el resultado queda en el portapapeles.

### Teclado y flujo de trabajo

- **Atajo global `⌥⇧T`** (configurable): trae MDTranslator a primer plano desde cualquier app con el cursor en el editor.
- **`⌘↩`** lanza la traducción desde el editor; **`⌘⇧C`** copia el resultado.
- **`⌘Z` / `⌘⇧Z`** funcionan dentro del editor.
- **Estimación de coste en vivo**: tokens y coste aproximado se actualizan mientras escribes o pegas.

### Rendimiento y calidad

- Bundle de Python reducido de ~200 MB a **116 MB**.
- Arranque en frío optimizado (objetivo < 5 s en Apple Silicon).
- Crash reporter opcional (Sparkle) y smoke test automatizado del backend.

## Requisitos

- macOS 14.0 (Sonoma) o superior · Apple Silicon
- Una API key de OpenAI o DeepL (se guarda en el Keychain, nunca en disco)

## Instalación

1. Descarga `MDTranslator-3.1.dmg`, ábrelo y arrastra la app a `Aplicaciones`.
2. **Primera apertura** (la app no está notarizada por Apple): clic **derecho** sobre MDTranslator.app → **Abrir** → confirmar. Solo es necesario una vez.
   - Alternativa por terminal: `xattr -dr com.apple.quarantine /Applications/MDTranslator.app`
3. Configura tu API key en `MD Translator → Configuración…` (`⌘,`).

Instrucciones completas en el `INSTALL.txt` incluido en el DMG.

## Verificación de integridad

Comprueba el SHA-256 del DMG descargado contra el publicado en la release:

```bash
shasum -a 256 MDTranslator-3.1.dmg
```

## Actualizaciones

La app comprueba actualizaciones automáticamente (Sparkle, firma EdDSA). Quienes tengan la 3.0 recibirán aviso de esta versión.

## Problemas conocidos

- Sin notarización de Apple: requiere el paso de clic derecho → Abrir en la primera ejecución.
- Solo Apple Silicon (arm64); no hay build Intel.
- El progreso de lote en la app nativa es indeterminado (SSE granular pendiente).

## Soporte

Incidencias: https://github.com/edfrutos/auto-trans-markdown/issues
