import Contacts
import Foundation
import Testing
@testable import Declutter

/// Merges and deletes real contacts in the simulator's address book, then cleans up.
/// Skipped without Contacts access.
@Suite("Contacts store (simulator)", .serialized,
       .enabled(if: CNContactStore.authorizationStatus(for: .contacts) == .authorized, "Needs Contacts access"))
struct ContactsStoreTests {
    private let store = CNContactStore()
    private let marker = "ZZDeclutterTest"

    private func add(_ contact: CNMutableContact) throws -> String {
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
        return contact.identifier
    }

    private func fetch(_ ids: [String]) throws -> [CNContact] {
        try store.unifiedContacts(
            matching: CNContact.predicateForContacts(withIdentifiers: ids),
            keysToFetch: [
                CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            ].map { $0 as CNKeyDescriptor }
        )
    }

    private func cleanUp() throws {
        let leftovers = try store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: marker),
            keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
        )
        guard !leftovers.isEmpty else { return }
        let request = CNSaveRequest()
        leftovers.compactMap { $0.mutableCopy() as? CNMutableContact }.forEach(request.delete)
        try store.execute(request)
    }

    @Test func editedMergeIsSavedAndTheDuplicateIsDeleted() async throws {
        try cleanUp()
        defer { try? cleanUp() }

        let keptID = try add(Fixture.contact("Kiran", marker, phones: ["+91 91234 56789"]))
        let otherID = try add(Fixture.contact("K", marker, phones: ["9123456789", "+1 415 555 0142"], emails: ["kiran@example.com"]))

        let plan = MergePlan(
            contactIDs: [keptID, otherID],
            primaryID: keptID,
            name: .custom(given: "Kiran", family: marker),
            phoneKeys: [ContactsService.phoneDedupKey("9123456789")],
            emailKeys: ["kiran@example.com"],
            photoFrom: nil
        )
        try await ContactsService.merge(plan)

        let remaining = try fetch([keptID, otherID])
        #expect(remaining.map(\.identifier) == [keptID])
        let merged = try #require(remaining.first)
        #expect(merged.phoneNumbers.map { $0.value.stringValue } == ["+91 91234 56789"])
        #expect(merged.emailAddresses.map { $0.value as String } == ["kiran@example.com"])
    }

    @Test func deleteRemovesOnlyTheChosenContacts() async throws {
        try cleanUp()
        defer { try? cleanUp() }

        let keep = try add(Fixture.contact("Keep", marker))
        let remove = try add(Fixture.contact("Remove", marker))
        try await ContactsService.delete([remove])
        #expect(try fetch([keep, remove]).map(\.identifier) == [keep])
    }
}
