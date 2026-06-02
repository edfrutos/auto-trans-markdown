# Domain Pitfalls — macOS Native App con Python Embebido

**Domain:** App macOS nativa SwiftUI + backend Python/FastAPI embebido + firma ad-hoc  
**Project:** MarkDown Auto Translator v3.0  
**Researched:** 2026-06-02  
**Overall confidence:** HIGH (patrones documentados de distribución macOS sin Developer Program, python-build-standalone, subprocess management, Keychain, Sparkle)

---

## Critical Pitfalls

Errores que causan que la app no arranque, se bloquee por Gatekeeper, exponga secretos o requiera reescritura de arquitectura.

---

### Pitfall C-1: Quarantine xattr bloquea el intérprete Python embebido

**Severity:** CRÍTICO

**What goes wrong:** macOS aplica el atributo extendido `com.apple.quarantine` a todo lo descargado por el navegador o recibido por AirDrop/Mail. Cuando la app arranca e intenta ejecutar el binario Python dentro del bundle, Gatekeeper lo bloquea silenciosamente o lanza un diálogo «no se puede abrir» que **no menciona Python** — el usuario ve un crash de la app sin mensaje útil.

**Why it happens:** python-build-standalone distribuye `python3.XX` como un binario Mach-O independiente. Al estar dentro de `Contents/Resources/python/bin/`, hereda el quarantine del `.dmg` padre. La firma ad-hoc no es suficiente para satisfacer Gatekeeper en macOS 12+: se requiere `--options runtime` o eliminar el atributo explícitamente.

**Consequences:** La app llega al usuario y no arranca. Diagnóstico imposible desde la UI. Reportes de crash sin información útil.

**Prevention:**
- En el script de build, tras copiar python-build-standalone al bundle, ejecutar:
  ```bash
  xattr -cr MyApp.app
  codesign --force --deep --sign - MyApp.app
  ```
- Al crear el DMG, firmar el `.dmg` también con `codesign --sign -`.
- Añadir `NSPrincipalClass` y `LSMinimumSystemVersion` en `Info.plist` para evitar activación de paths de seguridad adicionales.
- Documentar en README del proyecto: el usuario que descarga manualmente puede necesitar ejecutar `xattr -d com.apple.quarantine MyApp.dmg` si el diálogo aparece.

**Detection (warning signs):**
- Crash en arranque sin llegar a `AppDelegate.applicationDidFinishLaunching`.
- Consola macOS muestra `AMFI: ... is not allowed to run` o `killed: 9`.
- `xattr -l MyApp.app/Contents/Resources/python/bin/python3.XX` devuelve `com.apple.quarantine`.

**Phase:** Fase de packaging (Phase 12 / distribución). Validar también en Phase 9 (embedding Python).

---

### Pitfall C-2: Paths absolutos hardcodeados en python-build-standalone

**Severity:** CRÍTICO

**What goes wrong:** python-build-standalone compila rutas absolutas de `sys.prefix`, `sys.exec_prefix` y la ubicación de la stdlib en el propio binario. Si el bundle se instala en `/Applications/MyApp.app` pero el build se hizo en `/tmp/build/python/`, Python no encuentra su stdlib y falla con `ModuleNotFoundError: No module named 'encodings'` al arrancar el intérprete — incluso antes de importar FastAPI.

**Why it happens:** CPython usa rutas en tiempo de compilación para localizar `lib/pythonX.Y/`. python-build-standalone usa `PYTHONHOME` y la ruta relativa al ejecutable para resolverlas, pero solo funciona si el layout `bin/python3.XX` → `../lib/pythonX.Y/` se preserva intacto.

**Consequences:** El subprocess Python nunca arranca. Error críptico en log. App inutilizable.

**Prevention:**
- Usar la variante **"relocatable"** de python-build-standalone (releases marcados `+20XXXXXX` con soporte `PYTHONHOME`).
- Establecer `PYTHONHOME` y `PYTHONPATH` en el entorno del subprocess apuntando a rutas dentro del bundle:
  ```swift
  let bundlePath = Bundle.main.bundlePath
  env["PYTHONHOME"] = "\(bundlePath)/Contents/Resources/python"
  env["PYTHONPATH"] = "\(bundlePath)/Contents/Resources/python/lib/python3.XX/site-packages"
  ```
