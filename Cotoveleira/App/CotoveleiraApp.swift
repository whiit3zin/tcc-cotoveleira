import SwiftUI
import SwiftData

@main struct CotoveleiraApp: App {
    @StateObject private var workout = WorkoutStore()
    @StateObject private var bluetooth = BluetoothManager()
    @AppStorage("theme") private var theme = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(workout)
                .environmentObject(bluetooth)
                .preferredColorScheme(AppTheme(rawValue: theme)?.colorScheme)
                .onReceive(bluetooth.$latestState) { state in
                    if let state { workout.applyDevice(repetition: state.repetition, set: state.set, phase: state.phase) }
                }
        }
        .modelContainer(for: WorkoutSession.self)
    }
}
