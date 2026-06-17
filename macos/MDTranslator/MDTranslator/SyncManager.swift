// SyncManager.swift — Gestión de sincronización de datos via iCloud Drive.
//
// SYNC-01..04 (Phase 21): gestiona la preferencia "iCloud Drive sync" y las rutas
// efectivas de glossary.yaml y translation_memory.db, incluyendo la migración
// asistida al activar/desactivar y la detección de conflictos SQLite.
//
// No requiere entitlements de iCloud (com.apple.developer.icloud-container-identifiers,
// iCloud Documents). Usamos ~/Library/Mobile Documents/com~apple~CloudDocs/MDTranslator/
// como directorio normal del sistema de archivos; iCloudDrive lo sincroniza de forma
// transparente.

import Combine
import Foundation
import AppKit

/// Gestiona las rutas de datos (glosario y TM) y la migración entre local e iCloud Drive.
@MainActor
final class SyncManager: ObservableObject {

    // MARK: - Singleton
    static let shared = SyncManager()

    // MARK: - Constantes de rutas

    /// Clave UserDefaults para la preferencia de sincronización.
    static let iCloudSyncKey = "iCloudDriveSyncEnabled"

    /// Nombre de la carpeta dentro de iCloud Drive.
    private static let iCloudFolderName = "MDTranslator"

    /// Nombre del archivo de glosario.
    private static let glossaryFileName = "glossary.yaml"

    /// Nombre de la base de datos de TM.
    private static let dbFileName = "translation_memory.db"

    // MARK: - Estado publicado

    /// true = datos en iCloud Drive, false = datos en data/ local.
    @Published private(set) var isICloudEnabled: Bool

    /// Mensaje de advertencia visible en la UI (conflicto SQLite, iCloud no disponible, etc.).
    @Published private(set) var syncWarning: String?

    // MARK: - Init

    private init() {
        isICloudEnabled = UserDefaults.standard.bool(forKey: SyncManager.iCloudSyncKey)
    }

    // MARK: - Rutas efectivas

    /// Ruta local del glosario (en el bundle del backend embebido o en data/).
    private static var localGlossaryPath: URL {
        // En la app empaquetada el backend está en Resources/backend/
        if let backendURL = Bundle.main.resourceURL?.appendingPathComponent("backend") {
            return backendURL.appendingPathComponent(glossaryFileName)
        }
        // Fallback desarrollo (raíz del proyecto)
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(glossaryFileName)
    }

    /// Ruta local de la base de datos TM.
    private static var localDBPath: URL {
        if let backendURL = Bundle.main.resourceURL?.appendingPathComponent("backend") {
            let dataDir = backendURL.appendingPathComponent("data")
            try? FileManager.default.createDirectory(at: dataDir,
                                                     withIntermediateDirectories: true)
            return dataDir.appendingPathComponent(dbFileName)
        }
        let dataDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("data")
        try? FileManager.default.createDirectory(at: dataDir,
                                                 withIntermediateDirectories: true)
        return dataDir.appendingPathComponent(dbFileName)
    }

    /// Directorio de iCloud Drive para MDTranslator.
    private static var iCloudDir: URL? {
        let iCloud = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return iCloud.appendingPathComponent(iCloudFolderName)
    }

    /// Ruta iCloud del glosario.
    private static var iCloudGlossaryPath: URL? {
        iCloudDir?.appendingPathComponent(glossaryFileName)
    }

    /// Ruta iCloud de la base de datos TM.
    private static var iCloudDBPath: URL? {
        iCloudDir?.appendingPathComponent(dbFileName)
    }

    // MARK: - Rutas efectivas para inyectar en ServerManager

    /// Ruta efectiva del glosario según la preferencia de sync.
    var effectiveGlossaryPath: String? {
        guard isICloudEnabled,
              let path = SyncManager.iCloudGlossaryPath?.path else { return nil }
        return path
    }

    /// Ruta efectiva de la TM según la preferencia de sync.
    var effectiveDBPath: String? {
        guard isICloudEnabled,
              let path = SyncManager.iCloudDBPath?.path else { return nil }
        return path
    }

    // MARK: - Activar sync (SYNC-03)