- Verificar en CI que el bundle funciona en una ruta diferente a la de build (test en directorio temporal).
- Nunca hardcodear rutas `/Users/developer/...` en `requirements.txt` instalados dentro del bundle.

**Detection:**
- `python3 -c "import encodings"` falla desde la ruta del bundle.
- Log del subprocess contiene `Fatal Python error: init_sys_streams` o `can't open file 'bootstrap.py'`.

**Phase:** Phase 9 (embedding). Resolver antes de integrar FastAPI.

---

### Pitfall C-3: Procesos zombie de Python al cerrar la app

**Severity:** CRÍTICO

**What goes wrong:** Si Swift no llama explícitamente a `terminate()` + `waitForExit()` antes de que el proceso padre finalice, el subprocess Python queda como zombie. En reaperturas posteriores, el puerto está ocupado (tipicamente `8000`) y la app lanza un nuevo subprocess que también falla al bind, resultando en múltiples procesos zombie acumulados entre sesiones.

**Why it happens:** `NSTask` / `Process` en Swift no envía SIGTERM automáticamente al proceso hijo cuando el padre termina. Además, `applicationWillTerminate` tiene un timeout muy corto (~5s) en macOS; si la llamada a `terminate()` bloquea esperando que FastAPI drene las conexiones, la app se mata antes de completar la limpieza.

**Consequences:** Puerto permanentemente bloqueado. La app no arranca tras la primera sesión o tras un crash. Proceso Python consumiendo RAM/CPU en segundo plano.

**Prevention:**
- Registrar el subprocess en `AppDelegate` y llamar en `applicationWillTerminate`:
  ```swift
  pythonProcess.terminate()
  pythonProcess.waitUntilExit()  // máximo 2s con DispatchSemaphore timeout
  ```
- Usar `kill(pid, SIGKILL)` si `waitUntilExit` excede el timeout.
- Al arrancar, hacer un bind-check del puerto antes de lanzar el subprocess:
  ```swift
  if isPortInUse(8000) { killProcessOnPort(8000) }
  ```
- Almacenar el PID en `UserDefaults` para matar procesos huérfanos de sesiones anteriores.
- Elegir un puerto aleatorio libre en cada sesión (evita conflictos permanentes).

**Detection:**
- `lsof -i :8000` muestra proceso `python3` sin padre (`PPID=1`).
- La app tarda >10s en arrancar tras un crash previo.
- `ps aux | grep python` muestra múltiples instancias.

**Phase:** Phase 10 (subprocess management). Implementar desde el primer día de integración.

---

### Pitfall C-4: Gatekeeper bloquea librerías `.dylib` dentro del bundle

**Severity:** CRÍTICO

**What goes wrong:** python-build-standalone incluye decenas de `.dylib` (OpenSSL, libffi, sqlite3, etc.) y `.so` de extensiones C (como `_ssl.cpython-3XX.so`). Aunque se firme el ejecutable Python, Gatekeeper verifica **cada** binario Mach-O del bundle de forma independiente. Una sola `.dylib` sin firmar bloquea la ejecución con `Library validation failed`.

**Why it happens:** La firma `--deep` de `codesign` no siempre alcanza archivos en subdirectorios no estándar. Las rutas `lib/pythonX.Y/lib-dynload/*.so` y `lib/*.dylib` no son paths que Xcode gestiona automáticamente.

**Consequences:** Crash en import de módulos que usan C extensions (`ssl`, `sqlite3`, `hashlib`). FastAPI no arranca por falta de `ssl`. Errores intermitentes dependiendo del primer import.

