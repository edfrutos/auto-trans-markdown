# Phase 18: SSE Batch Nativo — Research

**Researched:** 2026-06-12
**Domain:** Swift 6 / URLSession AsyncBytes / SSE client / multipart upload / ZIP extraction / SwiftUI sheet state bridge
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** La vista de lote es una sheet SwiftUI anclada a la ventana principal (`.sheet()`), no panel flotante ni popover.
- **D-02:** Barra global determinada (archivos/total) + nombre del archivo en curso con su barra de segmentos (`done/total`) + contador. Sin lista completa de archivos durante el progreso.
- **D-03:** Al recibir `complete`, la sheet muestra resumen persistente (N traducidos, M errores) con botones "Cerrar" y "Mostrar en Finder". Sin autocierre.
- **D-04:** "Continuar en segundo plano": la sheet se oculta, el job sigue, el Dock muestra progreso, al terminar llega notificación. Debe poder reabrirse/consultarse.
- **D-05:** Al completar, la app descarga el ZIP y lo extrae en la carpeta de `OutputManager` (fallback Descargas). Los `.md` quedan sueltos; el ZIP se descarta.
- **D-06:** Se extraen solo los `.md` traducidos. Los sidecars `*.validation.json` y `errors.json` del ZIP NO se escriben en disco.
- **D-07:** Colisiones de nombre: sobrescribir (comportamiento actual de `saveFileSilently`). Sin diálogos.
- **D-08:** Al cancelar, se conservan los archivos ya traducidos: ZIP parcial descargado y extraído. Resumen "Cancelado: N de M".
- **D-09:** Cancelación cooperativa: botón Cancelar se deshabilita; sheet muestra "Cancelando — terminando archivo en curso…" hasta recibir `complete` con `cancelled: true`.
- **D-10:** ⌘Q con lote en curso: alert de confirmación "Hay un lote en curso (N de M archivos). ¿Salir y cancelarlo?". Salir/Continuar.
- **D-11:** Dos entradas: arrastre al Dock existente (Phase 13) + nueva entrada File → "Traducir lote…" con `NSOpenPanel` multi-selección en `Commands.swift`.
- **D-12:** Un solo idioma destino: `defaultTargetLang` de UserDefaults. Sin selección multi-idioma nativa (la web ya cubre ese caso).
- **D-13:** El `NSAlert` de confirmación de Phase 13 se sustituye por la propia sheet en estado "preparado": lista de archivos, idioma destino, botón "Traducir".

### Claude's Discretion

- Arquitectura Swift interna del cliente SSE (parser de `URLSession.bytes`, actor/observable del estado del job, etc.)
- Manejo de reconexión/errores de red del stream SSE
- Detalles visuales de la sheet (espaciado, tipografía) siguiendo el estilo existente de SettingsView/SplashView

### Deferred Ideas (OUT OF SCOPE)

- Multi-idioma destino en el lote nativo (el jobs API ya lo soporta; extensión futura)
- Drag & drop de varios `.md` sobre la ventana principal como tercera entrada del lote
- Lista completa de archivos con estado individual en la sheet

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID     | Description                                                                                                                                                                                       | Research Support                                                                                                     |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| SSE-01 | La app consume `GET /api/translate/batch/jobs/{id}/events` con URLSession (bytes stream) y parsea los eventos SSE existentes (`file_start`, `segment_progress`, `file_done`, `error`, `complete`) | Formato exacto de eventos verificado en `src/jobs.py` y `src/main.py`; patrón URLSession.bytes documentado en WWDC21 |
| SSE-02 | La vista de lote muestra progreso determinado: barra global (archivos completados/total) + archivo en curso con su progreso de segmentos                                                          | Payloads `file_start`/`segment_progress`/`file_done` verificados; `DockProgressManager` API reutilizable             |
| SSE-03 | Botón "Cancelar" llama a `DELETE /api/translate/batch/jobs/{id}` (cancelación cooperativa ya implementada en backend)                                                                             | Endpoint DELETE verificado en `src/main.py`; semántica cooperativa verificada en `src/jobs.py`                       |
| SSE-04 | El progreso del Dock (`DockProgressManager`, Phase 13) se alimenta de los eventos SSE en lugar del estado indeterminado actual                                                                    | `DockProgressManager.showProgress(current:total:)` verificado; cambio solo en la fuente de datos                     |

</phase_requirements>

---

## Summary

La fase 18 es una fase de **consumo puro de Swift**: el backend Python (FastAPI + jobs SSE) ya existe y no se toca. El trabajo consiste en construir un cliente SSE nativo en Swift 6, una sheet SwiftUI de lote, y el puente `AppDelegate → sheet` para los dos puntos de entrada (Dock drag y menú File).

El backend emite 5 tipos de eventos SSE sobre `GET /api/translate/batch/jobs/{id}/events` como `data: {json}\n\n` (sin campo `event:`). El cliente Swift usa `URLSession.shared.bytes(for:)` + `.lines` para consumirlos línea a línea de forma asíncrona. La cancelación es una llamada `DELETE` HTTP; la task Swift se cancela simplemente con `task.cancel()` una vez recibido el `complete`. El ZIP se descarga con `GET .../download` (disponible solo cuando el job está en `COMPLETED` o `CANCELLED`, con 409 si está en curso). La extracción se hace con `Process` + `/usr/bin/unzip` — disponible en macOS y funcional ya que la app no está sandboxed.

El patrón de estado observable sigue exactamente el de `ServerManager`: `@Observable @MainActor class`. El puente `AppDelegate → sheet` sigue el patrón ya establecido con `NotificationCenter` (mismo mecanismo que `.openSettings`). No se necesita ninguna dependencia nueva.

**Recomendación principal:** Crear `BatchJobManager.swift` como singleton `@Observable @MainActor` que encapsula todo el estado del job (URLs, progreso, estado de la sheet), y usar `NotificationCenter.default.post(name: .openBatchSheet, object: urls)` como puente desde `AppDelegate`. La sheet en `MDTranslatorApp` escucha la notificación y se activa con `$showBatchSheet`.

---

## Architectural Responsibility Map

