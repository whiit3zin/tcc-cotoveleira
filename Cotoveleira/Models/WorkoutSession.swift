import Foundation
import SwiftData

@Model final class WorkoutSession {
    var startedAt: Date
    var duration: Int
    var completedSets: Int
    var totalRepetitions: Int
    var isDemo: Bool
    // Optional for lightweight migration of sessions saved by version 1.
    var wasInterrupted: Bool? = nil

    init(startedAt: Date, duration: Int, completedSets: Int, totalRepetitions: Int, isDemo: Bool, wasInterrupted: Bool? = nil) {
        self.startedAt = startedAt
        self.duration = duration
        self.completedSets = completedSets
        self.totalRepetitions = totalRepetitions
        self.isDemo = isDemo
        self.wasInterrupted = wasInterrupted
    }
}

enum WorkoutPhase: UInt8 {
    case idle = 0, active = 1, paused = 2, resting = 3, completed = 4
}


extension WorkoutSession {
    var outcomeTitle: String {
        if wasInterrupted == true || (wasInterrupted == nil && completedSets == 0 && totalRepetitions > 0) {
            return "Treino interrompido"
        }
        return wasInterrupted == nil ? "Treino registrado" : "Treino concluído"
    }

    var localizedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy', às' HH:mm"
        return formatter.string(from: startedAt)
    }
}
