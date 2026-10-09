import XCTest
@testable import Core

final class IntervalTests: XCTestCase {
    private func at(_ minutes: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(minutes * 60)) }
    private func i(_ a: Int, _ b: Int) -> Interval { Interval(start: at(a), end: at(b)) }

    func testIsEmpty() {
        XCTAssertTrue(i(5, 5).isEmpty)
        XCTAssertTrue(i(6, 5).isEmpty)
        XCTAssertFalse(i(5, 6).isEmpty)
    }

    func testIntersection() {
        let cases: [(Interval, Interval, Interval?)] = [
            (i(0, 10), i(5, 15), i(5, 10)),
            (i(0, 10), i(2, 4), i(2, 4)),
            (i(0, 10), i(10, 20), nil),   // touching only
            (i(0, 10), i(11, 20), nil),
            (i(0, 10), i(0, 10), i(0, 10)),
        ]
        for (a, b, expected) in cases {
            XCTAssertEqual(a.intersection(b), expected)
            XCTAssertEqual(b.intersection(a), expected)
        }
    }

    func testPadded() {
        XCTAssertEqual(i(10, 20).padded(before: 300, after: 600), i(5, 30))
        XCTAssertEqual(i(10, 20).padded(before: 0, after: 0), i(10, 20))
    }

    func testOverlapsAndAdjacent() {
        XCTAssertTrue(i(0, 10).overlaps(i(9, 12)))
        XCTAssertFalse(i(0, 10).overlaps(i(10, 12)))
        XCTAssertTrue(i(0, 10).isAdjacent(to: i(10, 12)))
        XCTAssertTrue(i(10, 12).isAdjacent(to: i(0, 10)))
        XCTAssertFalse(i(0, 10).isAdjacent(to: i(11, 12)))
    }

    func testMerge() {
        let min = 60.0
        let cases: [(String, [Interval], TimeInterval, [Interval])] = [
            ("empty", [], 0, []),
            ("disjoint", [i(0, 5), i(10, 15)], 0, [i(0, 5), i(10, 15)]),
            ("overlap", [i(0, 10), i(5, 15)], 0, [i(0, 15)]),
            ("adjacent merges at gap 0", [i(0, 10), i(10, 15)], 0, [i(0, 15)]),
            ("unsorted", [i(10, 15), i(0, 5), i(4, 11)], 0, [i(0, 15)]),
            ("contained", [i(0, 20), i(5, 10)], 0, [i(0, 20)]),
            ("gap too small to merge", [i(0, 5), i(8, 10)], 2 * min, [i(0, 5), i(8, 10)]),
            ("gap exactly at threshold merges", [i(0, 5), i(8, 10)], 3 * min, [i(0, 10)]),
            ("gap chain", [i(0, 5), i(7, 10), i(12, 15)], 2 * min, [i(0, 15)]),
            ("drops empty", [i(3, 3), i(0, 5)], 0, [i(0, 5)]),
        ]
        for (name, input, gap, expected) in cases {
            XCTAssertEqual(Interval.merge(input, gap: gap), expected, name)
        }
    }
}