| Capability                       | Primary Tier                                 | Secondary Tier   | Rationale                                                                                      |
| -------------------------------- | -------------------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------- |
| Crear job batch (POST multipart) | API / Backend                                | —                | El backend crea el job y devuelve `job_id`; Swift solo envía la request                        |
| Stream SSE (consumir eventos)    | App macOS (cliente)                          | —                | `URLSession.bytes` en Swift; el backend ya emite; sin intermediarios                           |
| Estado del progreso en memoria   | App macOS (`BatchJobManager`)                | —                | Singleton observable; fuente de verdad para sheet y Dock                                       |
| Vista de progreso (sheet)        | App macOS (SwiftUI)                          | —                | `BatchSheet.swift` — lee estado de `BatchJobManager`                                           |
| Progreso Dock                    | App macOS (`DockProgressManager`)            | —                | Ya existe; se alimenta desde `BatchJobManager` en lugar de bucle de índice                     |
| Cancelación (DELETE)             | App macOS → API / Backend                    | —                | Swift envía DELETE; backend pone `cancel_requested = True`; el worker termina cooperativamente |
| Descarga ZIP                     | App macOS → API / Backend                    | —                | GET .../download; solo disponible post-`complete`/`cancelled`                                  |
| Extracción ZIP → .md             | App macOS (Process + /usr/bin/unzip)         | —                | Extracción local en la máquina; `/usr/bin/unzip` verificado en macOS                           |
| Guardado de .md                  | App macOS (`OutputManager.saveFileSilently`) | —                | Ya existe con security-scoped bookmark y fallback Descargas                                    |
| Notificación fin de lote         | App macOS (`NotificationManager`)            | —                | Ya existe; se reutiliza sin cambios                                                            |
| Confirmación salida (⌘Q)         | App macOS (`AppDelegate`)                    | —                | `applicationShouldTerminate` + `NSAlert` modal; patrón ya establecido                          |
| Entrada File → "Traducir lote…"  | App macOS (`Commands.swift`)                 | —                | `NSOpenPanel` multi-selección; añadir `CommandGroup`                                           |

---

## Standard Stack

### Core (sin dependencias nuevas)

| Componente                                | Versión / API               | Propósito                            | Por qué es estándar                                               |
| ----------------------------------------- | --------------------------- | ------------------------------------ | ----------------------------------------------------------------- |
| `URLSession.shared.bytes(for:)`           | Foundation / macOS 12+      | Stream SSE línea a línea             | API nativa; evita dependencias; compatible macOS 14+ del proyecto |
| `AsyncBytes.lines`                        | Foundation / macOS 12+      | Iterar el stream SSE línea por línea | Estándar WWDC21; `for try await line in bytes.lines`              |
| `@Observable` macro                       | Swift 5.9+ / macOS 14+      | Estado reactivo de `BatchJobManager` | Ya en uso en `ServerManager`; patrón establecido del proyecto     |
| `NotificationCenter`                      | Foundation                  | Puente `AppDelegate → sheet SwiftUI` | Ya en uso para `.openSettings`; sin acoplamiento directo          |
| `Process` + `/usr/bin/unzip`              | Foundation / macOS built-in | Extracción ZIP                       | App no sandboxed; `/usr/bin/unzip` verificado en macOS            |
| `OutputManager.saveFileSilently`          | Proyecto (existente)        | Guardar `.md` sin diálogos           | Bookmark + fallback Descargas; D-07 sobrescribir                  |
| `DockProgressManager.showProgress`        | Proyecto (existente)        | Barra Dock determinada               | Ya dibuja barra; solo cambia la fuente de datos                   |
| `NotificationManager.sendTranslationDone` | Proyecto (existente)        | Notificación fin de lote             | Ya existe; reutilizable sin cambios                               |

### Nuevos archivos Swift a crear

| Archivo                 | Rol                                                                                        |
| ----------------------- | ------------------------------------------------------------------------------------------ |
| `BatchJobManager.swift` | Singleton `@Observable @MainActor`; cliente SSE, estado del job, descarga y extracción ZIP |
| `BatchSheet.swift`      | Vista SwiftUI con tres estados: preparado, en progreso, resumen                            |

### Dependencias descartadas

| En lugar de                                                           | Descartar   | Motivo                                                                                                                                    |
| --------------------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Librería SSE de terceros (`mattt/EventSource`, `Recouse/EventSource`) | No usar     | El backend emite formato `data: {json}\n\n` sin campo `event:` — parsing trivial con `.lines`; añadir dependencia externa no aporta valor |
| `ZipFoundation` u otra librería ZIP en Swift                          | No usar     | `/usr/bin/unzip` verificado disponible; `Process` es suficiente para D-06 (filtrar por extensión .md)                                     |

---

## Package Legitimacy Audit

> Esta fase no instala paquetes externos. No se añaden dependencias a Package.swift ni a requirements.txt.

**Packages removed due to slopcheck [SLOP] verdict:** ninguno
**Packages flagged as suspicious [SUS]:** ninguno

---

## Formato Exacto de los Eventos SSE del Backend

**Fuente:** `src/jobs.py` y `src/main.py` — verificado directamente. [VERIFIED: codebase]

### Wire format

El backend usa `StreamingResponse` con `media_type="text/event-stream"`. Cada evento se emite como:

```http
data: {json_payload}\n\n
```

No hay campo `event:` ni `id:` — solo `data:`. El cliente debe filtrar las líneas que empiecen por `data: ` y deserializar el JSON.

### Tabla de eventos

| `type`             | Campos garantizados                                                                 | Cuándo se emite                                                                     |
| ------------------ | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `file_start`       | `filename`, `file_index`, `total_files`, `target_lang`, `lang_index`, `total_langs` | Antes de traducir cada (archivo, idioma)                                            |
| `segment_progress` | `filename`, `target_lang`, `done`, `total`                                          | Cada vez que el pipeline reporta progreso de segmentos (vía `on_progress` callback) |
| `file_done`        | `filename`, `target_lang`, `out_name`                                               | Al completar con éxito un (archivo, idioma)                                         |
| `error`            | `filename`, `target_lang`, `message`                                                | Si la traducción de un (archivo, idioma) lanza excepción                            |
| `complete`         | `ok_count`, `error_count`, `total_files`, `total_langs`, `cancelled`                | Siempre al final (éxito o cancelación); señal de fin del stream                     |

**Notas críticas:**

