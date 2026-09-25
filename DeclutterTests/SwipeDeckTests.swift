import Testing
@testable import Declutter

@Suite("Swipe to sort deck")
struct SwipeDeckTests {
    @Test func swipingMovesThroughTheDeckAndMarksDeletes() {
        var deck = SwipeDeck(count: 3)
        deck.decide(.delete, id: "a")
        deck.decide(.keep, id: "b")
        #expect(deck.position == 2)
        #expect(deck.markedIDs == ["a"])
        #expect(!deck.isFinished)
        deck.decide(.delete, id: "c")
        #expect(deck.isFinished)
        #expect(deck.markedIDs == ["a", "c"])
        // Nothing happens past the end.
        deck.decide(.delete, id: "d")
        #expect(deck.position == 3 && deck.markedIDs == ["a", "c"])
    }

    @Test func undoPutsTheLastPhotoBack() {
        var deck = SwipeDeck(count: 3)
        #expect(!deck.canUndo)
        deck.decide(.keep, id: "a")
        deck.decide(.delete, id: "b")
        #expect(deck.undo()?.id == "b")
        #expect(deck.position == 1)
        #expect(deck.markedIDs.isEmpty)
        #expect(deck.undo()?.decision == .keep)
        #expect(deck.position == 0)
        #expect(deck.undo() == nil)
    }

    @Test func startingAgainKeepsMarksAndLetsYouChangeYourMind() {
        var deck = SwipeDeck(count: 2)
        deck.decide(.delete, id: "a")
        deck.decide(.delete, id: "b")
        deck.restart()
        #expect(deck.position == 0 && !deck.canUndo)
        #expect(deck.markedIDs == ["a", "b"])

        deck.decide(.keep, id: "a")          // changed my mind about a
        deck.decide(.delete, id: "b")        // still delete b, and don't list it twice
        #expect(deck.markedIDs == ["b"])

        deck.undo()
        deck.undo()                          // undoing the keep marks a again
        #expect(Set(deck.markedIDs) == ["a", "b"])
    }

    @Test func deletedPhotosAreForgotten() {
        var deck = SwipeDeck(count: 3)
        deck.decide(.delete, id: "a")
        deck.decide(.keep, id: "b")
        deck.decide(.delete, id: "c")
        deck.forget(["a", "c"])
        #expect(deck.markedIDs.isEmpty)
        #expect(deck.history.map(\.id) == ["b"])
        #expect(deck.position == 3)
    }

    @Test func emptyDeckIsFinished() {
        #expect(SwipeDeck(count: 0).isFinished)
    }
}
