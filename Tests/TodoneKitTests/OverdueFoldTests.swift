import Testing
@testable import TodoneKit

@Suite struct OverdueFoldTests {
    private func items(_ n: Int) -> [Int] { Array(0..<n) }

    @Test func shortListNeverFolds() {
        #expect(!OverdueFold.canFold(count: 0))
        #expect(!OverdueFold.canFold(count: OverdueFold.threshold))
        #expect(OverdueFold.shown(items(OverdueFold.threshold), expanded: false).count == OverdueFold.threshold)
    }

    @Test func longListFoldsUntilExpanded() {
        let long = items(OverdueFold.threshold + 1)
        #expect(OverdueFold.canFold(count: long.count))
        #expect(OverdueFold.shown(long, expanded: false).isEmpty)
        #expect(OverdueFold.shown(long, expanded: true) == long)
    }

    @Test func expandedChoiceDoesNotAffectShortLists() {
        let short = items(2)
        #expect(OverdueFold.shown(short, expanded: true) == short)
        #expect(OverdueFold.shown(short, expanded: false) == short)
    }
}