- `complete.cancelled` es `true` si el job se canceló, `false` si completó normalmente.
- El stream se cierra tras `complete` — el generador hace `break` al recibirlo.
- `segment_progress` puede llegar 0 veces por archivo (si el archivo tiene 1 segmento, puede que el callback nunca se llame con valores intermedios).
- En lote con `target_langs = ["es"]` (D-12): `total_langs = 1`, `lang_index = 0` siempre.

### Ejemplo de secuencia para 2 archivos

```http
data: {"type":"file_start","filename":"doc.md","file_index":0,"total_files":2,"target_lang":"es","lang_index":0,"total_langs":1}

data: {"type":"segment_progress","filename":"doc.md","target_lang":"es","done":1,"total":5}

data: {"type":"segment_progress","filename":"doc.md","target_lang":"es","done":5,"total":5}

data: {"type":"file_done","filename":"doc.md","target_lang":"es","out_name":"doc.es.md"}

data: {"type":"file_start","filename":"readme.md","file_index":1,"total_files":2,"target_lang":"es","lang_index":0,"total_langs":1}

data: {"type":"file_done","filename":"readme.md","target_lang":"es","out_name":"readme.es.md"}

data: {"type":"complete","ok_count":2,"error_count":0,"total_files":2,"total_langs":1,"cancelled":false}

```

---

## API del Backend — Resumen para el Cliente Swift

**Fuente:** `src/main.py` líneas 724–805. [VERIFIED: codebase]

### POST /api/translate/batch/jobs

**Tipo de cuerpo:** `multipart/form-data`

| Campo          | Tipo                   | Obligatorio   | Notas                                                            |
| -------------- | ---------------------- | ------------- | ---------------------------------------------------------------- |
| `files`        | UploadFile (múltiple)  | Sí            | Un campo `files` por archivo; nombre = `filename` del UploadFile |
| `target_lang`  | Form string            | Condicional   | Alternativo a `target_langs`; D-12 usa uno solo                  |
| `target_langs` | Form string (múltiple) | Condicional   | Lista CSV o campos repetidos                                     |
| `source_lang`  | Form string            | No            | Por defecto `"auto"`                                             |
| `tone`         | Form string            | No            | Por defecto `"auto"`                                             |

**Respuesta 200:** `{"job_id": "<hex32>"}`

**Auth:** `_require_api_token` — acepta `Authorization: Bearer <token>` o query param `?access_token=<token>`. Si `API_TOKEN` env está vacío (desarrollo local), auth es no-op.

### GET /api/translate/batch/jobs/{job_id}/events

- **Media type:** `text/event-stream`
- **Headers respuesta:** `Cache-Control: no-cache`, `Connection: keep-alive`
- **Auth:** igual que POST
- **Importante para SSE:** como `URLSession.bytes` no puede añadir query params en `EventSource`, usar `Authorization: Bearer` en el header de la request.

### DELETE /api/translate/batch/jobs/{job_id}

- **Respuesta 200:** `{"cancelled": true}`
- **Respuesta 404:** job no encontrado
- Pone `cancel_requested = True` en el job; el worker termina cooperativamente (el archivo en curso completa antes de parar).

### GET /api/translate/batch/jobs/{job_id}/download

- **Respuesta 200:** ZIP bytes, `Content-Disposition: attachment; filename="traducciones.zip"`
- **Respuesta 404:** job no encontrado o ZIP aún no disponible
- **Respuesta 409:** job aún en curso (`state` no es COMPLETED ni CANCELLED)
- El ZIP está disponible tanto para `COMPLETED` como para `CANCELLED` (D-08: ZIP parcial con éxitos acumulados).

---

## Architecture Patterns

### Diagrama de flujo principal

```text
AppDelegate.application(_:open:) [≥2 archivos .md]
    │
    └─► NotificationCenter.post(.openBatchSheet, object: urls)
            │
            ▼
MDTranslatorApp.onReceive(.openBatchSheet)
    │  showBatchSheet = true
    │  batchJobManager.prepareWith(urls:)
    │
    ▼
BatchSheet (estado: .prepared)
    ├── Lista de archivos + idioma destino
    └── Botón "Traducir" ──► BatchJobManager.start()
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              POST multipart   GET .../events   DELETE (si cancela)
              /api/.../jobs    (SSE stream)     /api/.../jobs/{id}
                    │               │
                    └──job_id───────►
                                    │
                            for try await line in bytes.lines
                                    │
                            parsear "data: {json}"
                                    │
                     ┌──────────────┼──────────────┐
                     │              │              │
               file_start   segment_progress   file_done / error / complete
                     │              │              │
                     └──────────────┴──────────────► @MainActor update
                                                        │
                                         ┌──────────────┼────────────────────┐
                                         ▼              ▼                    ▼
                                   BatchSheet       DockProgressManager  al complete:
                                  (progreso)       .showProgress()       descargar ZIP
                                                                         extraer .md
                                                                         saveFileSilently
                                                                         notificación
```

### Estructura de archivos nuevos

```text
macos/MDTranslator/MDTranslator/
├── BatchJobManager.swift    ← nuevo: singleton @Observable @MainActor
└── BatchSheet.swift         ← nuevo: SwiftUI sheet con 3 estados
```

### Archivos modificados

```text
macos/MDTranslator/MDTranslator/
├── AppDelegate.swift        ← sustituir confirmAndBatch/batchTranslate por post(.openBatchSheet)
├── Commands.swift           ← añadir "Traducir lote…" en File CommandGroup
└── MDTranslatorApp.swift    ← añadir @State showBatchSheet + .sheet(isPresented:) + onReceive(.openBatchSheet)
```

### Pattern 1: Cliente SSE con URLSession.bytes

```swift
// Fuente: WWDC21 Session 10095 "Use async/await with URLSession" + verificación en src/main.py
// BatchJobManager.swift (fragmento)

@MainActor
@Observable
final class BatchJobManager {
    static let shared = BatchJobManager()
    private var streamTask: Task<Void, Never>?

    func startSSEStream(jobId: String, port: Int) {
        streamTask = Task {
            var request = URLRequest(url: URL(string:
                "http://127.0.0.1:\(port)/api/translate/batch/jobs/\(jobId)/events")!)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            // Si API_TOKEN está activo, añadir Bearer; en desarrollo local es vacío.
            // request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    // error de red — actualizar estado
                    return
                }
                for try await line in bytes.lines {
                    guard !Task.isCancelled else { break }
                    // El wire format es: "data: {json}" o línea vacía (separador)
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonStr = String(line.dropFirst(6))
                    guard let data = jsonStr.data(using: .utf8),
                          let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = event["type"] as? String
                    else { continue }

                    // Actualizar estado en MainActor
                    handleEvent(type: type, payload: event)

                    if type == "complete" { break }
                }
            } catch {
                // URLError.cancelled cuando task.cancel() — silenciar
                if (error as? URLError)?.code != .cancelled {
                    // registrar error real
                }
            }
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
    }
}
```

