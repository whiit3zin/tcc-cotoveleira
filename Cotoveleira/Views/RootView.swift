import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var workout: WorkoutStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        TabView {
            TrainingView().tabItem { Label("Treino", systemImage: "figure.strengthtraining.traditional") }
            RestView().tabItem { Label("Descanso", systemImage: "timer") }
            DeviceView().tabItem { Label("Dispositivo", systemImage: "sensor.tag.radiowaves.forward") }
            HistoryView().tabItem { Label("Histórico", systemImage: "clock.arrow.circlepath") }
            SettingsView().tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
        .tint(Palette.blue(scheme == .dark))
    }
}

struct Screen<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.colorScheme) private var scheme
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(title).font(.largeTitle.bold()).padding(.top, 12)
                    content
                }.padding(20)
            }
            .background(Palette.background(scheme == .dark))
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct TrainingView: View {
    @EnvironmentObject private var workout: WorkoutStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Screen("Treino") {
            if workout.demoMode { Label("Modo demonstração", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary) }
            Card {
                HStack { Circle().fill(workout.phase == .active ? Palette.green(scheme == .dark) : Palette.secondary(scheme == .dark)).frame(width: 8, height: 8)
                    Text(status).font(.subheadline.weight(.medium)) }
                ProgressRing(value: workout.progress, current: workout.repetition, target: workout.targetRepetitions)
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                Text("Série \(workout.set) de \(workout.targetSets)").font(.headline).frame(maxWidth: .infinity)
            }
            Button(action: primaryAction) { Text(primaryTitle).frame(maxWidth: .infinity).padding(12) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            if workout.phase == .active && workout.demoMode {
                Button("Adicionar repetição") { workout.addRepetition() }.frame(maxWidth: .infinity)
            }
            if workout.phase != .idle && workout.phase != .completed {
                Button("Finalizar e salvar treino") {
                    if !workout.demoMode { bluetooth.send(4) }
                    workout.finish(in: context)
                }
                    .foregroundStyle(Palette.red).frame(maxWidth: .infinity)
            }
            if workout.phase == .completed { Text("Treino concluído").font(.headline).foregroundStyle(Palette.green(scheme == .dark)) }
        }
        .onChange(of: workout.phase) { _, phase in
            if phase == .completed { workout.finish(in: context) }
        }
    }
    private var status: String {
        switch workout.phase { case .idle: "Aguardando início"; case .active: "Em andamento"; case .paused: "Pausado"; case .resting: "Descanso"; case .completed: "Concluído" }
    }
    private var primaryTitle: String {
        switch workout.phase { case .idle, .completed: "Iniciar treino"; case .active: "Pausar treino"; case .paused: "Retomar treino"; case .resting: "Em descanso" }
    }
    private func primaryAction() {
        switch workout.phase {
        case .idle, .completed:
            workout.start()
            if !workout.demoMode {
                bluetooth.send(6, value: UInt16(workout.targetSets))
                bluetooth.send(7, value: UInt16(workout.targetRepetitions))
                bluetooth.send(8, value: UInt16(workout.restSeconds))
                bluetooth.send(1)
            }
        case .active:
            workout.pauseOrResume()
            if !workout.demoMode { bluetooth.send(2) }
        case .paused:
            workout.pauseOrResume()
            if !workout.demoMode { bluetooth.send(3) }
        case .resting: break
        }
    }
}

struct ProgressRing: View {
    let value: Double
    let current: Int
    let target: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Circle().stroke(Palette.blue(scheme == .dark).opacity(0.13), lineWidth: 14)
            Circle().trim(from: 0, to: min(1, max(0, value)))
                .stroke(Palette.blue(scheme == .dark), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text("\(current)").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                Text("de \(target) repetições").font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(width: 240, height: 240)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(current) de \(target) repetições")
    }
}

struct RestView: View {
    @EnvironmentObject private var workout: WorkoutStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Screen("Descanso") {
            Card {
                Label("Tempo restante", systemImage: "timer").foregroundStyle(Palette.orange(scheme == .dark))
                Text(workout.clock).font(.system(size: 72, weight: .bold, design: .rounded)).monospacedDigit()
                    .frame(maxWidth: .infinity).padding(.vertical, 35)
                    .accessibilityLabel("\(workout.remaining) segundos restantes")
                Text(workout.phase == .resting ? "Próxima: série \(workout.set + 1) de \(workout.targetSets)" : "O descanso começa após cada série.")
                    .foregroundStyle(.secondary)
            }
            Button("Pular descanso") {
                if !workout.demoMode { bluetooth.send(5) }
                workout.skipRest()
            }
                .buttonStyle(.borderedProminent).tint(Palette.orange(scheme == .dark))
                .frame(maxWidth: .infinity).disabled(workout.phase != .resting)
        }
    }
}
