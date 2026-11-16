import CoreHaptics
import UIKit
import UserNotifications

@MainActor final class HapticService {
    static let shared = HapticService()
    enum Pattern: String, CaseIterable { case error, series, rest, success, unlock }
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "haptics") }
    }
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var busyUntil = Date.distantPast
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func play(_ pattern: Pattern) {
        guard enabled else { return }
        if UIApplication.shared.applicationState != .active {
            let content = UNMutableNotificationContent()
            content.title = "Cotoveleira"
            content.body = [Pattern.error: "Repetição rejeitada", .series: "Série concluída", .rest: "Descanso concluído", .success: "Treino concluído", .unlock: "Engenharia"][pattern] ?? "Treino"
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            return
        }
        let start = max(0, busyUntil.timeIntervalSinceNow)
        let times: [Double]
        switch pattern {
        case .series: times = [0, 0.15, 0.30]
        case .rest: times = [0, 0.18]
        case .success: times = [0, 0.12, 0.36, 0.60]
        default: times = [0]
        }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil { engine = try CHHapticEngine() }
            try engine?.start()
            let events = times.map { time in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: pattern == .unlock ? 0.25 : 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: pattern == .error ? 0.8 : 0.4)
                ], relativeTime: time)
            }
            let next = try engine?.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try next?.start(atTime: (engine?.currentTime ?? 0) + start)
            player = next
            busyUntil = Date.now.addingTimeInterval(start + (times.last ?? 0) + 0.25)
        } catch { engine = nil; busyUntil = .distantPast }
    }
}