### Pattern 2: Puente AppDelegate → sheet SwiftUI

```swift
// Fuente: patrón existente en MDTranslatorApp.swift (.openSettings) [VERIFIED: codebase]

// 1. En AppDelegate.swift — reemplazar confirmAndBatch:
@MainActor
private func openBatchSheet(_ urls: [URL]) {
    BatchJobManager.shared.prepareWith(urls: urls)
    NotificationCenter.default.post(name: .openBatchSheet, object: nil)
}

// 2. En MDTranslatorApp.swift — añadir a WindowGroup:
@State private var showBatchSheet = false

// Dentro del Group {...}:
.sheet(isPresented: $showBatchSheet) {
    BatchSheet(manager: BatchJobManager.shared,
               serverManager: serverManager)
}
.onReceive(NotificationCenter.default.publisher(for: .openBatchSheet)) { _ in
    showBatchSheet = true
}

// 3. En Commands.swift — añadir NotificationCenter.Name:
extension Notification.Name {
    static let openBatchSheet = Notification.Name("openBatchSheet")
}
```

### Pattern 3: Construir multipart/form-data sin librerías

```swift
// Fuente: theswiftdev.com/easy-multipart-file-upload-for-swift/ [CITED]
// Adaptado para el endpoint POST /api/translate/batch/jobs

struct MultipartBody {
    let boundary = UUID().uuidString
    private var data = Data()

    mutating func addText(_ key: String, _ value: String) {
        data += "--\(boundary)\r\n".data(using: .utf8)!
        data += "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!
        data += "\(value)\r\n".data(using: .utf8)!
    }

    mutating func addFile(name: String, filename: String, content: Data) {
        data += "--\(boundary)\r\n".data(using: .utf8)!
        data += "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!
        data += "Content-Type: text/markdown; charset=utf-8\r\n\r\n".data(using: .utf8)!
        data += content
        data += "\r\n".data(using: .utf8)!
    }

    var finalized: Data {
        data + "--\(boundary)--\r\n".data(using: .utf8)!
    }
}

// Uso para POST /api/translate/batch/jobs:
// var body = MultipartBody()
// body.addText("target_lang", targetLang)           // D-12: un solo idioma
// for url in urls {
//     let raw = try Data(contentsOf: url)
//     body.addFile(name: "files", filename: url.lastPathComponent, content: raw)
// }
// var request = URLRequest(url: postURL)
// request.httpMethod = "POST"
// request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
// request.httpBody = body.finalized
// let (data, _) = try await URLSession.shared.data(for: request)
// let response = try JSONDecoder().decode(BatchJobCreateResponse.self, from: data)
```

### Pattern 4: Extracción ZIP con Process + /usr/bin/unzip (D-05, D-06)

```swift
// /usr/bin/unzip verificado disponible en macOS [VERIFIED: shell]
// La app no está sandboxed (Phase 9, pitfall 2) → Process funciona sin restricciones.

func extractMarkdownFiles(zipData: Data, targetFolder: URL) throws {
    // 1. Escribir ZIP a temp
    let tmpZip = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("batch-\(UUID().uuidString).zip")
    try zipData.write(to: tmpZip, options: .atomic)
    defer { try? FileManager.default.removeItem(at: tmpZip) }

    // 2. Extraer solo .md (D-06: excluir *.validation.json y errors.json)
    // unzip -j : ignora estructura de directorios del ZIP
    // "*.md"   : extrae solo archivos con extensión .md
    // -d path  : carpeta destino
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    p.arguments = [
        "-o",                          // overwrite (D-07)
        "-j",                          // junk paths
        tmpZip.path,
        "*.md",                        // D-06: solo .md
        "-d", targetFolder.path
    ]
    try p.run()
    p.waitUntilExit()
    // p.terminationStatus == 0: OK; 11: no hay archivos .md (lote vacío o cancelado antes de completar)
}
```

**Nota:** `p.waitUntilExit()` bloquea el hilo llamante. Llamar desde un `Task { await MainActor.run { ... } }` usando `await withCheckedContinuation` o desde un executor de background.

### Pattern 5: applicationShouldTerminate con lote en curso (D-10)

```swift
// AppDelegate.swift — añadir método nonisolated siguiendo el patrón existente
// applicationShouldTerminate NO existe aún en AppDelegate — es nuevo.

nonisolated
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    MainActor.assumeIsolated {
        guard BatchJobManager.shared.isRunning else { return .terminateNow }
        let n = BatchJobManager.shared.completedCount
        let m = BatchJobManager.shared.totalCount
        let alert = NSAlert()
        alert.messageText = "Hay un lote en curso (\(n) de \(m) archivos)"
        alert.informativeText = "Si sales ahora, el servidor Python se detendrá y se perderán los archivos que aún no se han traducido."
        alert.addButton(withTitle: "Salir y cancelar")
        alert.addButton(withTitle: "Continuar en segundo plano")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            return .terminateNow
        } else {
            return .terminateCancel
        }
    }
}
```

### Pattern 6: Estado de BatchJobManager

```swift
// Los tres estados de la sheet (D-13, D-02, D-03)
enum BatchJobState {
    case idle                              // sin job — sheet no mostrada
    case prepared(urls: [URL])             // lista de archivos lista (D-13: confirmar+traducir en 1 componente)
    case running(jobId: String)            // SSE activo
    case cancelling                        // DELETE enviado, esperando complete (D-09)
    case done(ok: Int, errors: [(String, String)], cancelled: Bool)  // resumen final (D-03)
}

@MainActor
@Observable
final class BatchJobManager {
    static let shared = BatchJobManager()

    var jobState: BatchJobState = .idle

    // Progreso actualizado por eventos SSE
    var currentFile: String = ""
    var filesDone: Int = 0
    var filesTotal: Int = 0
    var segmentsDone: Int = 0
    var segmentsTotal: Int = 0
    var isRunning: Bool { /* jobState == .running || .cancelling */ false }
    var completedCount: Int { filesDone }
    var totalCount: Int { filesTotal }

    // ...
}
```