**Prevention:**
- Firmar **bottom-up**: primero todas las `.dylib` y `.so`, luego los ejecutables, luego el bundle:
  ```bash
  find MyApp.app -name "*.dylib" -o -name "*.so" | \
    xargs -I{} codesign --force --sign - {}
  find MyApp.app -name "python3*" -type f | \
    xargs -I{} codesign --force --sign - {}
  codesign --force --deep --sign - MyApp.app
  ```
- Usar `codesign -vvv MyApp.app` para verificar que todos los binarios tienen firma válida.
- Automatizar en el Makefile/script de build, no hacerlo manualmente.

**Detection:**
- `codesign --verify --deep --strict MyApp.app` reporta archivos sin firma.
- Log contiene `dlopen` con `code signature invalid`.
- `spctl -a -vv MyApp.app` devuelve `rejected`.

**Phase:** Phase 12 (distribución). Pero verificar en Phase 9 con un build de prueba.

---

### Pitfall C-5: Firma ad-hoc no equivale a notarización — el usuario necesita instrucciones

**Severity:** CRÍTICO (UX / adopción)

**What goes wrong:** Con firma ad-hoc (`codesign --sign -`), la app **no pasa Gatekeeper automáticamente** en macOS 15+. El usuario verá «"MyApp.app" cannot be opened because it is from an unidentified developer» y el botón de `Abrir de todos modos` está en `Ajustes del Sistema > Privacidad y Seguridad`, no en el diálogo inicial. Muchos usuarios no saben esto y asumen que la app está rota.

**Why it happens:** Sin una Developer ID Certificate notarizada por Apple, la firma ad-hoc solo impide la alerta de «binario corrupto» pero no supera la verificación de identidad. Es por diseño de Gatekeeper.

**Consequences:** Tasa de abandono en instalación. Tickets de soporte. Percepción de app maliciosa.

**Prevention:**
- Incluir instrucciones prominentes en el DMG (archivo `INSTALL.txt` visible al montar):
  ```
  Si ves "no se puede abrir", haz clic derecho → Abrir, o ve a
  Ajustes del Sistema > Privacidad y Seguridad > Abrir de todos modos.
  ```
- Alternativamente, incluir un script de instalación que ejecute:
  ```bash
  xattr -d com.apple.quarantine /Applications/MyApp.app
  ```
- Evaluar para v3.1+: el programa Apple Developer ($99/año) permite notarización y elimina este problema completamente.
- Documentar en README el proceso de primera apertura.

**Detection:**
- Test en una VM macOS limpia sin el Developer ID del proyecto instalado como trusted.
- Verificar que `spctl --status` está en `assessments enabled` en la VM de test.

**Phase:** Phase 12 (distribución). Documentar en Phase 11 (DMG build).

---

## Moderate Pitfalls

Problemas que degradan la experiencia de desarrollo o pueden causar bugs en producción si no se anticipan.

---

### Pitfall M-1: Health check timeout demasiado corto en primera ejecución

**Severity:** MEDIO

**What goes wrong:** En la primera ejecución, Python debe importar FastAPI, uvicorn, y todas las dependencias del proyecto desde el bundle. En una máquina lenta o en un sistema de archivos cifrado (FileVault activo), esto puede tardar 3-8 segundos. Si Swift hace el health check con un timeout de 2s, asume que el subprocess falló y muestra un error al usuario, aunque Python esté arrancando correctamente.

**Why it happens:** Los timeouts de health check se calibran en la máquina del desarrollador (rápida, caché caliente). En producción hay más variabilidad.

**Consequences:** Falsos positivos de «backend no disponible». El usuario reintenta, lanza múltiples subprocesses, y aparece el Pitfall C-3 (zombies).

**Prevention:**
- Implementar retry con backoff en el health check: intentar `/api/languages` cada 500ms hasta 15s de timeout total.
- En la primera ejecución (detectar con `UserDefaults`), mostrar un indicador de progreso «Iniciando…» en lugar de un error inmediato.
- Loggear el tiempo de arranque para calibrar timeouts en CI.
- Separar el health check de «¿está vivo?» (TCP connect) del de «¿está listo?» (HTTP 200): el primero es más rápido.

