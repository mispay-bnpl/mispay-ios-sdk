import XCTest
@testable import mispaysdk

final class MISPayLogTests: XCTestCase {

    private func fixedDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 25
        components.hour = 15
        components.minute = 31
        components.second = 2
        components.nanosecond = 481_000_000
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: components)!
    }

    func testFormatContainsPrefixCategoryTimestampAndLevel() {
        let line = MISPayLog.format(
            "→ GET https://api-sandbox.mispay.dev/v1/api/token (timeout 30s)",
            category: .network,
            isError: false,
            date: fixedDate()
        )
        XCTAssertTrue(line.hasPrefix("MISPaySDK ▸ [network] "), "line must start with prefix + category: \(line)")
        XCTAssertTrue(line.contains(" INFO  → GET https://api-sandbox.mispay.dev/v1/api/token"), "line must carry level + message: \(line)")
        XCTAssertTrue(line.range(of: #"\d{2}:\d{2}:\d{2}\.\d{3}"#, options: .regularExpression) != nil,
                      "line must contain an HH:mm:ss.SSS timestamp: \(line)")
    }

    func testFormatMarksErrors() {
        let line = MISPayLog.format("boom", category: .token, isError: true, date: fixedDate())
        XCTAssertTrue(line.contains("ERROR"), "error lines must be marked: \(line)")
        XCTAssertTrue(line.contains("[token]"), "error lines must keep the category: \(line)")
    }

    func testRedactKeepsOnlyPrefixAndLength() {
        let secret = "c9b1-super-secret-value-0123456789"
        let redacted = MISPayLog.redact(secret)
        XCTAssertTrue(redacted.hasPrefix("c9b1"), "redaction keeps a 4-char prefix: \(redacted)")
        XCTAssertTrue(redacted.contains("\(secret.count) chars"), "redaction reports the length: \(redacted)")
        XCTAssertFalse(redacted.contains("super-secret"), "redaction must not leak the secret body: \(redacted)")
    }

    func testRedactHandlesNilAndEmpty() {
        XCTAssertEqual(MISPayLog.redact(nil), "nil")
        XCTAssertEqual(MISPayLog.redact(""), "nil")
    }

    func testOnLogHookReceivesEmittedLines() {
        final class Sink {
            var lines: [String] = []
        }
        let sink = Sink()
        MISPayLog.onLog = { sink.lines.append($0) }
        defer { MISPayLog.onLog = nil }
        MISPayLog.info("hello hook", category: .demo)
        XCTAssertEqual(sink.lines.count, 1)
        XCTAssertTrue(sink.lines[0].contains("hello hook"))
    }
}
