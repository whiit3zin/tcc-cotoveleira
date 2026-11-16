import ActivityKit
import UIKit

@MainActor final class LiveWorkoutService {
    static let shared = LiveWorkoutService()
    func update(repetitions: Int, set: Int, phase: WorkoutPhase, demo: Bool) {
        let state = WorkoutActivity.ContentState(repetitions: repetitions, set: set,
            phase: ["Pronto", "Treinando", "Pausado", "Descanso", "Concluído"][Int(phase.rawValue)], demo: demo)
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(15))
        let running = phase != .idle && phase != .completed
        if Activity<WorkoutActivity>.activities.isEmpty && running && UIApplication.shared.applicationState == .active && ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: WorkoutActivity(title: "Cotoveleira"), content: content)
        }
        for activity in Activity<WorkoutActivity>.activities {
            Task {
                if running { await activity.update(content) }
                else { await activity.end(content, dismissalPolicy: .default) }
            }
        }
    }
}