### Anti-Patterns a evitar

- **No usar `ObservableObject` + `@Published`**: el proyecto usa `@Observable` macro (Swift 5.9+/macOS 14+). Usar `ObservableObject` rompe el patrón establecido en `ServerManager`.
- **No reemplazar completamente `p.environment` en ningún `Process`**: pitfall documentado en `ServerManager.swift` — siempre heredar y sobreescribir solo las vars necesarias.
- **No usar `task.cancel()` antes de recibir `complete`** para el stream SSE: cancelar la task de red mata la conexión inmediatamente, sin esperar la respuesta del backend. Para la cancelación cooperativa (D-09), primero enviar DELETE, luego dejar que el stream cierre naturalmente al llegar `complete`.
- **No usar `zipFile` de stdlib pura de Swift**: Foundation no expone `ZipArchive` público. La única API stdlib es `zipFile.h` de C o `FileManager` sin soporte ZIP. Usar `/usr/bin/unzip` vía `Process`.
- **No intentar mostrar `NSSavePanel` desde dentro de la task SSE** sin saltar al hilo principal (ya manejado por `@MainActor`).

---

## Don't Hand-Roll

| Problema                                                 | No construir                     | Usar en cambio                            | Por qué                                                                                                                                                                                                          |
| -------------------------------------------------------- | -------------------------------- | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Parsing SSE (líneas `event:`, `data:`, `id:`, reconnect) | Parser completo de spec RFC 8895 | Solo filtrar `hasPrefix("data: ")` + JSON | El backend emite SOLO `data: {json}\n\n`; no usa `event:`, `id:` ni `retry:` — parser completo es over-engineering                                                                                               |
| ZIP parsing en Swift puro                                | ZipSwift, Zip, ZipFoundation     | `Process` + `/usr/bin/unzip`              | La app no está sandboxed; unzip nativo maneja correctamente encoding de nombres de archivo, paths anidados y archivos grandes                                                                                    |
| State machine del job                                    | Enum complejo con substates      | `enum BatchJobState` + `@Observable`      | 5 estados bien delimitados; no necesita framework de state machine                                                                                                                                               |
| Multipart builder                                        | Librería externa                 | Struct `MultipartBody` (~30 líneas)       | El formulario tiene 2 tipos de campos simples (texto + archivo); sin headers especiales                                                                                                                          |
| Cliente SSE con reconexión                               | Librería completa EventSource    | `Task` + `URLSession.bytes`               | El job SSE tiene vida finita (termina con `complete`); no hay semántica de reconexión — si el stream se corta, el job sigue en el backend y hay que decidir la UX (mostrar error), no reconectar silenciosamente |

---

## Common Pitfalls

### Pitfall 1: `@Observable` vs `ObservableObject` en Swift 6

**Qué va mal:** Usar `ObservableObject` + `@StateObject` en lugar de `@Observable` + `@State`. En Swift 6, `@MainActor class` no puede conformar `ObservableObject` (el compilador genera error de conformance).

**Por qué ocurre:** Mezclar patrones pre-macOS 14 con Swift 6.
**Cómo evitar:** Seguir el patrón de `ServerManager`: `@Observable @MainActor final class`. Usar `@State private var manager = Manager()` en la vista propietaria, o `BatchJobManager.shared` directamente.
**Señales de alerta:** Error de compilación `'@MainActor' class cannot conform to 'ObservableObject'`.

### Pitfall 2: Cancelar la task del stream ANTES del DELETE

**Qué va mal:** Llamar `streamTask?.cancel()` al pulsar "Cancelar" mata la conexión HTTP inmediatamente. El backend recibe RST TCP y puede no procesar el DELETE que llega justo después.

**Por qué ocurre:** Confundir "cancelar el stream Swift" con "cancelar el job backend".
**Cómo evitar:** Secuencia correcta para D-09: (1) enviar `DELETE /api/translate/batch/jobs/{id}`, (2) cambiar estado a `.cancelling`, (3) dejar que el stream siga hasta recibir `complete { cancelled: true }`, (4) ENTONCES cancelar la task y cerrar el stream.
**Señales de alerta:** La app muestra "Cancelado" pero el ZIP no contiene los archivos ya traducidos (D-08 incumplido).

### Pitfall 3: Llamar `p.waitUntilExit()` en el MainActor

**Qué va mal:** `Process.waitUntilExit()` bloquea el hilo. Si se llama desde el `@MainActor`, congela la UI durante la extracción del ZIP.

**Por qué ocurre:** La extracción se llama al recibir `complete` — momento en que el código está corriendo en el MainActor.
**Cómo evitar:** Envolver en `await Task.detached { p.run(); p.waitUntilExit() }.value` o usar `p.terminationHandler` + continuación checked.
**Señales de alerta:** La app se cuelga brevemente al finalizar un lote grande.

### Pitfall 4: ZIP con 409 si el DELETE no llegó antes del download

**Qué va mal:** Llamar `GET .../download` antes de que el backend haya completado la construcción del ZIP. El backend devuelve 409 si `state not in (COMPLETED, CANCELLED)`.

**Por qué ocurre:** El stream SSE puede cerrarse antes de que el backend haya terminado de escribir `job.zip_bytes`.
**Cómo evitar:** Descargar el ZIP SOLO después de recibir el evento `complete` por SSE — ese evento se emite DESPUÉS de `job.zip_bytes = build_batch_zip(...)` en `_run_job`.
**Señales de alerta:** Error 409 al descargar; verificar que el download se llama desde `handleEvent(type: "complete", ...)`.

### Pitfall 5: Líneas vacías del stream SSE ignoradas incorrectamente

**Qué va mal:** El generador Python emite `f"data: {json}\n\n"` — dos `\n`, lo que genera una línea vacía entre eventos. Si el cliente trata la línea vacía como error, puede romper el parsing.

**Por qué ocurre:** El protocolo SSE usa `\n\n` como separador de eventos; la línea vacía es intencional.
**Cómo evitar:** `guard line.hasPrefix("data: ") else { continue }` — el `continue` ignora silenciosamente las líneas vacías y cualquier otro prefijo no esperado.
**Señales de alerta:** Logs de deserialización JSON con cadenas vacías o errores de parsing.