    /// Activa la sincronización con iCloud Drive.
    /// Crea la carpeta, migra los datos locales y persiste la preferencia.
    /// - Returns: nil si OK, mensaje de error si falló.
    @discardableResult
    func enableICloudSync() -> String? {
        guard let dir = SyncManager.iCloudDir else {
            return "iCloud Drive no está disponible en este Mac."
        }
        // Crear el directorio si no existe
        do {
            try FileManager.default.createDirectory(at: dir,
                                                    withIntermediateDirectories: true)
        } catch {
            return "No se pudo crear la carpeta en iCloud Drive: \(error.localizedDescription)"
        }

        // Migrar glosario local → iCloud (sin sobrescribir si ya existe)
        if let dst = SyncManager.iCloudGlossaryPath {
            let src = SyncManager.localGlossaryPath
            if FileManager.default.fileExists(atPath: src.path),
               !FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }

        // Migrar TM local → iCloud (sin sobrescribir si ya existe)
        if let dst = SyncManager.iCloudDBPath {
            let src = SyncManager.localDBPath
            if FileManager.default.fileExists(atPath: src.path),
               !FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }

        UserDefaults.standard.set(true, forKey: SyncManager.iCloudSyncKey)
        isICloudEnabled = true
        checkForConflicts()
        return nil
    }

    /// Desactiva la sincronización con iCloud Drive.
    /// Copia los datos de iCloud de vuelta a data/ local y persiste la preferencia.
    @discardableResult
    func disableICloudSync() -> String? {
        // Migrar glosario iCloud → local (sin sobrescribir si ya existe en local)
        if let src = SyncManager.iCloudGlossaryPath,
           FileManager.default.fileExists(atPath: src.path) {
            let dst = SyncManager.localGlossaryPath
            if !FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.copyItem(at: src, to: dst)
            } else {
                // Ya existe en local — ofrecer sobrescribir
                try? FileManager.default.replaceItemAt(dst, withItemAt: src)
            }
        }

        // Migrar TM iCloud → local (sin sobrescribir si ya existe)
        if let src = SyncManager.iCloudDBPath,
           FileManager.default.fileExists(atPath: src.path) {
            let dst = SyncManager.localDBPath
            if !FileManager.default.fileExists(atPath: dst.path) {
                try? FileManager.default.copyItem(at: src, to: dst)
            } else {
                try? FileManager.default.replaceItemAt(dst, withItemAt: src)
            }
        }

        UserDefaults.standard.set(false, forKey: SyncManager.iCloudSyncKey)
        isICloudEnabled = false
        syncWarning = nil
        return nil
    }

    // MARK: - Detección de conflictos SQLite (SYNC-04)

    /// Comprueba si la base de datos SQLite en iCloud está siendo usada por otro proceso.
    /// SQLite sobre iCloud Drive no es multi-escritor; emite aviso en la UI.
    func checkForConflicts() {
        guard isICloudEnabled, let dbURL = SyncManager.iCloudDBPath else {
            syncWarning = nil
            return
        }

        // Detectar archivos de bloqueo WAL/SHM de SQLite que indican conexión activa
        let walURL = dbURL.appendingPathExtension("wal")
        let shmURL = dbURL.appendingPathExtension("shm")
        let fm = FileManager.default

        let walExists = fm.fileExists(atPath: walURL.path)
        let shmExists = fm.fileExists(atPath: shmURL.path)

        // Detectar archivos .iCloud (aún no descargados por iCloud Drive)
        let iCloudPlaceholder = dbURL.deletingLastPathComponent()
            .appendingPathComponent(".\(SyncManager.dbFileName).icloud")
        let isPlaceholder = fm.fileExists(atPath: iCloudPlaceholder.path)

        if isPlaceholder {
            syncWarning = "La base de datos TM no se ha descargado aún desde iCloud Drive. " +
                          "Abre Finder y descárgala manualmente antes de traducir."
        } else if walExists || shmExists {
            syncWarning = "Advertencia: la base de datos TM parece estar en uso por otro Mac. " +
                          "SQLite sobre iCloud Drive no admite escritura simultánea. " +
                          "Cierra la app en el otro equipo antes de traducir aquí."
        } else {
            syncWarning = nil
        }
    }

    /// Llama a checkForConflicts() al arrancar la app (por si hubo sync en caliente).
    func onAppLaunch() {
        guard isICloudEnabled else { return }
        checkForConflicts()
    }
}
