import Foundation

/// The decisions made in Swipe to sort: where you are in the deck, what you kept or marked,
/// and how to undo. Pure logic so it can be unit tested; `SwipeSortModel` wraps it with photos.
nonisolated struct SwipeDeck: Equatable {
    enum Decision: Equatable { case keep, delete }

    struct Step: Equatable {
        let id: String
        let decision: Decision
        /// Whether the photo was already marked before this decision (possible after "Start again").
        let wasMarked: Bool
    }

    /// Number of photos in the deck.
    let count: Int
    /// Index of the photo on top of the stack.
    private(set) var position = 0
    private(set) var history: [Step] = []
    /// Photos marked for deletion, in the order they were marked.
    private(set) var markedIDs: [String] = []

    init(count: Int) { self.count = count }

    var isFinished: Bool { position >= count }
    var canUndo: Bool { !history.isEmpty }

    mutating func decide(_ decision: Decision, id: String) {
        guard !isFinished else { return }
        let wasMarked = markedIDs.contains(id)
        history.append(Step(id: id, decision: decision, wasMarked: wasMarked))
        switch decision {
        case .delete where !wasMarked: markedIDs.append(id)
        case .keep where wasMarked: markedIDs.removeAll { $0 == id }
        default: break
        }
        position += 1
    }

    /// Takes back the last decision and puts that photo back on top.
    @discardableResult
    mutating func undo() -> Step? {
        guard let step = history.popLast() else { return nil }
        if step.wasMarked {
            if !markedIDs.contains(step.id) { markedIDs.append(step.id) }
        } else {
            markedIDs.removeAll { $0 == step.id }
        }
        position -= 1
        return step
    }

    /// Stops tracking photos that no longer exist (they were deleted). Their cards stay behind
    /// you in the deck, but undo can no longer bring them back.
    mutating func forget(_ ids: Set<String>) {
        markedIDs.removeAll { ids.contains($0) }
        history.removeAll { ids.contains($0.id) }
    }

    /// Starts from the first photo again. Photos already marked stay marked.
    mutating func restart() {
        position = 0
        history = []
    }
}
