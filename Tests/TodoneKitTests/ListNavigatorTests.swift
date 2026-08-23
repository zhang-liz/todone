import Foundation
import Testing
@testable import TodoneKit

@Suite struct ListNavigatorTests {
    let ids = (0..<4).map { _ in UUID() }

    // MARK: Stepping

    @Test func firstDownSelectsTheTopRow() {
        #expect(ListNavigator.step(from: nil, by: 1, in: ids) == ids[0])
    }

    @Test func firstUpSelectsTheBottomRow() {
        #expect(ListNavigator.step(from: nil, by: -1, in: ids) == ids[3])
    }

    @Test func steppingWalksInBothDirections() {
        #expect(ListNavigator.step(from: ids[1], by: 1, in: ids) == ids[2])
        #expect(ListNavigator.step(from: ids[1], by: -1, in: ids) == ids[0])
    }

    // Wrapping would let a held key cycle the list forever.
    @Test func steppingStopsAtTheEnds() {
        #expect(ListNavigator.step(from: ids[3], by: 1, in: ids) == nil)
        #expect(ListNavigator.step(from: ids[0], by: -1, in: ids) == nil)
    }

    @Test func emptyListGoesNowhere() {
        #expect(ListNavigator.step(from: nil, by: 1, in: []) == nil)
        #expect(ListNavigator.step(from: ids[0], by: 1, in: []) == nil)
    }

    // A selected task can vanish from view — completed, rescheduled, filtered out.
    @Test func selectionMissingFromTheListRestartsFromTheEdge() {
        let stale = UUID()
        #expect(ListNavigator.step(from: stale, by: 1, in: ids) == ids[0])
        #expect(ListNavigator.step(from: stale, by: -1, in: ids) == ids[3])
    }

    // MARK: Successor after completing

    @Test func successorIsTheFollowingRow() {
        #expect(ListNavigator.successor(after: ids[1], in: ids) == ids[2])
    }

    @Test func successorAtTheEndFallsBackToThePreviousRow() {
        #expect(ListNavigator.successor(after: ids[3], in: ids) == ids[2])
    }

    @Test func successorInASingleRowListIsNil() {
        let only = [ids[0]]
        #expect(ListNavigator.successor(after: ids[0], in: only) == nil)
    }

    @Test func successorOfAnUnknownIDIsNil() {
        #expect(ListNavigator.successor(after: UUID(), in: ids) == nil)
    }
}