### Pitfall 6: applicationShouldTerminate con async Task

**Qué va mal:** Intentar mostrar el alert con `Task { @MainActor in ... }` en lugar de `MainActor.assumeIsolated`. `applicationShouldTerminate` devuelve `TerminateReply` síncrono — no puede `await`.

**Por qué ocurre:** Confundir el nuevo patrón async con métodos de delegate síncronos.
**Cómo evitar:** Seguir el mismo patrón de AppDelegate: `nonisolated func + MainActor.assumeIsolated { alert.runModal() }`. Devolver `.terminateNow` o `.terminateCancel` síncronamente.
**Señales de alerta:** El compilador advierte sobre `async` en un contexto que requiere valor de retorno síncrono.

### Pitfall 7: Security-scoped bookmark para la carpeta destino del unzip

**Qué va mal:** `OutputManager.resolveBookmarkedFolder()` devuelve una URL con security-scoped bookmark. `Process.currentDirectoryURL` y los argumentos de unzip necesitan acceder a esa carpeta — pero el acceso security-scoped se abre con `startAccessingSecurityScopedResource()` y se cierra con `stopAccessingSecurityScopedResource()`.

**Por qué ocurre:** `Process` corre en el mismo proceso que la app; los accesos security-scoped del proceso padre son heredados, pero deben estar activos durante la ejecución del `Process`.
**Cómo evitar:** Llamar `folder.startAccessingSecurityScopedResource()` antes de `p.run()` y `folder.stopAccessingSecurityScopedResource()` después de `p.waitUntilExit()`.
**Señales de alerta:** Error `EPERM` o archivos no escritos en la carpeta bookmarked, aunque sí en Descargas.

---

## Code Examples

### Parsear evento SSE completo

```swift
// Fuente: derivado de src/jobs.py (payloads verificados) + WWDC21 URLSession.bytes pattern
// Llamar desde el loop for try await line in bytes.lines

private func handleSSELine(_ line: String) {
    guard line.hasPrefix("data: ") else { return }
    let jsonStr = String(line.dropFirst(6))
    guard let data = jsonStr.data(using: .utf8),
          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = payload["type"] as? String
    else { return }

    switch type {
    case "file_start":
        currentFile = payload["filename"] as? String ?? ""
        filesTotal  = payload["total_files"] as? Int ?? filesTotal
        segmentsDone = 0
        segmentsTotal = 0

    case "segment_progress":
        segmentsDone  = payload["done"]  as? Int ?? segmentsDone
        segmentsTotal = payload["total"] as? Int ?? segmentsTotal

    case "file_done":
        filesDone += 1
        DockProgressManager.shared.showProgress(current: filesDone, total: filesTotal)

    case "error":
        let filename = payload["filename"] as? String ?? "?"
        let msg      = payload["message"]  as? String ?? "Error desconocido"
        errorMessages.append((filename, msg))
        filesDone += 1
        DockProgressManager.shared.showProgress(current: filesDone, total: filesTotal)

    case "complete":
        let ok        = payload["ok_count"]    as? Int ?? 0
        let errCount  = payload["error_count"] as? Int ?? 0
        let cancelled = payload["cancelled"]   as? Bool ?? false
        jobState = .done(ok: ok, errors: errorMessages, cancelled: cancelled)
        DockProgressManager.shared.hideProgress()
        DockProgressManager.shared.setBadge(nil)
        // Descargar y extraer ZIP
        Task { await downloadAndExtractZIP() }

    default:
        break
    }
}
```

### Subir archivos con multipart (POST /api/translate/batch/jobs)

```swift
// Fuente: patrón derivado de theswiftdev.com y verificado contra src/main.py [CITED]

func createJob(urls: [URL], targetLang: String, port: Int) async throws -> String {
    let boundary = UUID().uuidString
    var body = Data()

    func append(_ string: String) { body += string.data(using: .utf8)! }

    // Campo target_lang (D-12: un solo idioma)
    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"target_lang\"\r\n\r\n")
    append("\(targetLang)\r\n")

    // Archivos
    for url in urls {
        let raw = try Data(contentsOf: url)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"files\"; filename=\"\(url.lastPathComponent)\"\r\n")
        append("Content-Type: text/markdown; charset=utf-8\r\n\r\n")
        body += raw
        append("\r\n")
    }
    append("--\(boundary)--\r\n")

    var request = URLRequest(
        url: URL(string: "http://127.0.0.1:\(port)/api/translate/batch/jobs")!,
        timeoutInterval: 30
    )
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (data, _) = try await URLSession.shared.data(for: request)
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let jobId = json["job_id"] as? String else {
        throw URLError(.cannotParseResponse)
    }
    return jobId
}
```

---

## Runtime State Inventory

> Esta fase no es una fase de renombrado/refactor/migración. Sección omitida.

---

## State of the Art

| Patrón antiguo                                                          | Patrón actual (esta fase)                                               | Cuándo cambió   | Impacto                                                   |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------- | --------------- | --------------------------------------------------------- |
| `batchTranslate` — bucle síncrono con `POST /api/translate` por archivo | `BatchJobManager` — un solo job SSE con stream de eventos               | Phase 18        | Progreso real, cancelación cooperativa, menos round-trips |
| `DockProgressManager` alimentado por índice de bucle                    | `DockProgressManager` alimentado por eventos `file_done` del stream SSE | Phase 18        | Progreso Dock coherente con el estado real del backend    |
| `NSAlert` para confirmar antes de batch (Phase 13)                      | Sheet SwiftUI con estado "preparado" → "en progreso" → "resumen" (D-13) | Phase 18        | Un único componente; sin saltos entre Alert y UI web      |
| Sin posibilidad de cancelar un lote en curso                            | Botón Cancelar + DELETE cooperativo (D-09)                              | Phase 18        | El coste API ya pagado no se pierde (D-08)                |

**Deprecated en esta fase:**

- `confirmAndBatch(_:)` en `AppDelegate.swift` — se sustituye por `openBatchSheet(_:)`.
- `batchTranslate(urls:port:targetLang:)` en `AppDelegate.swift` — se elimina; la lógica pasa a `BatchJobManager`.
- `callTranslateAPI(text:targetLang:port:)` en `AppDelegate.swift` — se elimina (verificado 2026-06-12: su único llamador es `batchTranslate`, que también se elimina).

---