**Detection:**
- Arranque en máquina con FileVault + HDD (o VM con throttling de I/O).
- Log de Swift muestra «backend failed to start» pero el proceso Python sigue en `ps`.

**Phase:** Phase 10 (subprocess management). Health check protocol desde el diseño inicial.

---

### Pitfall M-2: Tamaño del bundle explota por dependencias Python

**Severity:** MEDIO

**What goes wrong:** python-build-standalone base pesa ~70-90 MB. Al instalar FastAPI + uvicorn + openai + deepl + WeasyPrint + todas las dependencias de `requirements.txt`, el directorio `site-packages` puede llegar a 400-600 MB. El DMG resultante supera los 500 MB, lo que penaliza enormemente la descarga y el tiempo de apertura del DMG.

**Why it happens:** Los SDKs de OpenAI y DeepL traen dependencias transitivas pesadas (httpx, pydantic, certifi). WeasyPrint arrastra Cairo y Pango (200+ MB en macOS). python-build-standalone incluye test suites y archivos `.pyc` redundantes.

**Consequences:** DMG de >500 MB. Tiempo de instalación de 3-5 minutos. Rechazo por parte de usuarios en redes lentas. Sparkle updates lentos.

**Prevention:**
- Excluir WeasyPrint del bundle de la app macOS (PDF export puede ser opcional, igual que en la versión web).
- Usar `pip install --no-compile` + limpiar `__pycache__` y `*.pyc` antes de firmar.
- Eliminar archivos innecesarios de python-build-standalone:
  ```bash
  rm -rf python/lib/python3.XX/test/
  rm -rf python/lib/python3.XX/ensurepip/
  find python/ -name "*.py" -path "*/test*" -delete
  ```
- Objetivo razonable: bundle <200 MB, DMG comprimido <120 MB.
- Evaluar `uv` para instalar dependencias con resolución más agresiva de duplicados.

**Detection:**
- `du -sh MyApp.app/Contents/Resources/python/` en el script de build.
- Alerta si supera 300 MB antes de comprimir el DMG.

**Phase:** Phase 9 (embedding) + Phase 11 (DMG build).

---

### Pitfall M-3: Sparkle sin Developer ID requiere configuración especial de EdDSA

**Severity:** MEDIO

**What goes wrong:** Sparkle 2.x usa firmas EdDSA para verificar la integridad de las actualizaciones antes de instalarlas. Sin una Apple Developer ID, el desarrollador debe gestionar el par de claves EdDSA manualmente. Si se pierde la clave privada EdDSA, las actualizaciones firmadas con la clave anterior dejan de verificarse en clientes ya instalados — no hay recuperación posible sin que el usuario reinstale manualmente.

**Why it happens:** Sparkle no depende del Apple Developer Program para sus firmas de actualización. Usa su propio sistema EdDSA. Pero la documentación asume que el desarrollador tiene flujo CI establecido; sin él, la clave privada acaba en la máquina del desarrollador sin backup.

**Consequences:** Pérdida de la clave = imposibilidad de distribuir actualizaciones automáticas a usuarios existentes. Si se usa una clave diferente en un update, Sparkle rechaza la actualización silenciosamente.

**Prevention:**
- Generar el par de claves EdDSA con `generate_keys` de Sparkle **una sola vez** y guardar la clave privada en:
  1. macOS Keychain del desarrollador (no en el repo).
  2. Backup cifrado offline (1Password, Bitwarden).
- La clave pública va en `Info.plist` bajo `SUPublicEDKey` — esta sí es pública y va en el repo.
- Script de release siempre usa la misma clave: `sign_update <archivo.dmg> <clave-privada>`.
- Sparkle no requiere sandbox, pero sí requiere HTTPS para el appcast XML (`SUFeedURL`).

**Detection:**
- El instalador de Sparkle muestra «Update cannot be verified» si la firma no coincide.
- `sparkle_tool verify-update` en CI.

**Phase:** Phase 12 (distribución). Setup de claves en Phase 11.

---

### Pitfall M-4: Keychain desde app no-sandboxed — acceso sin restricciones pero sin grupo compartido

