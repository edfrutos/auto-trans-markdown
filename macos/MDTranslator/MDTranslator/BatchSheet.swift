// BatchSheet.swift — Vista SwiftUI de lote con tres estados diferenciados.
// Consumidor puro de BatchJobManager.shared; no contiene lógica de negocio.
// Estados: .prepared (confirmar lote), .running/.cancelling (progreso con barras determinadas),
// .done (resumen final con errores y botones Cerrar + Mostrar en Finder).
// Sigue el patrón de SettingsView.swift: VStack + cabecera HStack + Divider + cuerpo.
import SwiftUI

struct BatchSheet: View {
    @Binding var isPresented: Bool
    /// Manager observable singleton — fuente de verdad de todo el estado del lote.
    var manager: BatchJobManager
    /// Referencia al ServerManager para leer serverPort antes de llamar a start().
    var serverManager: ServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Cabecera
            HStack {
                Image(systemName: "tray.and.arrow.up.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Traducir lote")
                    .font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            // MARK: Cuerpo principal — conmuta según el estado del job
            switch manager.jobState {

            // ---------------------------------------------------------------
            // RAMA 1: Preparado — lista de archivos + idioma + botón Traducir
            // ---------------------------------------------------------------
            case .prepared(let urls):
                VStack(alignment: .leading, spacing: 12) {

                    Text("Archivos seleccionados (\(urls.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(urls, id: \.self) { url in
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 24)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 24)

                    let lang = UserDefaults.standard.string(forKey: "defaultTargetLang") ?? "es"
                    Text("Idioma destino: \(lang)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)

                    Divider()

                    HStack {
                        Button("Cancelar") {
                            manager.reset()
                            isPresented = false
                        }
                        .keyboardShortcut(.escape)

                        Spacer()

                        Button("Traducir") {
                            let targetLang = UserDefaults.standard.string(forKey: "defaultTargetLang") ?? "es"
                            let port = serverManager.serverPort
                            Task {
                                await manager.start(port: port, targetLang: targetLang)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return)
                        .disabled(serverManager.state != .running)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

            // ---------------------------------------------------------------
            // RAMA 2a: En progreso — barras determinadas + Cancelar + Continuar
            // ---------------------------------------------------------------
            case .running:
                progressBody(isCancelling: false)

            // ---------------------------------------------------------------
            // RAMA 2b: Cancelando — misma vista con feedback cooperativo
            // ---------------------------------------------------------------
            case .cancelling:
                progressBody(isCancelling: true)

            // ---------------------------------------------------------------
            // RAMA 3: Completado — resumen con errores y botones finales
            // ---------------------------------------------------------------
            case .done(let ok, let errors, let cancelled):
                VStack(alignment: .leading, spacing: 12) {

                    // Subtítulo de resumen (D-08: indicar "Cancelado" si cancelled)
                    let subtitle: String = {
                        if cancelled {
                            return "Cancelado: \(ok) de \(manager.totalCount) traducidos"
                        } else if errors.isEmpty {
                            return "\(ok) archivo\(ok == 1 ? "" : "s") traducido\(ok == 1 ? "" : "s") correctamente"
                        } else {
                            return "\(ok) traducido\(ok == 1 ? "" : "s") · \(errors.count) error\(errors.count == 1 ? "" : "es")"
                        }
                    }()

                    Text(subtitle)
                        .font(.subheadline)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    // Lista de errores individuales si los hay
                    if !errors.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(errors, id: \.0) { (filename, msg) in
                                    Text("• \(filename): \(msg)")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 24)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 24)
                    }

                    Divider()

                    HStack {
                        Button("Cerrar") {
                            manager.reset()
                            isPresented = false
                        }
                        .keyboardShortcut(.escape)

                        Spacer()

                        Button("Mostrar en Finder") {
                            OutputManager.shared.revealOutputFolder()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

            // ---------------------------------------------------------------
            // RAMA DEFAULT: .idle — la sheet no debería mostrarse en este estado
            // ---------------------------------------------------------------
            default:
                EmptyView()
            }
        }
        .frame(minWidth: 480, minHeight: 300)
    }

    // MARK: - Vista de progreso (compartida entre .running y .cancelling)

    @ViewBuilder
    private func progressBody(isCancelling: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            // Mensaje de estado .cancelling
            if isCancelling {
                Text("Cancelando — terminando archivo en curso…")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            } else {
                Spacer().frame(height: 16)
            }

            // Nombre del archivo en curso
            Text(manager.currentFile.isEmpty ? "Preparando…" : manager.currentFile)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 24)

            // Barra global determinada (archivos completados / total)
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(manager.filesDone), total: Double(max(manager.filesTotal, 1)))
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 24)

                Text("\(manager.filesDone) de \(manager.filesTotal) archivos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            // Barra de segmentos del archivo en curso
            if manager.segmentsTotal > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(manager.segmentsDone), total: Double(max(manager.segmentsTotal, 1)))
                        .progressViewStyle(.linear)
                        .tint(.secondary)
                        .padding(.horizontal, 24)

                    Text("Segmento \(manager.segmentsDone)/\(manager.segmentsTotal)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }
            }

            Divider()

            HStack {
                Button("Continuar en segundo plano") {
                    isPresented = false
                }

                Spacer()

                Button("Cancelar") {
                    manager.cancel()
                }
                .disabled(isCancelling)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

#Preview {
    BatchSheet(
        isPresented: .constant(true),
        manager: BatchJobManager.shared,
        serverManager: ServerManager()
    )
}
