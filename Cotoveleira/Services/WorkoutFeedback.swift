import Foundation

enum HapticPattern: String, CaseIterable {
    case correct, error, series, rest, success, unlock

    var title: String {
        switch self {
        case .correct: return "Repetição correta"
        case .error: return "Repetição incorreta"
        case .series: return "Série concluída"
        case .rest: return "Próxima série"
        case .success: return "Treino concluído"
        case .unlock: return "Engenharia"
        }
    }
    var times: [Double] {
        switch self {
        case .correct, .unlock: return [0]
        case .error: return [0, 0.16]
        case .series: return [0, 0.20, 0.40]
        case .rest: return [0, 0.08]
        case .success: return [0, 0.15, 0.35, 0.65, 0.95]
        }
    }
    var priority: Int {
        switch self {
        case .correct, .unlock: return 0
        case .rest: return 1
        case .error: return 2
        case .series: return 3
        case .success: return 4
        }
    }
}

struct WorkoutEvent: Equatable {
    let type: UInt8
    let reason: UInt8
    let sequence: UInt32

    init?(data: Data) {
        let bytes = Array(data)
        guard bytes.count == 7, bytes[0] == 1, (1...5).contains(bytes[1]) else { return nil }
        type = bytes[1]; reason = bytes[2]
        sequence = UInt32(bytes[3]) | UInt32(bytes[4]) << 8 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 24
    }
    var pattern: HapticPattern {
        switch type {
        case 1: return .error
        case 2: return .series
        case 3: return .rest
        case 4: return .success
        default: return .correct
        }
    }
}

struct WorkoutEventStream {
    private(set) var sequence: UInt32?
    mutating func accept(_ event: WorkoutEvent) -> Bool {
        if let sequence, Int32(bitPattern: event.sequence &- sequence) <= 0 { return false }
        sequence = event.sequence
        return true
    }
}

// The service owns one pending pattern and one active player, never a backlog.
struct HapticArbitration {
    private(set) var pending: HapticPattern?
    private var active: HapticPattern?
    private var activeUntil = Date.distantPast

    mutating func offer(_ pattern: HapticPattern, now: Date = .now) -> Bool {
        if let active, activeUntil > now, active.priority > pattern.priority { return false }
        if let pending, pending.priority > pattern.priority { return false }
        pending = pattern
        return true
    }
    mutating func take() -> HapticPattern? {
        defer { pending = nil }
        return pending
    }
    mutating func begin(_ pattern: HapticPattern, now: Date = .now) {
        active = pattern
        activeUntil = now.addingTimeInterval((pattern.times.last ?? 0) + 0.12)
    }
    mutating func clear() { self = HapticArbitration() }
}

// Shared by BLE and tests; never infer completion from a state snapshot.
// Firmware 1-4 already emits boundary events. Only missing ordinary reps need a fallback.
@MainActor final class WorkoutFeedbackCoordinator {
    private var stream = WorkoutEventStream()
    private var previous: (repetition: Int, set: Int, phase: WorkoutPhase)?
    private(set) var hasCorrectEvents = false
    private var suspended = false
    private var legacyTask: Task<Void, Never>?
    private var lastLegacyFeedback: Date?
    private let output: (HapticPattern) -> Void
    private let log: (String) -> Void

    init(output: @escaping (HapticPattern) -> Void, log: @escaping (String) -> Void = { _ in }) {
        self.output = output; self.log = log
    }

    func reset() {
        legacyTask?.cancel(); legacyTask = nil
        stream = WorkoutEventStream(); previous = nil; hasCorrectEvents = false; suspended = false
        lastLegacyFeedback = nil
    }

    func suspend() { suspended = true; legacyTask?.cancel(); legacyTask = nil }
    func resume() { suspended = false }

    func receive(_ data: Data, enabled: Bool) {
        guard let event = WorkoutEvent(data: data) else { log("Evento BLE inválido (tamanho/versão/tipo)"); return }
        log("Evento tipo=\(event.type) motivo=\(event.reason) sequência=\(event.sequence)")
        guard stream.accept(event) else { log("Evento duplicado/anterior ignorado"); return }
        if event.type == 5 {
            hasCorrectEvents = true
            legacyTask?.cancel(); legacyTask = nil
            // A late first type-5 can follow the compatibility timeout. The
            // firmware enforces >= 1000 ms between valid reps; match only the
            // recent fallback, never the next normal repetition.
            if let lastLegacyFeedback, Date.now.timeIntervalSince(lastLegacyFeedback) < 0.8 {
                self.lastLegacyFeedback = nil
                log("Evento 5 já atendido pelo fallback de estado")
                return
            }
        }
        guard enabled, !suspended else { log("Feedback de evento suprimido (demo/standby/pausa)"); return }
        // Event notifications may precede the corresponding state update.
        if (event.type == 1 || event.type == 5), let previous, previous.phase != .active { return }
        output(event.pattern)
    }

    func state(repetition: Int, set: Int, phase: WorkoutPhase, enabled: Bool) {
        let old = previous
        previous = (repetition, set, phase)
        if phase != .active || !enabled { legacyTask?.cancel(); legacyTask = nil }
        if phase == .active, let old, old.phase != .active { suspended = false }
        guard enabled, !suspended, !hasCorrectEvents, let old,
              old.phase == .active, phase == .active, old.set == set,
              repetition > old.repetition else { return }
        legacyTask?.cancel()
        // Gives type 5 time to arrive in either state/event notification order.
        legacyTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self, !self.hasCorrectEvents, !self.suspended else { return }
            self.log("Repetição detectada pelo estado (firmware legado)")
            self.lastLegacyFeedback = .now
            self.output(.correct)
        }
    }
}