**Severity:** MEDIO

**What goes wrong:** Una app sin sandbox puede leer/escribir en el Keychain del usuario sin los permisos de `com.apple.security.keychain-access-groups` del sandbox. Esto es conveniente, pero también significa que **cualquier app en el sistema** puede leer los ítems del Keychain que no tengan ACL restrictivas. Si la app almacena `OPENAI_API_KEY` con `kSecAttrAccessible = kSecAttrAccessibleAlways`, otras apps (o malware) pueden extraer la clave.

Además, sin sandbox no hay `kSecAttrAccessGroup` automático: si en el futuro se sandboxea la app, los ítems del Keychain del período no-sandbox no son accesibles desde el nuevo contexto sandbox, rompiendo la migración.

**Why it happens:** La conveniencia de no-sandbox enmascara los controles de acceso que deberían configurarse explícitamente.

**Consequences:** API keys expuestas a otras apps. Rotura de Keychain en migración a sandbox. Posibles violaciones de ToS de OpenAI/DeepL si las claves se filtran.

**Prevention:**
- Usar `kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (más restrictivo).
- Configurar ACL explícita con `SecAccessCreate` para limitar qué apps pueden leer el ítem.
- Usar un `kSecAttrService` único y consistente (`com.autoTransMarkdown.apikeys`) para facilitar migración futura.
- Documentar en ARCHITECTURE.md que el Keychain access no está sandboxed y los riesgos asociados.

**Detection:**
- Auditar con `security find-generic-password -s "com.autoTransMarkdown.apikeys"` — si devuelve la clave sin autenticación adicional, el atributo `Accessible` es demasiado permisivo.

**Phase:** Phase 10 (Keychain integration). Definir atributos de acceso desde el primer ítem almacenado.

---

### Pitfall M-5: Variables de entorno del sistema no disponibles en el subprocess Python

**Severity:** MEDIO

**What goes wrong:** El subprocess Python arrancado desde Swift no hereda el entorno del shell del usuario. Variables como `PATH`, `HOME`, `TMPDIR`, y cualquier variable de entorno configurada en `~/.zshrc` o `~/.bash_profile` no están disponibles. Si `src/main.py` o `src/translator.py` depende de `os.getenv('HOME')` para rutas relativas o si alguna dependencia usa `PATH` para localizar binarios del sistema, el comportamiento será diferente al esperado.

**Why it happens:** Los subprocesses lanzados desde una app GUI macOS tienen un entorno mínimo del sistema, no el entorno interactivo del usuario.

**Consequences:** `load_dotenv()` falla si busca `.env` relativo a `HOME`. Rutas a `output/` no resuelven. Imports que dependen de binarios en `/usr/local/bin` (ej. Pandoc) fallan.

**Prevention:**
- Pasar un entorno explícito y completo al subprocess desde Swift:
  ```swift
  process.environment = [
      "PYTHONHOME": pythonHomePath,
      "PYTHONPATH": sitePackagesPath,
      "HOME": NSHomeDirectory(),
      "TMPDIR": NSTemporaryDirectory(),
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "OPENAI_API_KEY": keyFromKeychain,
      "DEEPL_API_KEY": keyFromKeychain,
      "TRANSLATION_PROVIDER": userPreference
  ]
  ```
- No depender de `.env` en la app macOS: las API keys vienen del Keychain vía variables de entorno inyectadas por Swift.
- Usar rutas absolutas dentro del bundle para todos los recursos Python.

**Detection:**
- El subprocess Python falla con `FileNotFoundError` para rutas relativas.
- `load_dotenv()` no encuentra el archivo y el proveedor cae en RuntimeError 503.

**Phase:** Phase 10 (subprocess management). Definir el entorno completo del proceso desde el diseño.

---

### Pitfall M-6: Conflicto de puerto al tener múltiples instancias (Finder + dock)

**Severity:** MEDIO

**What goes wrong:** El usuario abre la app dos veces (doble clic en Finder mientras ya está en el dock). macOS permite múltiples instancias de apps sin sandbox. La segunda instancia intenta lanzar FastAPI en el mismo puerto y falla silenciosamente. La UI de la segunda ventana apunta al backend de la primera instancia o a nada.

**Why it happens:** Sin `LSMultipleInstancesProhibited` en `Info.plist`, macOS no previene múltiples instancias.

**Consequences:** Segunda instancia sin backend funcional. Confusión del usuario. Puerto bloqueado si la primera instancia termina antes que la segunda.

**Prevention:**
- Añadir `LSMultipleInstancesProhibited = YES` en `Info.plist` para forzar instancia única.
- Si se permite múltiples instancias por diseño: asignar puertos dinámicos y comunicarlos a la UI.
- Implementar un mecanismo de IPC para traer al frente la instancia existente (`NSRunningApplication.activate()`).

**Detection:**
- Abrir la app dos veces desde Finder y verificar comportamiento.
- `lsof -i :8000` muestra dos procesos python escuchando.

**Phase:** Phase 10. Añadir `LSMultipleInstancesProhibited` en Phase 9 al crear el bundle inicial.

---

### Pitfall M-7: Logging del subprocess Python no visible para el usuario ni para debug

**Severity:** MEDIO

**What goes wrong:** El subprocess Python escribe logs en stdout/stderr, pero si Swift no redirige esos file descriptors, los mensajes se pierden. En producción, el usuario no ve nada. En desarrollo, el desarrollador tiene que hacer `print` statements y esperar que aparezcan en la consola de Xcode, que no siempre captura stderr de subprocesses.

**Why it happens:** `Process` en Swift solo captura stdout/stderr si se configuran explícitamente `standardOutput` y `standardError` como `Pipe`.

**Consequences:** Imposible diagnosticar crashes del backend sin re-ejecutar en terminal. Errores de traducción (502) sin contexto. Pérdida de mensajes de `logger.exception()`.

**Prevention:**
- Configurar `Pipe` para stdout y stderr del subprocess desde el primer día:
  ```swift
  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe
  // Leer asincrónicamente y escribir en un archivo de log en Application Support
  ```
- Escribir logs en `~/Library/Logs/AutoTransMarkdown/backend.log` con rotación.
- En la app, añadir una vista «Diagnóstico» que muestre las últimas 100 líneas del log.
- En desarrollo, redirigir también a `NSLog` para que aparezca en Console.app.

**Detection:**
- Un 502 desde la UI no da información sobre la causa sin logs del subprocess.
- `Console.app` → filtrar por el nombre del proceso no muestra nada del backend Python.

**Phase:** Phase 10 (subprocess). Implementar desde el primer subprocess launch, no como afterthought.

---

## Minor Pitfalls

Problemas de menor impacto que aún merecen atención en las fases correspondientes.

---

### Pitfall m-1: `PYTHONDONTWRITEBYTECODE` no configurado — `.pyc` en el bundle post-ejecución

**Severity:** BAJO

**What goes wrong:** Sin `PYTHONDONTWRITEBYTECODE=1`, Python escribe archivos `.pyc` en `__pycache__/` dentro del bundle durante la primera ejecución. Si el bundle está firmado y en `/Applications/`, esto puede fallar con `PermissionError` o invalidar la firma.

**Prevention:** Configurar `PYTHONDONTWRITEBYTECODE=1` en el entorno del subprocess. Usar un directorio de caché en `~/Library/Caches/AutoTransMarkdown/` si se necesita bytecode para rendimiento.

**Phase:** Phase 9.

---

### Pitfall m-2: Tailwind desde CDN en UI web embebida

**Severity:** BAJO

**What goes wrong:** Si la app reutiliza la UI web existente (`static/index.html`), esta carga Tailwind desde `cdn.tailwindcss.com`. Sin conexión a internet, la UI carga sin estilos. La app macOS debe funcionar offline (para edición, no para traducción).

**Prevention:** Generar un build estático de Tailwind con solo las clases utilizadas e incluirlo en el bundle. O migrar a SwiftUI nativa (objetivo principal de v3.0).

**Phase:** Phase 11 (UI SwiftUI) elimina este problema. Si hay una fase intermedia con WebView, resolver en esa fase.

---

### Pitfall m-3: `output/` ephemeral dentro del bundle — rutas de descarga rotas

**Severity:** BAJO

**What goes wrong:** El backend Python actual crea `output/` relativo al working directory. Si el subprocess se lanza con CWD dentro del bundle (read-only en `/Applications/`), la creación del directorio falla con `PermissionError`.

**Prevention:** Pasar `OUTPUT_DIR` como variable de entorno apuntando a `~/Library/Application Support/AutoTransMarkdown/output/` desde Swift.

**Phase:** Phase 10.

---

### Pitfall m-4: `reload=True` en uvicorn activado en producción

**Severity:** BAJO

**What goes wrong:** El `run()` de `src/main.py` usa `reload=True`. En el bundle, el file watcher de uvicorn monitoriza los archivos Python del bundle, consume recursos innecesarios y puede causar reinicios inesperados si el sistema modifica metadatos del bundle.

**Prevention:** Detectar si se está ejecutando dentro de un bundle (ej. `BUNDLE_ID` env var) y forzar `reload=False`. O añadir un flag `--no-reload` en el CLI.

**Phase:** Phase 10.

---

### Pitfall m-5: Auto-update Sparkle descarga a `/tmp` — antivirus / quarantine

**Severity:** BAJO

**What goes wrong:** Sparkle descarga el nuevo DMG/ZIP a un directorio temporal. En sistemas con software de seguridad activo (Malwarebytes, Sophos), la descarga puede ser interceptada o bloqueada, dejando la actualización en estado inconsistente. La app no reporta el error claramente.

**Prevention:** Implementar el handler `updater(_:didAbortWithError:)` de Sparkle para mostrar un mensaje accionable. Proporcionar URL de descarga manual como fallback.

**Phase:** Phase 12.

---

## Phase-Specific Warnings

| Phase | Tema | Pitfall más probable | Mitigación prioritaria |
|-------|------|----------------------|------------------------|
| **Phase 9** (Python embedding) | Copiar python-build-standalone al bundle | C-2 (paths), C-4 (dylib signing), M-2 (tamaño) | Variante relocatable; firma bottom-up; `rm -rf test/` |
| **Phase 10** (subprocess Swift) | Lanzar FastAPI como Process | C-1 (quarantine), C-3 (zombies), M-1 (health timeout), M-5 (entorno) | xattr clear; cleanup en applicationWillTerminate; retry health check 15s; env explícito |
| **Phase 10** (Keychain) | Almacenar API keys | M-4 (acceso Keychain) | `AccessibleWhenUnlockedThisDeviceOnly`; ACL explícita |
| **Phase 11** (SwiftUI UI) | Ventanas y lifecycle | M-6 (múltiples instancias) | `LSMultipleInstancesProhibited`; IPC para instancia única |
| **Phase 11** (logging) | Debug del backend | M-7 (logs perdidos) | Pipe stdout/stderr; log en Application Support |
| **Phase 12** (DMG/firma) | Distribución ad-hoc | C-1, C-4, C-5 | xattr -cr; firma bottom-up; instrucciones INSTALL.txt |
| **Phase 12** (Sparkle) | Auto-update sin Developer ID | M-3 (clave EdDSA) | Backup clave privada; script de release automatizado |

---

## Integration Pitfalls: Swift ↔ Python Boundary

Pitfalls específicos del punto de contacto entre los dos mundos del stack.

| Pitfall | Descripción | Severidad | Mitigación |
|---------|-------------|-----------|------------|
| **Puerto dinámico sin retry** | Swift hace GET a `:8000` antes de que Python haya hecho `bind()` | CRÍTICO | Loop de retry con backoff hasta `/api/languages` devuelve 200 |
| **Encoding de paths con espacios** | `Bundle.main.bundlePath` puede contener espacios si el usuario renombra la app; `Process.arguments` los maneja, pero concatenación de strings en shell no | MEDIO | Siempre usar arrays de argumentos, nunca `sh -c "python \(path)"` |
| **Inyección de API key en arguments** | Pasar API keys como argumentos CLI (visibles en `ps aux`) | CRÍTICO | Solo vía variables de entorno, nunca como `--api-key=sk-...` |
| **Versión de protocolo HTTP** | uvicorn por defecto acepta HTTP/1.1; la app debería usar URLSession con HTTP/1.1 explícito para evitar upgrades a HTTP/2 que añaden complejidad | BAJO | `URLSessionConfiguration.httpAdditionalHeaders["Connection"] = "keep-alive"` |
| **CORS en localhost** | Si la UI web corre en un WebView con origin `file://`, las peticiones fetch a `127.0.0.1:8000` pueden fallar por CORS | MEDIO | Añadir `allow_origins=["*"]` o `file://` en el middleware CORS cuando se detecte contexto bundle |
| **stdin bloqueante** | Si Python lee stdin (ej. debugger, `input()`), el subprocess se cuelga esperando input que nunca llega | BAJO | Redirigir stdin a `/dev/null` en el Process de Swift |

