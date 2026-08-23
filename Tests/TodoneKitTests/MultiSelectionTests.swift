import Foundation
import Testing
@testable import TodoneKit

@Suite struct MultiSelectionTests {
    let ids = (0..<5).map { _ in UUID() }

    @Test func startsEmpty() {
        let sel = MultiSelection()
        #expect(sel.isEmpty)
        #expect(sel.only == nil)
        #expect(sel.anchor == nil)
    }

    @Test func plainClickReplacesTheSelection() {
        var sel = MultiSelection()
        sel.select(ids[0])
        sel.select(ids[2])
        #expect(sel.ids == [ids[2]])
        #expect(sel.only == ids[2])
        #expect(sel.anchor == ids[2])
    }

    @Test func commandClickAddsAndRemoves() {
        var sel = MultiSelection()
        sel.select(ids[0])
        sel.toggle(ids[2])
        #expect(sel.ids == [ids[0], ids[2]])
        #expect(sel.only == nil)  // several rows: no single selection

        sel.toggle(ids[2])
        #expect(sel.ids == [ids[0]])
        #expect(sel.only == ids[0])
    }

    @Test func shiftClickSelectsTheRangeBetween() {
        var sel = MultiSelection()
        sel.select(ids[1])
        sel.extend(to: ids[3], in: ids)
        #expect(sel.ids == Set(ids[1...3]))
    }

    @Test func shiftClickWorksUpwardsToo() {
        var sel = MultiSelection()
        sel.select(ids[3])
        sel.extend(to: ids[1], in: ids)
        #expect(sel.ids == Set(ids[1...3]))
    }

    // The anchor stays put so dragging a shift-click keeps extending from the
    // same origin rather than creeping along behind the cursor.
    @Test func repeatedShiftClicksExtendFromTheSameAnchor() {
        var sel = MultiSelection()
        sel.select(ids[2])
        sel.extend(to: ids[4], in: ids)
        sel.extend(to: ids[0], in: ids)
        #expect(sel.ids == Set(ids[0...2]))
        #expect(sel.anchor == ids[2])
    }

    @Test func shiftClickWithoutAnAnchorActsLikeAPlainClick() {
        var sel = MultiSelection()
        sel.extend(to: ids[3], in: ids)
        #expect(sel.ids == [ids[3]])
        #expect(sel.anchor == ids[3])
    }

    @Test func shiftClickToAnOffscreenRowActsLikeAPlainClick() {
        var sel = MultiSelection()
        sel.select(ids[0])
        sel.extend(to: UUID(), in: ids)
        #expect(sel.count == 1)
    }

    @Test func removingTheAnchorMovesItRatherThanLeavingItDangling() {
        var sel = MultiSelection()
        sel.select(ids[0])
        sel.toggle(ids[1])
        #expect(sel.anchor == ids[1])

        sel.toggle(ids[1])  // remove the anchor row
        #expect(sel.anchor == ids[0])
        #expect(sel.ids == [ids[0]])
    }

    // After completing or filtering, a selection must not keep pointing at rows
    // the user can no longer see, or a bulk action would hit invisible tasks.
    @Test func pruneDropsRowsThatLeftTheView() {
        var sel = MultiSelection()
        sel.select(ids[0])
        sel.toggle(ids[1])
        sel.toggle(ids[2])

        sel.prune(to: [ids[0], ids[2]])
        #expect(sel.ids == [ids[0], ids[2]])
    }

    @Test func pruneMovesTheAnchorWhenItLeavesTheView() {
        var sel = MultiSelection()
        sel.select(ids[4])
        sel.prune(to: [ids[0], ids[1]])
        #expect(sel.isEmpty)
        #expect(sel.anchor == nil)
    }

    @Test func clearResetsEverything() {
        var sel = MultiSelection()
        sel.select(ids[0])
        sel.toggle(ids[1])
        sel.clear()
        #expect(sel.isEmpty)
        #expect(sel.anchor == nil)
    }
}
