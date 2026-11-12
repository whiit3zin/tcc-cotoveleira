import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        TabView {
            Tab("Treino", systemImage: "figure.strengthtraining.traditional") { TrainingView() }
            Tab("Histórico", systemImage: "clock.arrow.circlepath") { HistoryView() }
            Tab("Dispositivo", systemImage: "sensor.tag.radiowaves.forward") { DeviceView() }
            Tab("Ajustes", systemImage: "gearshape") { SettingsView() }
        }
        .tint(Palette.blue(scheme == .dark))
    }
}

// NavigationStack and ScrollView own the safe areas. Only the background extends.
struct Screen<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.colorScheme) private var scheme
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { content }
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                    .padding(.horizontal, 20).padding(.top, 16)
            }
            .safeAreaPadding(.bottom, 24)
            .background(Palette.background(scheme == .dark).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
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
            if workout.demoMode {
                Label("Modo demonstração", systemImage: "play.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if workout.phase == .resting {
                RestView()
            } else {
                Card {
                    Label(status, systemImage: workout.phase == .active ? "circle.fill" : "circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(workout.phase == .active ? Palette.green(scheme == .dark) : Palette.secondary(scheme == .dark))
                    ProgressRing(value: workout.progress, current: workout.repetition, target: workout.targetRepetitions)
                    Text("Série \(workout.set) de \(workout.targetSets)")
                        .font(.headline).frame(maxWidth: .infinity)
                }
                Button(action: primaryAction) {
                    Text(primaryTitle).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("workout.primary")
                .disabled(!workout.demoMode && bluetooth.status != "Conectado")
                if !workout.demoMode && bluetooth.status != "Conectado" {
                    Text("Conecte a cotoveleira na aba Dispositivo para iniciar ou retomar o treino.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if workout.phase == .active && workout.demoMode {
                    Button("Adicionar repetição") { workout.addRepetition() }
                        .accessibilityIdentifier("workout.addRepetition")
                        .frame(maxWidth: .infinity).buttonStyle(.bordered)
                }
            }
            NavigationLink {
                WorkoutDetailsView()
            } label: {
                Label("Detalhes do treino e descanso", systemImage: "list.bullet.rectangle")
                    .font(.subheadline)
            }
            if workout.isRunning {
                Button("Finalizar e salvar treino", role: .destructive) {
                    if !workout.demoMode { bluetooth.send(4) }
                    workout.finish(in: context)
                }
                .accessibilityIdentifier("workout.finish")
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
        }
        .onChange(of: workout.phase) { _, phase in
            if phase == .completed { workout.finish(in: context) }
        }
    }
    private var status: String {
        switch workout.phase {
        case .idle: "Aguardando início"
        case .active: "Em andamento"
        case .paused: "Pausado"
        case .resting: "Descanso"
        case .completed: workout.wasInterrupted ? "Treino interrompido" : "Treino concluído"
        }
    }
    private var primaryTitle: String {
        switch workout.phase {
        case .idle, .completed: "Iniciar treino"
        case .active: "Pausar treino"
        case .paused: "Retomar treino"
        case .resting: "Em descanso"
        }
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
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 56.0
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Palette.blue(scheme == .dark).opacity(0.13), lineWidth: 12)
                Circle().trim(from: 0, to: min(1, max(0, value)))
                    .stroke(Palette.blue(scheme == .dark), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(current)").font(.system(size: numberSize, weight: .bold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1).padding(24)
            }
            .padding(6).aspectRatio(1, contentMode: .fit).frame(maxWidth: 232)
            Text("de \(target) repetições").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(current) de \(target) repetições")
        .accessibilityIdentifier("workout.progress")
    }
}

// Embedded in Treino, and also available from its details screen.
struct RestView: View {
    @EnvironmentObject private var workout: WorkoutStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Card {
            Label("Descanso", systemImage: "timer").font(.title2.bold())
                .foregroundStyle(Palette.orange(scheme == .dark))
            if workout.phase == .resting {
                Text(workout.clock).font(.system(.largeTitle, design: .rounded).bold())
                    .monospacedDigit().frame(maxWidth: .infinity).padding(.vertical, 12)
                    .accessibilityLabel("\(workout.remaining) segundos restantes")
                    .accessibilityIdentifier("rest.countdown")
                Text("Próxima: série \(workout.set + 1) de \(workout.targetSets)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Pular descanso") {
                    if !workout.demoMode { bluetooth.send(5) }
                    workout.skipRest()
                }
                .accessibilityIdentifier("rest.skip")
                .buttonStyle(.borderedProminent).tint(Palette.orange(scheme == .dark))
            } else if workout.restCompleted {
                Label("Descanso concluído", systemImage: "checkmark.circle")
                    .foregroundStyle(Palette.green(scheme == .dark))
                Text("Continue a próxima série. O contador aparecerá novamente no próximo intervalo.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Descanso não iniciado").font(.headline)
                Text("Ao concluir uma série, o intervalo de \(workout.restSeconds) segundos começa aqui automaticamente.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct WorkoutDetailsView: View {
    @EnvironmentObject private var workout: WorkoutStore
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Card {
                    LabeledContent("Séries", value: "\(workout.targetSets)")
                    LabeledContent("Repetições por série", value: "\(workout.targetRepetitions)")
                    LabeledContent("Repetições realizadas", value: "\(workout.total)")
                }
                RestView()
            }.padding(20)
        }
        .navigationTitle("Detalhes").navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Treino — escuro") {
    RootView().environmentObject(WorkoutStore()).environmentObject(BluetoothManager())
        .modelContainer(for: WorkoutSession.self, inMemory: true).preferredColorScheme(.dark)
}
#Preview("Treino — texto maior") {
    RootView().environmentObject(WorkoutStore()).environmentObject(BluetoothManager())
        .modelContainer(for: WorkoutSession.self, inMemory: true).environment(\.dynamicTypeSize, .accessibility3)
}
