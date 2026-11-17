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
    @Published var demoMode = false {
        didSet { stopTimer(); phase = .idle; repetition = 0; total = 0; startedAt = nil }
    }
    @Published var demoPowered = true
    func simulateError() { guard demoMode && demoPowered, phase == .active else { return }; HapticService.shared.play(.error) }

    @Published var targetSets = (UserDefaults.standard.object(forKey: "sets") == nil ? 3 : UserDefaults.standard.integer(forKey: "sets")) {
        didSet { UserDefaults.standard.set(targetSets, forKey: "sets") }
    }
    @Published var targetRepetitions = (UserDefaults.standard.object(forKey: "repetitions") == nil ? 12 : UserDefaults.standard.integer(forKey: "repetitions")) {
        didSet { UserDefaults.standard.set(targetRepetitions, forKey: "repetitions") }
    }
    @Published var restSeconds = (UserDefaults.standard.object(forKey: "restSeconds") == nil ? 60 : UserDefaults.standard.integer(forKey: "restSeconds")) {
        didSet { UserDefaults.standard.set(restSeconds, forKey: "restSeconds") }
    }
    private var timer: Task<Void, Never>?
    private var saved = false
    private var deviceInterrupted = false

    func syncInterruption(_ interrupted: Bool) { deviceInterrupted = interrupted }

    init() {
        #if DEBUG
        demoMode = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #endif
    }

    var progress: Double { Double(repetition) / Double(max(1, targetRepetitions)) }
    var clock: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }

    func start() {
        guard demoMode, demoPowered, phase == .idle || phase == .completed else { return }
        stopTimer()
        repetition = 0; set = 1; total = 0; saved = false
        restCompleted = false; wasInterrupted = false
        startedAt = .now; phase = .active
        startDemoTicker()
    }

    func pauseOrResume() {
        guard demoMode else { return }
        if phase == .active { phase = .paused; stopTimer(); HapticService.shared.cancel() }
        else if phase == .paused { phase = .active; startDemoTicker() }
    }

    func addRepetition() {
        guard demoMode, demoPowered, phase == .active else { return }
        repetition += 1; total += 1
        if repetition >= max(1, targetRepetitions) {
            stopTimer()
            if set >= targetSets { phase = .completed }
            else { restCompleted = false; phase = .resting; remaining = restSeconds; startRestTicker() }
            HapticService.shared.play(phase == .completed ? .success : .series)
        } else { HapticService.shared.play(.correct) }
    }

    func skipRest() {
        guard demoMode, phase == .resting else { return }
        restCompleted = true
        stopTimer(); set += 1; repetition = 0; remaining = 0; phase = .active
        HapticService.shared.play(.rest)
        startDemoTicker()
    }

    func finish(in context: ModelContext) {
        guard phase != .idle else { return }
        if phase != .completed { HapticService.shared.cancel() }
        stopTimer()
        if !saved, let startedAt {
            let duration = max(0, Int(Date.now.timeIntervalSince(startedAt)))
            wasInterrupted = phase != .completed || (!demoMode && deviceInterrupted)
            let completedSets = min(targetSets, max(0, set - 1) + (repetition >= targetRepetitions ? 1 : 0))
            context.insert(WorkoutSession(startedAt: startedAt, duration: duration, completedSets: completedSets, totalRepetitions: total, isDemo: demoMode, wasInterrupted: wasInterrupted))
            try? context.save()
            saved = true
        }
        phase = .completed
    }

    func applyDevice(repetition: Int, set: Int, phase: WorkoutPhase) {
        guard !demoMode else { return }
        if (phase == .active || phase == .paused || phase == .resting) && (self.phase == .idle || self.phase == .completed) {
            startedAt = .now; saved = false; wasInterrupted = false
        }
        if phase == .idle { stopTimer(); startedAt = nil }
        self.repetition = min(repetition, targetRepetitions)
        self.set = min(max(1, set), targetSets)
        self.phase = phase
        self.total = (self.set - 1) * targetRepetitions + self.repetition
    }

    func syncRest(_ seconds: Int) { if !demoMode { remaining = seconds } }

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
