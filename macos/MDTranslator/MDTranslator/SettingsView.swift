// SettingsView.swift — Configuración de API keys y carpeta de salida para MD Translator.
// Se muestra en primera ejecución (sin keys en Keychain) y desde el menú ⌘,.
// Las keys se guardan en el Keychain del sistema, nunca en disco ni en logs.
import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    /// Referencia al ServerManager para reiniciar el servidor tras un cambio de provider.
    var serverManager: ServerManager

    @State private var openAIKey = KeychainManager.load(account: KeychainManager.openAIKeyAccount) ?? ""
    @State private var deepLKey  = KeychainManager.load(account: KeychainManager.deepLKeyAccount)  ?? ""
    @State private var provider  = KeychainManager.load(account: KeychainManager.providerAccount)  ?? "openai"

    @State private var saveError: String?
    @State private var saved = false
    @State private var outputFolderName: String? = OutputManager.shared.outputFolderName
    @State private var accessibilityGranted = GlobalHotkeyManager.shared.isAccessibilityGranted
    // CRASH-01: opt-in diagnóstico — persiste en UserDefaults a través de @AppStorage.
    @AppStorage(CrashReporterManager.sendReportsKey) private var sendCrashReports = false
    // SYNC-01: estado local del toggle, sincronizado con SyncManager al guardar.
    @State private var iCloudSyncEnabled = SyncManager.shared.isICloudEnabled
    @State private var syncActionError: String?

    private var canSave: Bool {
        !openAIKey.trimmingCharacters(in: .whitespaces).isEmpty ||
        !deepLKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Cabecera
            HStack {
                Image(systemName: "key.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Configuración de API Keys")
                    .font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            // MARK: Formulario
            Form {
                Section {
                    Picker("Proveedor activo", selection: $provider) {
                        Text("OpenAI").tag("openai")
                        Text("DeepL").tag("deepl")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Proveedor de traducción")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    SecureField("sk-…", text: $openAIKey)
                        .textContentType(.password)
                    Text("Necesaria para el proveedor OpenAI (modelo gpt-4o-mini por defecto).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("OpenAI API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    SecureField("", text: $deepLKey)
                        .textContentType(.password)
                    Text("Necesaria para el proveedor DeepL.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("DeepL API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        if let name = outputFolderName {
                            Label(name, systemImage: "folder.fill")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No configurada — se usará el diálogo de guardar")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Elegir…") {
                            OutputManager.shared.chooseFolderAndSave()
                            outputFolderName = OutputManager.shared.outputFolderName
                        }
                        if outputFolderName != nil {
                            Button(role: .destructive) {
                                OutputManager.shared.clearOutputFolder()
                                outputFolderName = nil
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Text("Cuando hay carpeta configurada, los archivos se guardan automáticamente y se revelan en Finder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Carpeta de salida")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // SYNC-01: sincronización de glosario y TM en iCloud Drive.
                Section {
                    Toggle("Sincronizar datos vía iCloud Drive", isOn: $iCloudSyncEnabled)
                        .onChange(of: iCloudSyncEnabled) { _, newValue in
                            applyICloudSync(enabled: newValue)
                        }
                    if let warning = SyncManager.shared.syncWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let err = syncActionError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text("Mueve el glosario y la memoria de traducción a iCloud Drive " +
                         "(~/Library/Mobile Documents/com~apple~CloudDocs/MDTranslator/) " +
                         "para compartirlos entre Macs. SQLite no admite escritura simultánea: " +
                         "úsalo desde un solo Mac a la vez.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Sincronización")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // CRASH-01: opt-in informes de diagnóstico anónimos.
                Section {
                    Toggle("Enviar informes de diagnóstico anónimos", isOn: $sendCrashReports)
                    Text("Si la app se cierra de forma inesperada, en el siguiente arranque se ofrecerá enviar un informe al autor. No se incluyen API keys, contenido personal ni texto traducido.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacidad")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(height: 590)

            // MARK: Banner Accesibilidad (hotkey ⌥⇧M)
            // Tras una actualización Sparkle, macOS revoca el permiso porque la firma cambia.
            // El usuario debe eliminar la entrada antigua y volver a añadirla.
            if !accessibilityGranted {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accesibilidad requerida para el atajo ⌥⇧M")
                            .font(.caption).bold()
                        Text("En Privacidad → Accesibilidad: elimina MDTranslator y vuelve a añadirlo. Tras una actualización esto es necesario.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        Button("Abrir Ajustes") {
                            GlobalHotkeyManager.shared.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.orange)
                        Button("Recomprobar") {
                            accessibilityGranted = GlobalHotkeyManager.shared.isAccessibilityGranted
                            if accessibilityGranted { GlobalHotkeyManager.shared.register() }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))
                // Polling automático cada 2 s mientras el banner está visible.
                .task {
                    while !accessibilityGranted {
                        try? await Task.sleep(for: .seconds(2))
                        await MainActor.run {
                            accessibilityGranted = GlobalHotkeyManager.shared.isAccessibilityGranted
                            if accessibilityGranted { GlobalHotkeyManager.shared.register() }
                        }
                    }
                }
            }

            // MARK: Mensaje de error
            if let err = saveError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            Divider()

            // MARK: Botones
            HStack {
                Button("Cancelar") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Guardar") {
                    saveKeys()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return)
            }
            .padding(20)
        }
        .frame(width: 460)
        .onAppear { accessibilityGranted = GlobalHotkeyManager.shared.isAccessibilityGranted }
        .alert("Keys guardadas", isPresented: $saved) {
            Button("OK") { isPresented = false }
        } message: {
            Text("Las API keys se han guardado en el Keychain. El servidor se reinicia automáticamente con la nueva configuración.")
        }
    }

    // MARK: - iCloud sync

    /// Aplica el cambio de preferencia de iCloud sync y reinicia el servidor.
    private func applyICloudSync(enabled: Bool) {
        syncActionError = nil
        let sync = SyncManager.shared
        let error: String?
        if enabled {
            error = sync.enableICloudSync()
        } else {
            error = sync.disableICloudSync()
        }
        if let err = error {
            syncActionError = err
            // Revertir el toggle si la operación falló
            iCloudSyncEnabled = !enabled
            return
        }
        // El servidor necesita reiniciarse para que las nuevas env vars surtan efecto.
        serverManager.stop()
        Task { await serverManager.start() }
    }

    // MARK: - Guardar en Keychain

    private func saveKeys() {
        saveError = nil
        do {
            try KeychainManager.save(account: KeychainManager.openAIKeyAccount,
                                     value: openAIKey.trimmingCharacters(in: .whitespaces))
            try KeychainManager.save(account: KeychainManager.deepLKeyAccount,
                                     value: deepLKey.trimmingCharacters(in: .whitespaces))
            try KeychainManager.save(account: KeychainManager.providerAccount,
                                     value: provider)
            // Notificar a SplashView (primera ejecución) que ya hay keys disponibles.
            NotificationCenter.default.post(name: .settingsSaved, object: nil)
            saved = true
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView(isPresented: .constant(true), serverManager: ServerManager())
}
