import ActivityKit

struct WorkoutActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var repetitions: Int
        var set: Int
        var phase: String
        var demo: Bool
    }
    var title: String
}
