import XCTest
@testable import Core

final class ReconcilerTests: XCTestCase {
    private func at(_ minutes: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(minutes * 60)) }
    private func i(_ a: Int, _ b: Int) -> Interval { Interval(start: at(a), end: at(b)) }
    private func m(_ id: String, _ a: Int, _ b: Int) -> ManagedEvent { ManagedEvent(id: id, interval: i(a, b)) }

    func testNoOp() {
        XCTAssertEqual(Reconciler.reconcile(desired: [i(0, 10), i(20, 30)],
                                            existing: [m("a", 0, 10), m("b", 20, 30)]), [])
        XCTAssertEqual(Reconciler.reconcile(desired: [], existing: []), [])
    }

    func testCreateWhenNothingExists() {
        XCTAssertEqual(Reconciler.reconcile(desired: [i(0, 10), i(20, 30)], existing: []),
                       [.create(i(0, 10)), .create(i(20, 30))])
    }

    func testDeleteWhenNothingDesired() {
        XCTAssertEqual(Reconciler.reconcile(desired: [], existing: [m("a", 0, 10)]), [.delete(id: "a")])
    }

    func testUpdatePairsInsteadOfCreateAndDelete() {
        XCTAssertEqual(Reconciler.reconcile(desired: [i(0, 15)], existing: [m("a", 0, 10)]),
                       [.update(id: "a", i(0, 15))])
    }

    func testUpdatePairsByOverlapThenNearestStart() {
        // Each desired interval overlaps only its own event, so pairing must not cross over.
        let ops = Reconciler.reconcile(desired: [i(0, 12), i(100, 112)],
                                       existing: [m("late", 100, 110), m("early", 0, 10)])
        XCTAssertEqual(Set(ops), [.update(id: "early", i(0, 12)), .update(id: "late", i(100, 112))])
    }

    func testPairsNonOverlappingByNearestStart() {
        let ops = Reconciler.reconcile(desired: [i(50, 60)], existing: [m("far", 500, 510), m("near", 40, 45)])
        XCTAssertEqual(ops, [.update(id: "near", i(50, 60)), .delete(id: "far")])
    }

    func testMixedUpdateCreateDelete() {
        let ops = Reconciler.reconcile(desired: [i(0, 10), i(20, 35), i(100, 110)],
                                       existing: [m("keep", 0, 10), m("grow", 20, 30), m("gone1", 300, 310), m("gone2", 400, 410)])
        // 'grow' updates; one leftover event gets reused for the new interval; one is deleted.
        XCTAssertFalse(ops.contains(.create(i(0, 10))))
        XCTAssertTrue(ops.contains(.update(id: "grow", i(20, 35))))
        XCTAssertEqual(ops.count, 3)
    }

    func testDuplicateExistingKeepsOneDeletesExtras() {
        let ops = Reconciler.reconcile(desired: [i(0, 10)], existing: [m("b", 0, 10), m("a", 0, 10), m("c", 0, 10)])
        XCTAssertEqual(ops, [.delete(id: "b"), .delete(id: "c")])
    }

    func testDuplicateDesiredIsCollapsed() {
        XCTAssertEqual(Reconciler.reconcile(desired: [i(0, 10), i(0, 10)], existing: []), [.create(i(0, 10))])
    }

    func testEmptyDesiredIsIgnored() {
        XCTAssertEqual(Reconciler.reconcile(desired: [i(5, 5)], existing: []), [])
    }

    func testIdempotent() {
        let cases: [(desired: [Interval], existing: [ManagedEvent])] = [
            ([i(0, 10), i(20, 30)], []),
            ([], [m("a", 0, 10), m("b", 5, 15)]),
            ([i(0, 15), i(40, 50), i(70, 80)], [m("a", 0, 10), m("b", 100, 110), m("c", 100, 110), m("d", 100, 110)]),
            ([i(0, 10)], [m("a", 0, 10), m("b", 0, 10)]),
            ([i(10, 20), i(30, 40)], [m("a", 12, 22), m("b", 28, 38), m("c", 1000, 1010)]),
        ]
        for (desired, existing) in cases {
            var nextID = 0
            let ops = Reconciler.reconcile(desired: desired, existing: existing)
            let after = apply(ops, to: existing, nextID: &nextID)
            XCTAssertEqual(Set(after.map(\.interval)), Set(desired))
            XCTAssertEqual(after.count, Set(desired).count)
            XCTAssertEqual(Reconciler.reconcile(desired: desired, existing: after), [], "second run must be a no-op")
        }
    }
}
