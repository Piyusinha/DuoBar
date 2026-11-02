import XCTest
@testable import DuoBar

final class KeepAwakeTests: XCTestCase {
    func testTimedDurationsPassTheirLengthInSecondsAndWatchDuoBar() {
        XCTAssertEqual(
            KeepAwakeService.caffeinateArguments(for: .fiveMinutes, watchingProcess: 42),
            ["-di", "-t", "300", "-w", "42"]
        )
        XCTAssertEqual(
            KeepAwakeService.caffeinateArguments(for: .oneHour, watchingProcess: 42),
            ["-di", "-t", "3600", "-w", "42"]
        )
    }

    func testIndefiniteDurationHasNoTimeout() {
        XCTAssertEqual(
            KeepAwakeService.caffeinateArguments(for: .indefinitely, watchingProcess: 7),
            ["-di", "-w", "7"]
        )
    }

    func testSessionEndDateFollowsTheDuration() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertEqual(
            KeepAwakeSession(duration: .tenMinutes, startDate: start).endDate,
            start.addingTimeInterval(600)
        )
        XCTAssertNil(KeepAwakeSession(duration: .indefinitely, startDate: start).endDate)
    }

    @MainActor
    func testStartingAndStoppingRunsCaffeinate() throws {
        let service = KeepAwakeService()
        service.start(.fiveMinutes)
        XCTAssertEqual(service.session?.duration, .fiveMinutes)

        // Switching durations replaces the session instead of stacking processes.
        service.start(.indefinitely)
        XCTAssertEqual(service.session?.duration, .indefinitely)

        service.stop()
        XCTAssertNil(service.session)
    }
}