---

## Anti-Patterns Explícitos

| Anti-pattern | Por qué falla | En lugar de |
|--------------|---------------|-------------|
| Firmar solo el ejecutable principal | Gatekeeper verifica cada Mach-O individualmente | Firma bottom-up de todas las `.dylib` y `.so` |
| Usar `codesign --deep` como único paso de firma | `--deep` tiene bugs en subdirectorios no estándar | Script explícito que firma cada binario individualmente |
| Confiar en que el usuario tiene Python en el sistema | La versión del sistema puede ser incompatible o no existir en macOS 15+ | Siempre usar python-build-standalone relocatable dentro del bundle |
| Puerto fijo sin fallback | Conflicto garantizado con otras apps o instancias | Puerto dinámico o check + kill previo al bind |
| API keys en `UserDefaults` o en el bundle | `UserDefaults` es texto plano en `~/Library/Preferences/` | Siempre Keychain con `AccessibleWhenUnlockedThisDeviceOnly` |
| Iniciar FastAPI con `reload=True` en producción | File watcher en bundle read-only causa errores; consume recursos | `reload=False` fuera de modo desarrollo explícito |
| Mostrar errores del subprocess con mensaje técnico | «RuntimeError: No module named fastapi» no es accionable para el usuario | Traducir errores del subprocess a mensajes de usuario + acción |

