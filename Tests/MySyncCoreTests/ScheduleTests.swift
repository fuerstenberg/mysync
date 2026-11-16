import XCTest
@testable import MySyncCore

final class ScheduleTests: XCTestCase {
    let cal = TestCalendar.berlin

    func testDescriptions() {
        XCTAssertEqual(Schedule.everyMinutes(10).description, "alle 10 Minuten")
        XCTAssertEqual(Schedule.everyMinutes(1).description, "jede Minute")
        XCTAssertEqual(Schedule.everyMinutes(0).description, "jede Minute")
        XCTAssertEqual(Schedule.hourly.description, "stündlich")
        XCTAssertEqual(Schedule.daily(hour: 12, minute: 0).description, "täglich um 12:00 Uhr")
        XCTAssertEqual(Schedule.daily(hour: 7, minute: 5).description, "täglich um 07:05 Uhr")
    }

    func testWithoutLastAttemptIsDueImmediately() {
        let now = TestCalendar.date(2026, 11, 16, 9, 0)
        for schedule in [Schedule.everyMinutes(5), .hourly, .daily(hour: 12, minute: 0)] {
            XCTAssertTrue(schedule.isDue(lastAttempt: nil, now: now, calendar: cal), "\(schedule)")
        }
    }

    func testEveryMinutes() {
        let last = TestCalendar.date(2026, 11, 16, 9, 0)
        let s = Schedule.everyMinutes(10)
        XCTAssertEqual(s.nextRun(after: last, calendar: cal), TestCalendar.date(2026, 11, 16, 9, 10))
        XCTAssertFalse(s.isDue(lastAttempt: last, now: TestCalendar.date(2026, 11, 16, 9, 9, 59), calendar: cal))
        XCTAssertTrue(s.isDue(lastAttempt: last, now: TestCalendar.date(2026, 11, 16, 9, 10), calendar: cal))
    }

    func testHourly() {
        let last = TestCalendar.date(2026, 11, 16, 9, 30)
        XCTAssertEqual(Schedule.hourly.nextRun(after: last, calendar: cal), TestCalendar.date(2026, 11, 16, 10, 30))
    }

    func testDailyLaterSameDay() {
        let last = TestCalendar.date(2026, 11, 16, 8, 0)
        XCTAssertEqual(Schedule.daily(hour: 12, minute: 0).nextRun(after: last, calendar: cal),
                       TestCalendar.date(2026, 11, 16, 12, 0))
    }

    func testDailyAfterTimeMovesToNextDay() {
        let last = TestCalendar.date(2026, 11, 16, 12, 0)
        XCTAssertEqual(Schedule.daily(hour: 12, minute: 0).nextRun(after: last, calendar: cal),
                       TestCalendar.date(2026, 11, 17, 12, 0))
    }

    func testDailyAcrossMonthEnd() {
        let last = TestCalendar.date(2026, 12, 31, 23, 0)
        XCTAssertEqual(Schedule.daily(hour: 6, minute: 30).nextRun(after: last, calendar: cal),
                       TestCalendar.date(2027, 1, 1, 6, 30))
    }

    func testDailyCatchUpAfterSleep() {
        // Gestern um 12:00 synchronisiert, Mac hat heute um 12:00 geschlafen, jetzt 15:00 → fällig.
        let last = TestCalendar.date(2026, 11, 15, 12, 0)
        let now = TestCalendar.date(2026, 11, 16, 15, 0)
        XCTAssertTrue(Schedule.daily(hour: 12, minute: 0).isDue(lastAttempt: last, now: now, calendar: cal))
    }

    func testDailyAcrossDaylightSavingChange() {
        // Umstellung auf Sommerzeit am 29.03.2026: 02:00 → 03:00
        let last = TestCalendar.date(2026, 3, 28, 12, 0)
        let next = Schedule.daily(hour: 12, minute: 0).nextRun(after: last, calendar: cal)
        XCTAssertEqual(next, TestCalendar.date(2026, 3, 29, 12, 0))
        XCTAssertEqual(next.timeIntervalSince(last), 23 * 3600)
    }

    func testDailyAtNonExistentTimeUsesNextTime() {
        let last = TestCalendar.date(2026, 3, 28, 3, 0)
        let next = Schedule.daily(hour: 2, minute: 30).nextRun(after: last, calendar: cal)
        // 02:30 existiert am 29.03. nicht – es wird die nächste gültige Zeit genommen.
        XCTAssertGreaterThan(next, last)
        XCTAssertLessThan(next.timeIntervalSince(last), 2 * 86_400)
    }

    func testCodableRoundTrip() throws {
        for s in [Schedule.everyMinutes(15), .hourly, .daily(hour: 23, minute: 59)] {
            let data = try JSONEncoder().encode(s)
            XCTAssertEqual(try JSONDecoder().decode(Schedule.self, from: data), s)
        }
    }

    func testKind() {
        XCTAssertEqual(Schedule.everyMinutes(3).kind, .minutes)
        XCTAssertEqual(Schedule.hourly.kind, .hourly)
        XCTAssertEqual(Schedule.daily(hour: 1, minute: 2).kind, .daily)
    }
}
