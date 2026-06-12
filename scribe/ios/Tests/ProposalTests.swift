import XCTest
@testable import Scribe

final class ProposalTests: XCTestCase {

    /// The exact JSON shape the backend returns from POST /extract.
    private let sampleJSON = """
    {
      "events": [
        {
          "title": "Lunch with Sam",
          "start": "2026-06-16T12:00:00",
          "end": null,
          "allDay": false,
          "location": "Joe's Diner",
          "notes": null
        }
      ],
      "reminders": [
        {
          "title": "Send the invoice",
          "dueDate": "2026-06-19T09:00:00",
          "notes": null,
          "priority": "high"
        }
      ]
    }
    """

    func testDecodesBackendShape() throws {
        let result = try JSONDecoder().decode(ExtractionResult.self, from: Data(sampleJSON.utf8))

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].title, "Lunch with Sam")
        XCTAssertEqual(result.events[0].location, "Joe's Diner")
        XCTAssertNil(result.events[0].end)
        XCTAssertFalse(result.events[0].allDay)

        XCTAssertEqual(result.reminders.count, 1)
        XCTAssertEqual(result.reminders[0].title, "Send the invoice")
        XCTAssertEqual(result.reminders[0].priority, .high)
    }

    func testEmptyArraysDecode() throws {
        let json = #"{"events":[],"reminders":[]}"#
        let result = try JSONDecoder().decode(ExtractionResult.self, from: Data(json.utf8))
        XCTAssertTrue(result.events.isEmpty)
        XCTAssertTrue(result.reminders.isEmpty)
    }

    func testLocalDateTimeParsing() {
        let date = LocalDateTime.date(from: "2026-06-16T12:00:00")
        XCTAssertNotNil(date)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 16)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 0)
    }

    func testLocalDateTimeNilForBadInput() {
        XCTAssertNil(LocalDateTime.date(from: nil))
        XCTAssertNil(LocalDateTime.date(from: ""))
        XCTAssertNil(LocalDateTime.date(from: "not a date"))
    }

    func testReminderPriorityMapsToEventKit() {
        XCTAssertEqual(ReminderPriority.none.ekPriority, 0)
        XCTAssertEqual(ReminderPriority.high.ekPriority, 1)
        XCTAssertEqual(ReminderPriority.medium.ekPriority, 5)
        XCTAssertEqual(ReminderPriority.low.ekPriority, 9)
    }
}
