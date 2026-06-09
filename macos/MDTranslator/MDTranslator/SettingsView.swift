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
            }
            .formStyle(.grouped)
            .frame(height: 400)

            // MARK: Banner Accesibilidad (hotkey ⌥⇧M)
            if !accessibilityGranted {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accesibilidad requerida para el atajo ⌥⇧M")
                            .font(.caption).bold()
                        Text("Activa MDTranslator en Ajustes del Sistema → Privacidad → Accesibilidad.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Abrir") {
                        GlobalHotkeyManager.shared.openAccessibilitySettings()
                        // Re-comprobar tras volver de Ajustes del Sistema (aprox. 3s)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            accessibilityGranted = GlobalHotkeyManager.shared.isAccessibilityGranted
                            if accessibilityGranted { GlobalHotkeyManager.shared.register() }
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))
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
