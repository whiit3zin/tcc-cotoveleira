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
                    if !workout.demoMode {
                        LabeledContent("Energia", value: bluetooth.powered.map { $0 ? "Em funcionamento" : "Standby virtual" } ?? "Indisponível")
                        Button(bluetooth.powered == true ? "Colocar em standby" : "Ligar cotoveleira") {
                            bluetooth.send(9, value: bluetooth.powered == true ? 0 : 1)
                        }.disabled(!bluetooth.ready || bluetooth.powered == nil || workout.isRunning)
                        Text("Standby mantém a conexão Bluetooth disponível.").font(.footnote).foregroundStyle(.secondary)
                    }
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
    @State private var taps = 0
    @State private var lastTap = Date.distantPast
    @State private var engineering = false
    @AppStorage("haptics") private var haptics = true
    @AppStorage("theme") private var theme = AppTheme.system.rawValue
    var body: some View {
        NavigationStack {
            Form {
                Section("Aparência") {
                    Picker("Tema", selection: $theme) {
                        ForEach(AppTheme.allCases) { theme in Text(theme.rawValue).tag(theme.rawValue) }
                    }
                }
                Section("Feedback") {
                    Toggle("Feedback háptico", isOn: $haptics)
                    Button("Permitir notificações do treino") { HapticService.shared.requestNotifications() }
                }
                Section("Treino") {
                    Stepper("Séries: \(workout.targetSets)", value: $workout.targetSets, in: 1...10)
                    Stepper("Repetições por série: \(workout.targetRepetitions)", value: $workout.targetRepetitions, in: 1...100)
                    Stepper("Descanso: \(workout.restSeconds) s", value: $workout.restSeconds, in: 5...300, step: 5)
                }.disabled(workout.isRunning)
                Section("Sobre o projeto") {
                    Text("Cotoveleira Inteligente · TCC técnico")
                    Text("Versão \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .accessibilityIdentifier("settings.version")
                        .onTapGesture {
                            taps = Date.now.timeIntervalSince(lastTap) < 2 ? taps + 1 : 1
                            lastTap = .now
                            if taps == 5 { taps = 0; HapticService.shared.play(.unlock); engineering = true }
                        }
                }
            }
            .appFormStyle().navigationTitle("Ajustes")
            .sheet(isPresented: $engineering) { EngineeringView() }
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
