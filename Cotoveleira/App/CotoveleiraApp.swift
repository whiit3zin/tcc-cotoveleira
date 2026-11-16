import SwiftUI
import SwiftData

@main struct CotoveleiraApp: App {
    @StateObject private var workout = WorkoutStore()
    @StateObject private var bluetooth = BluetoothManager()
    @AppStorage("theme") private var theme = AppTheme.system.rawValue

    private var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(workout)
                .environmentObject(bluetooth)
                .preferredColorScheme(AppTheme(rawValue: theme)?.colorScheme)
                .onReceive(workout.$phase) { phase in
                    LiveWorkoutService.shared.update(repetitions: workout.repetition, set: workout.set, phase: phase, demo: workout.demoMode)
                }
                .onReceive(workout.$repetition) { repetition in
                    LiveWorkoutService.shared.update(repetitions: repetition, set: workout.set, phase: workout.phase, demo: workout.demoMode)
                }
                .onChange(of: workout.demoMode) { _, demo in
                    bluetooth.demoMode = demo
                }
                .onReceive(bluetooth.$latestState) { state in
                    if bluetooth.configuration.count == 5 && !workout.demoMode {
                        workout.targetSets = bluetooth.configuration[0]
                        workout.targetRepetitions = bluetooth.configuration[1]
                        workout.restSeconds = bluetooth.configuration[2]
                        workout.syncRest(bluetooth.configuration[3])
                        workout.syncInterruption(bluetooth.configuration[4] & 1 != 0)
                    }
                    if let state { workout.applyDevice(repetition: state.repetition, set: state.set, phase: state.phase) }
                }
        }
        .modelContainer(for: WorkoutSession.self, inMemory: isUITesting)
    }
}
