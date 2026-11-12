import XCTest
import SwiftData
@testable import CotoveleiraInteligente

@MainActor final class WorkoutStoreTests: XCTestCase {
    private func store() -> WorkoutStore {
        let store = WorkoutStore()
        store.demoMode = true
        store.targetSets = 2
        store.targetRepetitions = 2
        store.restSeconds = 5
        return store
    }
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: WorkoutSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    func testInterruptedWorkoutDoesNotInventCompletedSets() throws {
        let store = store(); let context = try context()
        store.start(); store.addRepetition(); store.finish(in: context)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].completedSets, 0)
        XCTAssertEqual(sessions[0].totalRepetitions, 1)
        XCTAssertEqual(sessions[0].outcomeTitle, "Treino interrompido")
        store.finish(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }
    func testFinishDuringRestCountsTheCompletedSet() throws {
        let store = store(); let context = try context()
        store.start(); store.addRepetition(); store.addRepetition()
        XCTAssertEqual(store.phase, .resting)
        store.finish(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.completedSets, 1)
    }
    func testPauseRestSkipAndCompletionPreserveCounts() throws {
        let store = store(); let context = try context()
        store.start(); store.pauseOrResume(); store.addRepetition()
        XCTAssertEqual(store.total, 0)
        store.pauseOrResume(); store.addRepetition(); store.addRepetition()
        XCTAssertEqual(store.phase, .resting)
        XCTAssertEqual(store.remaining, 5)
        store.skipRest()
        XCTAssertTrue(store.restCompleted)
        XCTAssertEqual(store.set, 2)
        store.addRepetition(); store.addRepetition(); store.finish(in: context)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(session.completedSets, 2)
        XCTAssertEqual(session.totalRepetitions, 4)
        XCTAssertEqual(session.wasInterrupted, false)
    }
    func testRestActuallyAdvancesAutomatically() async throws {
        let store = store(); let context = try context()
        store.start(); store.addRepetition(); store.addRepetition()
        try await Task.sleep(for: .seconds(5.5))
        XCTAssertEqual(store.phase, .active)
        XCTAssertEqual(store.set, 2)
        XCTAssertTrue(store.restCompleted)
        store.finish(in: context)
    }
    func testLegacyPartialRecordAndPortugueseDate() {
        let date = Date(timeIntervalSince1970: 1794510540)
        let record = WorkoutSession(startedAt: date, duration: 20, completedSets: 0, totalRepetitions: 8, isDemo: true)
        XCTAssertEqual(record.outcomeTitle, "Treino interrompido")
        XCTAssertTrue(record.localizedDate.contains("novembro"))
        XCTAssertTrue(record.localizedDate.contains(", às "))
    }
}