## Open Questions (RESOLVED)

1. **Auth token en el stream SSE**
   - Qué sabemos: `_require_api_token` acepta `Authorization: Bearer` o query `?access_token=`. `URLSession.bytes` puede añadir headers pero no query params fácilmente.
   - Qué no está claro: si en el entorno macOS local `API_TOKEN` está vacío (deployment.py: `return token or None`), la auth es no-op. Si el usuario configura `API_TOKEN`, hay que inyectarlo.
   - RESOLVED: En el entorno macOS local `API_TOKEN` está vacío (la app lanza el servidor sin configurarlo), así que la auth es no-op y `BatchJobManager` no añade header `Authorization`. Si el usuario configurara `API_TOKEN` manualmente, las llamadas fallarían con 401 — escenario documentado en el threat model y fuera del alcance de esta fase.

2. **Readability de archivos grandes en multipart**
   - Qué sabemos: `Data(contentsOf: url)` carga el archivo completo en memoria antes de construir el cuerpo multipart.
   - Qué no está claro: el límite `MAX_BATCH_UPLOAD_MB` es 50 MB total — con archivos `.md` de documentación técnica esto raramente se alcanza, pero en lotes grandes podría ser un problema.
   - RESOLVED: Aceptable para Phase 18 — el límite de 50 MB del backend acota el peor caso y los `.md` de documentación rara vez se acercan. Si hiciera falta, una fase futura puede usar `uploadTask(with:fromFile:)` o streaming body.

3. **Reapertura de la sheet en modo segundo plano (D-04)**
   - Qué sabemos: D-04 dice que la sheet puede reabrirse mientras el job corre. `BatchJobManager.shared.jobState == .running` indica que hay un job activo.
   - Qué no está claro: ¿qué botón/menú re-abre la sheet? ¿File → "Traducir lote…" muestra la sheet existente si hay un job en curso?
   - RESOLVED: File → "Traducir lote…" (vía `.onReceive(.openBatchSheet)`) simplemente activa `showBatchSheet = true`; como la sheet renderiza según `BatchJobManager.shared.jobState`, con un job activo se abre directamente en estado de progreso (no en "preparado"). Implementado en los planes 18-02 (switch sobre `jobState`) y 18-03 (CAMBIO 3 de MDTranslatorApp.swift); se verifica en el checkpoint humano del plan 18-03.

---

## Environment Availability

| Dependencia              | Requerida por                         | Disponible                       | Versión                           | Fallback   |
| ------------------------ | ------------------------------------- | -------------------------------- | --------------------------------- | ---------- |
| Xcode 26.5 / Swift 6.3.2 | Compilación app macOS                 | Verificado                       | Xcode 26.5 / Swift 6.3.2          | —          |
| `/usr/bin/unzip`         | Extracción ZIP (D-05/D-06)            | Verificado                       | macOS built-in                    | —          |
| URLSession.bytes         | Cliente SSE                           | Verificado                       | macOS 12+ (req. mínimo: macOS 14) | —          |
| Backend FastAPI local    | Todos los endpoints de jobs           | Verificado (Phase 16 completada) | v2.0, 148 tests passing           | —          |
| `@Observable` macro      | `BatchJobManager`, patrón establecido | Verificado                       | Swift 5.9+ / macOS 14+            | —          |

**Missing dependencies con no fallback:** ninguna.

---

## Validation Architecture

> `workflow.nyquist_validation: true` en `.planning/config.json` — sección requerida.

### Test Framework

| Propiedad      | Valor                                          |
| -------------- | ---------------------------------------------- |
| Framework      | pytest 8.x (backend Python)                    |
| Config file    | `pyproject.toml` → `[tool.pytest.ini_options]` |
| Comando rápido | `pytest tests/test_jobs.py -q`                 |
| Suite completa | `pytest tests/ -q`                             |

**Nota:** Los tests de la app Swift (Xcode Unit Tests) no existen en el proyecto actualmente. Esta fase añade únicamente Swift nuevo; los tests de backend ya cubren `src/jobs.py`. Los criterios de aceptación de SSE-01..04 son tests manuales en la app.

### Phase Requirements → Test Map

| Req ID   | Comportamiento                                                  | Tipo de test  | Comando automatizado                     | Archivo existe   |
| -------- | --------------------------------------------------------------- | ------------- | ---------------------------------------- | ---------------- |
| SSE-01   | Backend emite eventos SSE correctamente                         | unit Python   | `pytest tests/test_jobs.py -q`           | Existe           |
| SSE-02   | Progreso determinado en sheet (archivo en curso + barra global) | manual UI     | —                                        | N/A (Swift UI)   |
| SSE-03   | DELETE cancela cooperativamente y ZIP parcial contiene éxitos   | unit Python   | `pytest tests/test_jobs.py -q -k cancel` | Existe           |
| SSE-04   | Dock muestra progreso real (mismo valor que sheet)              | manual UI     | —                                        | N/A (Swift UI)   |

### Sampling Rate

- Por commit de tarea: `pytest tests/test_jobs.py -q`
- Por merge de wave: `pytest tests/ -q`
- Phase gate: suite completa verde + verificación manual de la app

### Wave 0 Gaps

- Ninguno — `tests/test_jobs.py` ya existe y cubre `create_batch_job`, `cancel_job`, `file_done`, `complete`. Los criterios de aceptación visuales (SSE-02, SSE-04) son manuales.

---

## Security Domain

> `security_enforcement` no está explícitamente configurado en `.planning/config.json` — tratar como habilitado.

### Applicable ASVS Categories

| Categoría ASVS        | Aplica                                  | Control estándar                                                                          |
| --------------------- | --------------------------------------- | ----------------------------------------------------------------------------------------- |
| V2 Authentication     | Sí (Bearer token si `API_TOKEN` activo) | `_require_api_token` ya implementado en backend; cliente Swift añade header               |
| V3 Session Management | No                                      | Sin sesiones; cada request es independiente                                               |
| V4 Access Control     | No                                      | Solo endpoints locales en 127.0.0.1                                                       |
| V5 Input Validation   | Sí                                      | Backend valida idioma, tamaño, UTF-8; cliente Swift valida extensión `.md` antes de subir |
| V6 Cryptography       | No                                      | Sin criptografía nueva en esta fase                                                       |

### Known Threat Patterns

