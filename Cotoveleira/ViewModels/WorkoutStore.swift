import Foundation
import SwiftUI
import SwiftData
import UIKit

@MainActor final class WorkoutStore: ObservableObject {
    @Published private(set) var phase: WorkoutPhase = .idle
    @Published private(set) var repetition = 0
    @Published private(set) var set = 1
    @Published private(set) var remaining = 0
    @Published private(set) var total = 0
    @Published private(set) var restCompleted = false
    @Published private(set) var wasInterrupted = false
    var isRunning: Bool { phase == .active || phase == .paused || phase == .resting }
    @Published private(set) var startedAt: Date?
    @Published var demoMode = UserDefaults.standard.object(forKey: "demoMode") as? Bool ?? true {
        didSet { UserDefaults.standard.set(demoMode, forKey: "demoMode") }
    }
    @Published var targetSets = UserDefaults.standard.object(forKey: "sets") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(targetSets, forKey: "sets") }
    }
    @Published var targetRepetitions = UserDefaults.standard.object(forKey: "repetitions") as? Int ?? 15 {
        didSet { UserDefaults.standard.set(targetRepetitions, forKey: "repetitions") }
    }
    @Published var restSeconds = UserDefaults.standard.object(forKey: "restSeconds") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(restSeconds, forKey: "restSeconds") }
    }
    private var timer: Task<Void, Never>?
    private var saved = false

    var progress: Double { Double(repetition) / Double(max(1, targetRepetitions)) }
    var clock: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }

    func start() {
        guard phase == .idle || phase == .completed else { return }
        stopTimer()
        repetition = 0; set = 1; total = 0; saved = false
        restCompleted = false; wasInterrupted = false
        startedAt = .now; phase = .active
        startDemoTicker()
    }

    func pauseOrResume() {
        if phase == .active { phase = .paused; stopTimer() }
        else if phase == .paused { phase = .active; startDemoTicker() }
    }

    func addRepetition() {
        guard phase == .active else { return }
        repetition += 1; total += 1
        if repetition >= max(1, targetRepetitions) {
            stopTimer()
            if set >= targetSets { phase = .completed }
            else { restCompleted = false; phase = .resting; remaining = restSeconds; startRestTicker() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func skipRest() {
        guard phase == .resting else { return }
        restCompleted = true
        stopTimer(); set += 1; repetition = 0; remaining = 0; phase = .active
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        startDemoTicker()
    }

    func finish(in context: ModelContext) {
        guard phase != .idle else { return }
        stopTimer()
        if !saved, let startedAt {
            let duration = max(0, Int(Date.now.timeIntervalSince(startedAt)))
            wasInterrupted = phase != .completed
            let completedSets = min(targetSets, max(0, set - 1) + (repetition >= targetRepetitions ? 1 : 0))
            context.insert(WorkoutSession(startedAt: startedAt, duration: duration, completedSets: completedSets, totalRepetitions: total, isDemo: demoMode, wasInterrupted: wasInterrupted))
            try? context.save()
            saved = true
        }
        phase = .completed
    }

    func applyDevice(repetition: Int, set: Int, phase: WorkoutPhase) {
        guard !demoMode else { return }
        self.repetition = min(repetition, targetRepetitions)
        self.set = min(max(1, set), targetSets)
        self.phase = phase
        self.total = (self.set - 1) * targetRepetitions + self.repetition
    }

    private func startDemoTicker() {
        guard demoMode else { return }
        #if DEBUG
        // UI tests advance repetitions by tapping; production cadence stays two seconds.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        #endif
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                self?.addRepetition()
            }
        }
    }

    private func startRestTicker() {
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }
                self.remaining = max(0, self.remaining - 1)
                if self.remaining == 0 { self.skipRest(); return }
            }
        }
    }

    private func stopTimer() { timer?.cancel(); timer = nil }
}
