import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    let settings: SettingsStore
    let tokenProvider: DefaultTokenProvider
    let store: PRStore
    let notifier: Notifier

    var body: some View {
        TabView {
            GeneralTab(settings: settings, store: store, notifier: notifier)
                .tabItem { Label("Geral", systemImage: "gear") }

            ReposTab(settings: settings, store: store)
                .tabItem { Label("Repositórios", systemImage: "square.stack") }

            TokenTab(tokenProvider: tokenProvider, store: store)
                .tabItem { Label("Token", systemImage: "key") }
        }
        .frame(width: 420)
        .padding()
    }
}

// MARK: - Geral tab

private struct GeneralTab: View {
    @Bindable var settings: SettingsStore
    let store: PRStore
    let notifier: Notifier

    private let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("30 segundos", 30),
        ("1 minuto", 60),
        ("2 minutos", 120),
        ("5 minutos", 300)
    ]

    var body: some View {
        Form {
            Section {
                Picker("Intervalo de atualização:", selection: $settings.pollInterval) {
                    ForEach(intervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.pollInterval) {
                    store.settingsChanged()
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Iniciar ao fazer login", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.launchAtLogin = $0 }
                    ))
                    .disabled(!settings.isRunningFromApplications)

                    if !settings.isRunningFromApplications {
                        Text("Disponível apenas quando instalado em /Applications (use make install)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Notificações:") {
                Toggle("Nova review solicitada", isOn: $settings.notifyReviewRequested)
                Toggle("Minha PR aprovada", isOn: $settings.notifyPRApproved)
                Toggle("Mudanças solicitadas na minha PR", isOn: $settings.notifyPRChangesRequested)
            }

            Section {
                Button("Testar notificação") {
                    notifier.postTest()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Repositórios tab

private struct ReposTab: View {
    @Bindable var settings: SettingsStore
    let store: PRStore

    @State private var newRepoInput = ""
    @State private var addError: String? = nil

    private var isInputValid: Bool {
        RepoConfig.parse(newRepoInput) != nil
    }

    private var isDuplicate: Bool {
        guard let config = RepoConfig.parse(newRepoInput) else { return false }
        return settings.repoStrings.contains { $0.lowercased() == config.id.lowercased() }
    }

    private var canAdd: Bool {
        isInputValid && !isDuplicate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if settings.repoStrings.isEmpty {
                Text("Nenhum repositório configurado.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                List {
                    ForEach(settings.repoStrings, id: \.self) { repo in
                        HStack {
                            Text(repo)
                                .font(.body)
                            Spacer()
                            Button {
                                settings.removeRepo(repo)
                                store.settingsChanged()
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remover repositório")
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        settings.removeRepo(atOffsets: offsets)
                        store.settingsChanged()
                    }
                }
                .listStyle(.bordered)
                .frame(minHeight: 120)
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("owner/repositório", text: $newRepoInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { attemptAdd() }

                    Text("Ex.: vercel/next.js")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if let error = addError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Button("Adicionar") {
                    attemptAdd()
                }
                .disabled(!canAdd)
                .padding(.top, 2)
            }
        }
        .padding()
    }

    private func attemptAdd() {
        guard canAdd else { return }
        if let error = settings.addRepo(newRepoInput) {
            addError = error
        } else {
            newRepoInput = ""
            addError = nil
            store.settingsChanged()
        }
    }
}

// MARK: - Token tab

private struct TokenTab: View {
    let tokenProvider: DefaultTokenProvider
    let store: PRStore

    @State private var sourceDescription = ""
    @State private var patInput = ""

    private var hasPAT: Bool {
        sourceDescription.contains("PAT")
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Origem atual:", value: sourceDescription)
            }

            Section {
                SecureField("Personal Access Token (opcional)", text: $patInput)

                HStack {
                    Button("Salvar") {
                        Task {
                            await tokenProvider.setPAT(patInput)
                            await tokenProvider.invalidate()
                            patInput = ""
                            sourceDescription = await tokenProvider.sourceDescription()
                            store.refreshNow()
                        }
                    }
                    .disabled(patInput.isEmpty)

                    Button("Remover PAT") {
                        Task {
                            await tokenProvider.clearPAT()
                            await tokenProvider.invalidate()
                            sourceDescription = await tokenProvider.sourceDescription()
                            store.refreshNow()
                        }
                    }
                    .disabled(!hasPAT)
                }
            }

            Section {
                Text("Por padrão usa o token do gh CLI. Defina um PAT para sobrescrever (escopo repo).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            sourceDescription = await tokenProvider.sourceDescription()
        }
    }
}
