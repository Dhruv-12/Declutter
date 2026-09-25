import Foundation

/// Where the merged contact's name comes from.
nonisolated enum NameChoice: Hashable, Sendable {
    /// Copy the whole name from this contact.
    case contact(String)
    /// A name the user typed.
    case custom(given: String, family: String)
}

/// Exactly what the user approved for one merge. Passed to `ContactsService.merge`.
nonisolated struct MergePlan: Sendable {
    let contactIDs: [String]
    /// The contact that is updated and kept; the rest are deleted.
    let primaryID: String
    let name: NameChoice
    let phoneKeys: Set<String>
    let emailKeys: Set<String>
    /// Contact whose photo to use, or nil for no photo.
    let photoFrom: String?
}

/// One phone number or email in the merge editor.
nonisolated struct DraftValue: Identifiable, Hashable, Sendable {
    /// Normalised form used to spot duplicates.
    let key: String
    /// How it is written in the first contact that has it.
    let display: String
    /// Other copies of the same value that were folded into this one.
    var duplicatesRemoved = 0
    var isIncluded = true

    var id: String { key }

    /// One entry per unique key, in order, with duplicates counted instead of repeated.
    static func unique(_ values: [String], key: (String) -> String) -> [DraftValue] {
        var result: [DraftValue] = []
        var indexForKey: [String: Int] = [:]
        for value in values {
            let valueKey = key(value)
            if let index = indexForKey[valueKey] {
                result[index].duplicatesRemoved += 1
            } else {
                indexForKey[valueKey] = result.count
                result.append(DraftValue(key: valueKey, display: value))
            }
        }
        return result
    }
}

/// The user's edits to one duplicate group before it is merged.
nonisolated struct MergeDraft: Identifiable, Hashable, Sendable {
    let group: ContactGroup
    /// Used by "Merge all": unticked groups are skipped.
    var isIncluded = true
    var useCustomName = false
    var nameFromID: String
    var customGiven = ""
    var customFamily = ""
    var phones: [DraftValue]
    var emails: [DraftValue]
    var photoFrom: String?

    var id: String { group.id }
    var primary: ContactSummary { group.primary }

    /// The kept contact first, then the others, so the first copy of a number wins.
    var orderedContacts: [ContactSummary] {
        [primary] + group.contacts.filter { $0.id != primary.id }
    }

    init(group: ContactGroup) {
        self.group = group
        let primary = group.primary
        let ordered = [primary] + group.contacts.filter { $0.id != primary.id }

        nameFromID = primary.name.isEmpty
            ? (ordered.first { !$0.name.isEmpty }?.id ?? primary.id)
            : primary.id
        phones = DraftValue.unique(ordered.flatMap(\.phones), key: ContactsService.phoneDedupKey)
        emails = DraftValue.unique(ordered.flatMap(\.emails), key: ContactsService.emailDedupKey)
        photoFrom = primary.thumbnail != nil ? primary.id : ordered.first { $0.thumbnail != nil }?.id
    }

    /// Contacts offering a different name to choose from.
    var nameOptions: [ContactSummary] {
        var seen = Set<String>()
        let named = orderedContacts.filter { !$0.name.isEmpty && seen.insert($0.name).inserted }
        return named.isEmpty ? [primary] : named
    }

    var photoOptions: [ContactSummary] {
        orderedContacts.filter { $0.thumbnail != nil }
    }

    var finalName: String {
        if useCustomName {
            return [customGiven, customFamily]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return group.contacts.first { $0.id == nameFromID }?.displayName ?? primary.displayName
    }

    var photoContact: ContactSummary? {
        photoFrom.flatMap { id in group.contacts.first { $0.id == id } }
    }

    var includedPhones: [DraftValue] { phones.filter(\.isIncluded) }
    var includedEmails: [DraftValue] { emails.filter(\.isIncluded) }

    /// A typed name can't be blank.
    var isValid: Bool { !useCustomName || !finalName.isEmpty }

    var plan: MergePlan {
        MergePlan(
            contactIDs: orderedContacts.map(\.id),
            primaryID: primary.id,
            name: useCustomName
                ? .custom(
                    given: customGiven.trimmingCharacters(in: .whitespaces),
                    family: customFamily.trimmingCharacters(in: .whitespaces))
                : .contact(nameFromID),
            phoneKeys: Set(includedPhones.map(\.key)),
            emailKeys: Set(includedEmails.map(\.key)),
            photoFrom: photoFrom
        )
    }
}
