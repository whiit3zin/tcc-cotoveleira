import SwiftUI
import WidgetKit
import ActivityKit

@main struct WorkoutWidgets: WidgetBundle {
    var body: some Widget { WorkoutLiveActivity() }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivity.self) { context in
            VStack(alignment: .leading) {
                Label(context.attributes.title, systemImage: "figure.strengthtraining.traditional")
                Text(context.state.demo ? "Demonstração" : context.state.phase)
                Text("Série \(context.state.set) · \(context.state.repetitions) repetições")
                if context.isStale { Text("Aguardando atualização").font(.caption) }
            }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("Série \(context.state.set)") }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.repetitions) reps") }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.demo ? "Demonstração" : context.state.phase) }
            } compactLeading: { Image(systemName: "figure.strengthtraining.traditional") }
              compactTrailing: { Text("\(context.state.repetitions)") }
              minimal: { Text("\(context.state.repetitions)") }
        }
    }
}
