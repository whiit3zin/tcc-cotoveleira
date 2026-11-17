import CoreHaptics
import Combine
import UIKit
import UserNotifications
import os

@MainActor final class HapticService: ObservableObject {
    static let shared = HapticService()
    typealias Pattern = HapticPattern
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var engineStatus = "Não preparado"
    private let logger = Logger(subsystem: "br.edu.tcc.cotoveleira", category: "Haptics")
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "haptics"); if !newValue { cancel() } }
    }
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var patterns: [Pattern: CHHapticPattern] = [:]
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()
    private var arbitration = HapticArbitration()
    private var pendingTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private let supportsHaptics: () -> Bool

    init(supportsHaptics: @escaping () -> Bool = { CHHapticEngine.capabilitiesForHardware().supportsHaptics }) {
        self.supportsHaptics = supportsHaptics
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prepare() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        diagnostics.append("\(Date.now.formatted(date: .omitted, time: .standard)) \(message)")
        if diagnostics.count > 200 { diagnostics.removeFirst(diagnostics.count - 200) }
    }
    func clearDiagnostics() { diagnostics = [] }

    func prepare() {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        heavy.prepare(); rigid.prepare(); notification.prepare()
        let supported = supportsHaptics()
        log("Core Haptics disponível: \(supported)")
        guard supported else { engineStatus = "Fallback UIKit"; return }
        do {
            if engine == nil {
                let next = try CHHapticEngine()
                next.playsHapticsOnly = true
                next.isAutoShutdownEnabled = true
                next.stoppedHandler = { [weak self] reason in
                    Task { @MainActor in
                        guard let self else { return }
                        self.cancel()
                        self.engineStatus = "Parado: \(reason.rawValue)"
                        self.log("Engine parado: \(reason.rawValue); reinício na próxima solicitação")
                    }
                }
                next.resetHandler = { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        self.cancel(); self.player = nil
                        self.log("Engine resetado; recriando players e preparando")
                        self.prepare()
                    }
                }
                engine = next
            }
            try engine?.start()
            engineStatus = "Core Haptics pronto"
        } catch {
            engineStatus = "Fallback UIKit"
            log("Falha ao preparar Core Haptics: \(error.localizedDescription)")
        }
    }

    func cancel() {
        pendingTask?.cancel(); pendingTask = nil; arbitration.clear()
        fallbackTask?.cancel(); fallbackTask = nil
        do { try player?.stop(atTime: CHHapticTimeImmediate) }
        catch { log("Falha ao parar player: \(error.localizedDescription)") }
        player = nil
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func play(_ pattern: Pattern) {
        log("Vibração solicitada: \(pattern.title)")
        guard enabled else { cancel(); log("Feedback desativado em Ajustes"); return }
        if UIApplication.shared.applicationState != .active {
            // No custom Taptic guarantee in background; avoid a notification for every rep.
            guard pattern == .error || pattern == .series || pattern == .success || pattern == .rest else {
                log("Háptico indisponível com app inativo: \(pattern.title)"); return
            }
            queueNotification(pattern)
            return
        }
        guard arbitration.offer(pattern) else {
            log("Padrão suprimido por prioridade: \(pattern.title)"); return
        }
        guard pendingTask == nil else { return }
        // 40 ms collects the adjacent 5/2/4 BLE burst before producing any pulse.
        pendingTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self, let selected = self.arbitration.take() else { return }
            self.pendingTask = nil
            self.execute(selected)
        }
    }

    private func execute(_ pattern: Pattern) {
        guard enabled, UIApplication.shared.applicationState == .active else { cancel(); return }
        cancel() // Preempt instead of queueing stale feedback or overlapping players.
        arbitration.begin(pattern)
        if supportsHaptics() {
            do {
                if engine == nil { prepare() }
                guard let engine else { throw HapticError.engineUnavailable }
                try engine.start() // Reuse engine; restart after idle timeout/interruption.
                let haptic: CHHapticPattern
                if let cached = patterns[pattern] { haptic = cached }
                else {
                    let events = pattern.times.map { time in
                        CHHapticEvent(eventType: .hapticTransient, parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: pattern == .unlock ? 0.5 : 1),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: pattern == .unlock ? 0.5 : 1)
                        ], relativeTime: time)
                    }
                    haptic = try CHHapticPattern(events: events, parameters: [])
                    patterns[pattern] = haptic
                }
                let next = try engine.makePlayer(with: haptic)
                player = next
                try next.start(atTime: CHHapticTimeImmediate)
                engineStatus = "Core Haptics pronto"
                log("Player iniciado: \(pattern.title) (execução física não confirmável pela API)")
                return
            } catch {
                log("Erro Core Haptics: \(error.localizedDescription); usando UIKit")
                try? player?.stop(atTime: CHHapticTimeImmediate); player = nil
            }
        }
        fallback(pattern)
    }

    private func fallback(_ pattern: Pattern) {
        engineStatus = "Fallback UIKit"
        heavy.prepare(); rigid.prepare(); notification.prepare()
        fallbackPulse(pattern, first: true)
        fallbackTask = Task { [weak self] in
            var previous = 0.0
            for time in pattern.times.dropFirst() {
                do { try await Task.sleep(for: .seconds(time - previous)) } catch { return }
                previous = time
                guard let self, self.enabled, UIApplication.shared.applicationState == .active else { return }
                self.fallbackPulse(pattern, first: false)
            }
        }
        log("Fallback UIKit solicitado: \(pattern.title); intensidade depende do dispositivo/iOS")
    }

    private func fallbackPulse(_ pattern: Pattern, first: Bool) {
        if pattern == .success && first { notification.notificationOccurred(.success); notification.prepare() }
        else if pattern == .rest { rigid.impactOccurred(intensity: 1); rigid.prepare() }
        else { heavy.impactOccurred(intensity: 1); heavy.prepare() }
    }

    private func queueNotification(_ pattern: Pattern) {
        // Reuse the same coalescing policy in background, so series then success
        // does not post multiple simultaneous completion notifications.
        guard arbitration.offer(pattern) else { return }
        guard pendingTask == nil else { return }
        pendingTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self, self.enabled, let selected = self.arbitration.take() else { return }
            self.pendingTask = nil
            let content = UNMutableNotificationContent()
            content.title = "Cotoveleira"
            content.body = selected.title
            content.sound = .default
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "workout-feedback", content: content, trigger: nil))
                self.log("Notificação alternativa solicitada: \(selected.title); depende dos ajustes iOS")
            } catch { self.log("Falha na notificação: \(error.localizedDescription)") }
        }
    }

    private enum HapticError: Error { case engineUnavailable }
}
