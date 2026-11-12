import Foundation
import SwiftData

@Model final class WorkoutSession {
    var startedAt: Date
    var duration: Int
    var completedSets: Int
    var totalRepetitions: Int
    var isDemo: Bool

    init(startedAt: Date, duration: Int, completedSets: Int, totalRepetitions: Int, isDemo: Bool) {
        self.startedAt = startedAt
        self.duration = duration
        self.completedSets = completedSets
        self.totalRepetitions = totalRepetitions
        self.isDemo = isDemo
    }
}

enum WorkoutPhase: UInt8 {
    case idle = 0, active = 1, paused = 2, resting = 3, completed = 4
}