---

## Sources

| Source | Topic | Confidence |
|--------|-------|------------|
| python-build-standalone releases (indygreg/python-build-standalone) | Variante relocatable, PYTHONHOME, paths compilados | HIGH (conocimiento de spec del proyecto) |
| Apple Developer Documentation — Code Signing Guide | Firma bottom-up, quarantine xattr, Gatekeeper | HIGH |
| Sparkle 2.x Documentation — `generate_keys`, EdDSA signing | Firma de updates sin Developer ID | HIGH |
| macOS Security Overview — Keychain Services | `SecItemAdd`, atributos de acceso, ACL | HIGH |
| NSTask / Process Apple documentation | `terminate()`, `waitUntilExit()`, Pipe, entorno | HIGH |
| Gatekeeper behavior macOS 14/15 | Quarantine en bundles descargados, `xattr` | HIGH |
| `.planning/PROJECT.md` v3.0 constraints | Stack, distribución ad-hoc, Keychain, Sparkle | HIGH (repo) |

*Nota: WebSearch y WebFetch no disponibles en este contexto. Pitfalls basados en especificación técnica del dominio y documentación conocida del ecosistema macOS/Python (corte agosto 2025). Verificar comportamiento específico de macOS 15 Sequoia en CI antes de release.*

---

*Investigación pitfalls macOS app: 2026-06-02. Consumir junto con `.planning/research/STACK.md` y `.planning/research/ARCHITECTURE.md` para implicaciones de fases en ROADMAP v3.0.*
