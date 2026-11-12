import SwiftUI
import SwiftData

struct DeviceView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var workout: WorkoutStore
    var body: some View {
        NavigationStack {
            Form {
                Section("Cotoveleira Inteligente") {
                    Label(workout.demoMode ? "Modo demonstração" : bluetooth.status,
                          systemImage: "sensor.tag.radiowaves.forward")
                    LabeledContent("Bateria", value: bluetooth.battery.map { "\($0)%" } ?? "Indisponível")
                    if !workout.demoMode {
                        Button(bluetooth.status == "Conectado" ? "Desconectar" : "Procurar cotoveleira") {
                            if bluetooth.status == "Conectado" { bluetooth.disconnect() } else { bluetooth.scan() }
                        }
                    }
                }
                Section("Configuração do treino") {
                    LabeledContent("Séries", value: "\(workout.targetSets)")
                    LabeledContent("Repetições", value: "\(workout.targetRepetitions)")
                    LabeledContent("Descanso", value: "\(workout.restSeconds) segundos")
                }
            }
            .appFormStyle().navigationTitle("Dispositivo")
        }
    }
}

struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView("Nenhum treino ainda", systemImage: "clock",
                        description: Text("Seus treinos salvos aparecerão aqui."))
                        .listRowBackground(Color.clear)
                }
                ForEach(sessions) { session in
                    NavigationLink {
                        Form {
                            Section(session.outcomeTitle) {
                                Text(session.localizedDate)
                                LabeledContent("Séries concluídas", value: "\(session.completedSets)")
                                LabeledContent("Repetições", value: "\(session.totalRepetitions)")
                                LabeledContent("Duração", value: "\(session.duration / 60) min \(session.duration % 60) s")
                                LabeledContent("Origem", value: session.isDemo ? "Demonstração" : "Cotoveleira BLE")
                            }
                        }.appFormStyle().navigationTitle("Treino salvo").navigationBarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.outcomeTitle).font(.headline)
                            Text(session.localizedDate).font(.subheadline)
                            Text("\(session.completedSets) séries concluídas • \(session.totalRepetitions) repetições")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if session.isDemo { Text("Modo demonstração").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }
                }
            }
            .appFormStyle().navigationTitle("Histórico")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var workout: WorkoutStore
    @AppStorage("theme") private var theme = AppTheme.system.rawValue
    var body: some View {
        NavigationStack {
            Form {
                Section("Aparência") {
                    Picker("Tema", selection: $theme) {
                        ForEach(AppTheme.allCases) { theme in Text(theme.rawValue).tag(theme.rawValue) }
                    }
                }
                Section {
                    Toggle("Modo demonstração", isOn: $workout.demoMode)
                        .disabled(workout.isRunning)
                } footer: {
                    Text(workout.isRunning ? "Finalize o treino para alterar a origem dos dados e a configuração." : "Simula repetições sem precisar conectar o ESP32.")
                }
                Section("Treino") {
                    Stepper("Séries: \(workout.targetSets)", value: $workout.targetSets, in: 1...10)
                    Stepper("Repetições por série: \(workout.targetRepetitions)", value: $workout.targetRepetitions, in: 1...100)
                    Stepper("Descanso: \(workout.restSeconds) s", value: $workout.restSeconds, in: 5...300, step: 5)
                }.disabled(workout.isRunning)
                Section("Sobre o projeto") {
                    Text("Cotoveleira Inteligente · TCC técnico")
                    Text("A sensibilidade do sensor depende de suporte no firmware ESP32.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .appFormStyle().navigationTitle("Ajustes")
        }
    }
}

private struct AppFormStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
            .background(Palette.background(scheme == .dark).ignoresSafeArea())
    }
}
extension View {
    func appFormStyle() -> some View { modifier(AppFormStyle()) }
}
