import XCTest
import UIKit
@testable import CotoveleiraInteligente

@MainActor final class WorkoutFeedbackTests: XCTestCase {
    private func packet(_ type: UInt8, _ sequence: UInt32 = 1, reason: UInt8 = 0) -> Data {
        Data([1, type, reason, UInt8(truncatingIfNeeded: sequence),
              UInt8(truncatingIfNeeded: sequence >> 8), UInt8(truncatingIfNeeded: sequence >> 16),
              UInt8(truncatingIfNeeded: sequence >> 24)])
    }

    func testProtocolValidationAndLittleEndian() throws {
        let event = try XCTUnwrap(WorkoutEvent(data: packet(5, 0x12345678, reason: 3)))
        XCTAssertEqual(event.sequence, 0x12345678)
        XCTAssertEqual(event.reason, 3)
        XCTAssertEqual(event.pattern, .correct)
        for data in [Data(), Data([1, 5, 0, 1, 0, 0]), Data([2, 5, 0, 1, 0, 0, 0]), packet(6)] {
            XCTAssertNil(WorkoutEvent(data: data))
        }
        XCTAssertEqual((1...5).map { WorkoutEvent(data: packet(UInt8($0)))!.pattern },
                       [.error, .series, .rest, .success, .correct])
    }

    func testDuplicateOldAndWraparoundSequences() throws {
        var stream = WorkoutEventStream()
        for (sequence, accepted) in [(UInt32.max - 1, true), (UInt32.max, true), (0, true), (0, false), (UInt32.max, false), (1, true)] {
            XCTAssertEqual(stream.accept(try XCTUnwrap(WorkoutEvent(data: packet(5, sequence)))), accepted)
        }
    }

    func testExactlyOneCorrectForEitherNotificationOrder() async throws {
        for stateFirst in [true, false] {
            var output: [HapticPattern] = []
            let router = WorkoutFeedbackCoordinator(output: { output.append($0) })
            router.state(repetition: 0, set: 1, phase: .active, enabled: true)
            if stateFirst { router.state(repetition: 1, set: 1, phase: .active, enabled: true) }
            router.receive(packet(5), enabled: true)
            router.receive(packet(5), enabled: true)
            if !stateFirst { router.state(repetition: 1, set: 1, phase: .active, enabled: true) }
            try await Task.sleep(for: .milliseconds(180))
            XCTAssertEqual(output, [.correct])
        }
    }

    func testErrorReasonsAndNextSeries() {
        var output: [HapticPattern] = []
        let router = WorkoutFeedbackCoordinator(output: { output.append($0) })
        router.state(repetition: 0, set: 1, phase: .active, enabled: true)
        router.receive(packet(1, 1, reason: 2), enabled: true)
        router.receive(packet(3, 2), enabled: true)
        XCTAssertEqual(output, [.error, .rest])
        XCTAssertEqual(HapticPattern.error.times, [0, 0.16])
        XCTAssertNotEqual(HapticPattern.error.times, HapticPattern.rest.times)
    }

    func testLateFirstCorrectEventDoesNotRepeatLegacyFeedback() async throws {
        var output: [HapticPattern] = []
        let router = WorkoutFeedbackCoordinator(output: { output.append($0) })
        router.state(repetition: 0, set: 1, phase: .active, enabled: true)
        router.state(repetition: 1, set: 1, phase: .active, enabled: true)
        try await Task.sleep(for: .milliseconds(180))
        router.receive(packet(5), enabled: true)
        XCTAssertEqual(output, [.correct])
        XCTAssertTrue(router.hasCorrectEvents)
    }

    func testFinalRepSelectsOnlySeriesAndFinalWorkoutOnlySuccess() {
        for (events, expected) in [([UInt8(5), 2], HapticPattern.series), ([UInt8(5), 2, 4], .success)] {
            var arbitration = HapticArbitration()
            let router = WorkoutFeedbackCoordinator(output: { _ = arbitration.offer($0) })
            router.state(repetition: 11, set: 1, phase: .active, enabled: true)
            for (index, type) in events.enumerated() { router.receive(packet(type, UInt32(index + 1)), enabled: true) }
            XCTAssertEqual(arbitration.take(), expected)
            XCTAssertNil(arbitration.take())
        }
    }

