import SwiftUI
import SwiftData

struct DeviceView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var workout: WorkoutStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Screen("Dispositivo") {
            Card {
                Label("Cotoveleira Inteligente", systemImage: "bluetooth").font(.headline)
                Text(workout.demoMode ? "Modo demonstração" : bluetooth.status)
                    .foregroundStyle(workout.demoMode ? Palette.orange(scheme == .dark) : (bluetooth.status == "Conectado" ? Palette.green(scheme == .dark) : Palette.secondary(scheme == .dark)))
                    .padding(.top, 8)
                Text(bluetooth.battery.map { "Bateria: \($0)%" } ?? "Bateria indisponível")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.top, 4)
            }
            Card {
                Text("Configuração do treino").font(.headline)
                LabeledContent("Séries", value: "\(workout.targetSets)")
                LabeledContent("Repetições", value: "\(workout.targetRepetitions)")
                LabeledContent("Descanso", value: "\(workout.restSeconds) segundos")
            }
            if !workout.demoMode {
                Button(bluetooth.status == "Conectado" ? "Desconectar" : "Procurar cotoveleira") {
                    if bluetooth.status == "Conectado" { bluetooth.disconnect() } else { bluetooth.scan() }
                }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            }
        }
    }
}

struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    var body: some View {
        Screen("Histórico") {
            if sessions.isEmpty { Card { ContentUnavailableView("Nenhum treino ainda", systemImage: "clock", description: Text("Seus treinos concluídos aparecerão aqui.")) } }
            ForEach(sessions) { session in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.startedAt, format: .dateTime.day().month().year().hour().minute()).font(.headline)
                        if session.isDemo { Text("Modo demonstração").font(.caption).foregroundStyle(.secondary) }
                        Text("\(session.completedSets) séries • \(session.totalRepetitions) repetições")
                        Text("Duração: \(session.duration / 60) min \(session.duration % 60) s").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var workout: WorkoutStore
    @AppStorage("theme") private var theme = AppTheme.system.rawValue
    var body: some View {
        Screen("Ajustes") {
            Card {
                Picker("Tema", selection: $theme) { ForEach(AppTheme.allCases) { theme in Text(theme.rawValue).tag(theme.rawValue) } }
                Toggle("Modo demonstração", isOn: $workout.demoMode)
            }
            Card {
                Stepper("Séries: \(workout.targetSets)", value: $workout.targetSets, in: 1...10)
                Stepper("Repetições por série: \(workout.targetRepetitions)", value: $workout.targetRepetitions, in: 1...100)
                Stepper("Descanso: \(workout.restSeconds) s", value: $workout.restSeconds, in: 5...300, step: 5)
            }
            Card {
                Text("Sobre o projeto").font(.headline)
                Text("Cotoveleira Inteligente · TCC técnico").foregroundStyle(.secondary)
                Text("A sensibilidade do sensor depende de suporte no firmware ESP32.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