| Patrón                                      | STRIDE                 | Mitigación estándar                                                                                                   |
| ------------------------------------------- | ---------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Upload de archivo no-Markdown               | Tampering              | Backend ya valida: binarios rechazados (byte nulo), límite `MAX_BATCH_UPLOAD_MB`; cliente filtra `.md` antes de subir |
| SSRF hacia endpoints distintos de localhost | Elevation of Privilege | URL hardcodeada a `127.0.0.1:{serverPort}` — `serverPort` viene de `ServerManager` (bind dinámico local)              |
| ZIP bomb en la respuesta de download        | DoS                    | Archivos `.md` de documentación son pequeños; no hay extracción recursiva; mitigación adicional out of scope          |

---

## Project Constraints (from CLAUDE.md)

| Directiva                                                              | Fuente                                | Impacto en esta fase                                                                |
| ---------------------------------------------------------------------- | ------------------------------------- | ----------------------------------------------------------------------------------- |
| Nunca commitear `.env`; API keys en Keychain                           | CLAUDE.md §Constraints                | `API_TOKEN` leído de env (inyectado por `ServerManager`); nunca hardcodeado         |
| Salida siempre Markdown válido; código y URLs intactos                 | CLAUDE.md §Constraints                | El backend ya garantiza esto; la extracción ZIP no transforma el contenido          |
| `@Observable` macro, NO `ObservableObject`                             | CLAUDE.md §macOS Pitfalls (Pitfall 4) | `BatchJobManager` usa `@Observable @MainActor`                                      |
| `p.run()` (no `p.launch()`), `p.executableURL` (no `p.launchPath`)     | CLAUDE.md §macOS Pitfalls (Pitfall 3) | Aplicar al `Process` de unzip                                                       |
| Heredad entorno padre en `Process.environment`                         | CLAUDE.md §macOS Pitfalls (Pitfall 1) | Si `BatchJobManager` lanza `Process`, heredar `ProcessInfo.processInfo.environment` |
| App Sandbox eliminado (incompatible con subprocess)                    | CLAUDE.md §macOS Pitfalls (Pitfall 2) | Confirma que `Process` + `/usr/bin/unzip` funciona sin restricciones                |
| Mensajes de UI nativa en español                                       | CLAUDE.md §Conventions                | Todos los textos de la sheet, alertas y botones en español                          |
| Código en `snake_case` (Python), Swift usa convenciones estándar Swift | CLAUDE.md §Naming                     | Swift: `BatchJobManager`, `batchJobState`, etc. en camelCase                        |
| Pre-commit hook `git secrets --pre_commit_hook`                        | CLAUDE.md §Code Style                 | No commitear API keys reales en código Swift                                        |

---

## Assumptions Log

| #   | Afirmación                                                                                                                          | Sección                | Riesgo si es incorrecta                                                                                                              |
| --- | ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| A1  | `API_TOKEN` estará vacío en el entorno local de desarrollo de la app nativa (sin auth real activa)                                  | API del Backend        | Si el usuario tiene `API_TOKEN` configurado en `.env`, las llamadas del cliente Swift fallarán con 401 hasta añadir el header Bearer |
| A2  | `/usr/bin/unzip` acepta el patrón glob `"*.md"` para filtrar archivos del ZIP                                                       | Extracción ZIP         | Si la versión de unzip de macOS no soporta glob en ese argumento, hay que extraer todo y borrar los no-md después                    |
| A3  | `FileManager.default.urls(for: .downloadsDirectory)` devuelve una URL escribible sin permisos adicionales en macOS 14+ no sandboxed | OutputManager fallback | Si TCC o permisos cambian, el fallback Descargas podría fallar silenciosamente                                                       |

---

## Sources

### Primary (HIGH confidence)

- `src/jobs.py` (codebase verificado) — formato exacto de eventos SSE, semántica de cancelación cooperativa, momento de `zip_bytes`
- `src/main.py` (codebase verificado) — endpoints HTTP, modelos Pydantic, auth token, SSE StreamingResponse
- `src/batch_zip.py` (codebase verificado) — contenido del ZIP (`.md` + `*.validation.json` + `errors.json`)
- `macos/MDTranslator/MDTranslator/AppDelegate.swift` (codebase verificado) — patrón `nonisolated` + `MainActor.assumeIsolated`, código batch existente a sustituir
- `macos/MDTranslator/MDTranslator/ServerManager.swift` (codebase verificado) — patrón `@Observable @MainActor` a imitar
- `macos/MDTranslator/MDTranslator/MDTranslatorApp.swift` (codebase verificado) — patrón `NotificationCenter` para puente AppDelegate→sheet
- `macos/MDTranslator/MDTranslator/DockProgressManager.swift` (codebase verificado) — API `showProgress/hideProgress/setBadge`
- `macos/MDTranslator/MDTranslator/OutputManager.swift` (codebase verificado) — `saveFileSilently`, security-scoped bookmark, fallback Descargas
- Apple WWDC21 Session 10095 "Use async/await with URLSession" — `URLSession.bytes(for:)` + `AsyncBytes.lines`
- `/usr/bin/unzip` disponibilidad verificada en shell macOS 25.5.0

### Secondary (MEDIUM confidence)

- [theswiftdev.com/easy-multipart-file-upload-for-swift/](https://theswiftdev.com/easy-multipart-file-upload-for-swift/) — patrón multipart/form-data sin librerías
- Apple Developer Documentation `URLSession.AsyncBytes` — firma y uso de `.lines`

### Tertiary (LOW confidence)

- Ninguna — todos los hallazgos críticos están verificados en el codebase o en documentación oficial.

---

## Metadata

**Confidence breakdown:**

- Formato exacto SSE: HIGH — leído directamente de `src/jobs.py` y `src/main.py`
- API endpoints: HIGH — leído directamente de `src/main.py`
- Patrones Swift (URLSession.bytes, @Observable): HIGH — WWDC21 oficial + código existente en el proyecto
- Extracción ZIP con Process: HIGH — `/usr/bin/unzip` verificado; app no sandboxed verificado
- Puente AppDelegate→sheet: HIGH — patrón `.openSettings` ya en uso en el proyecto
- Multipart builder: MEDIUM — patrón genérico de community docs, verificado contra spec HTTP

**Research date:** 2026-06-12
**Válido hasta:** 2026-07-12 (stack estable; el backend no cambia en esta fase)