    func testCompletionPreemptsAndSuppressesLowerPrioritiesWithoutBacklog() {
        let now = Date(timeIntervalSince1970: 100)
        var arbitration = HapticArbitration()
        arbitration.begin(.series, now: now)
        XCTAssertTrue(arbitration.offer(.success, now: now))
        XCTAssertEqual(arbitration.take(), .success)
        arbitration.begin(.success, now: now)
        XCTAssertFalse(arbitration.offer(.correct, now: now))
        XCTAssertFalse(arbitration.offer(.error, now: now))
        XCTAssertNil(arbitration.take())
        XCTAssertTrue(arbitration.offer(.correct, now: now.addingTimeInterval(2)))
        arbitration.clear()
        XCTAssertNil(arbitration.take())
    }

    func testLegacyFirmwareCounterFallbackWithoutInitialOrRepeatedSnapshot() async throws {
        var output: [HapticPattern] = []
        let router = WorkoutFeedbackCoordinator(output: { output.append($0) })
        router.state(repetition: 6, set: 1, phase: .active, enabled: true)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertTrue(output.isEmpty)
        router.state(repetition: 7, set: 1, phase: .active, enabled: true)
        router.state(repetition: 7, set: 1, phase: .active, enabled: true)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(output, [.correct])
        router.state(repetition: 12, set: 1, phase: .resting, enabled: true)
        router.receive(packet(2), enabled: true)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(output, [.correct, .series])
    }

    func testPauseManualFinishStandbyAndDemoDoNotProduceFeedback() async throws {
        var output: [HapticPattern] = []
        let router = WorkoutFeedbackCoordinator(output: { output.append($0) })
        router.state(repetition: 0, set: 1, phase: .active, enabled: true)
        router.state(repetition: 1, set: 1, phase: .active, enabled: true)
        router.suspend()
        router.receive(packet(5), enabled: true)
        router.receive(packet(4, 2), enabled: true)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertTrue(output.isEmpty)
        router.resume()
        router.receive(packet(5, 3), enabled: false)
        router.state(repetition: 2, set: 1, phase: .active, enabled: false)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertTrue(output.isEmpty)
    }

    func testReconnectResetsBaselineAndSequenceWithoutReplay() async throws {
        var output: [HapticPattern] = []
        let router = WorkoutFeedbackCoordinator(output: { output.append($0) })
        router.receive(packet(5, 99), enabled: true)
        router.reset()
        router.state(repetition: 8, set: 2, phase: .active, enabled: true)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(output, [.correct])
        router.receive(packet(5, 1), enabled: true)
        router.receive(packet(5, 1), enabled: true)
        XCTAssertEqual(output, [.correct, .correct])
    }

    func testDistinctPatternTiming() {
        XCTAssertEqual(HapticPattern.correct.times.count, 1)
        XCTAssertEqual(HapticPattern.series.times.count, 3)
        XCTAssertGreaterThan(HapticPattern.success.times.last!, HapticPattern.series.times.last!)
        XCTAssertEqual(Set(HapticPattern.allCases.filter { $0 != .unlock }.map(\.times)).count, 5)
    }

    func testUnavailableCoreHapticsUsesUIKitWithoutThrowing() async throws {
        guard UIApplication.shared.applicationState == .active else {
            throw XCTSkip("UIKit fallback requires an active test host")
        }
        let previous = UserDefaults.standard.object(forKey: "haptics")
        defer { UserDefaults.standard.set(previous, forKey: "haptics") }
        let service = HapticService(supportsHaptics: { false })
        service.enabled = true
        defer { service.cancel() }
        service.prepare()
        service.play(.error)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.engineStatus, "Fallback UIKit")
        XCTAssertTrue(service.diagnostics.contains { $0.contains("Fallback UIKit solicitado") })
    }
}
