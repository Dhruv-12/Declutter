import Contacts
import Foundation
import Testing
@testable import Declutter

@Suite("Duplicate contact detection")
struct DuplicateContactTests {
    @Test func sameNameIgnoringCaseAccentsAndWordOrder() {
        let groups = ContactsService.groupDuplicates([
            Fixture.contact("José", "Silva"),
            Fixture.contact("silva", "jose"),
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.contacts.count == 2)
        #expect(groups.first?.reasons == [.name])
    }

    @Test func phoneNumbersMatchAcrossFormats() {
        let groups = ContactsService.groupDuplicates([
            Fixture.contact("Asha", "Verma", phones: ["+91 98765 43210"]),
            Fixture.contact("A", "V", phones: ["098765-43210"]),
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.reasons == [.phone])
    }

    @Test func emailsIgnoreCapitalLetters() {
        let groups = ContactsService.groupDuplicates([
            Fixture.contact("Rahul", "Mehta", emails: ["rahul@example.com"]),
            Fixture.contact("R", "M", emails: ["RAHUL@Example.com"]),
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.reasons == [.email])
    }

    @Test func unrelatedContactsStaySeparate() {
        let groups = ContactsService.groupDuplicates([
            Fixture.contact("Vikram", "Singh", phones: ["+91 90000 11111"], emails: ["vikram@example.com"]),
            Fixture.contact("Priya", "Nair", phones: ["+91 90000 22222"], emails: ["priya@example.com"]),
        ])
        #expect(groups.isEmpty)
    }

    @Test func matchesChainIntoOneGroup() {
        // A and B share a phone, B and C share an email: all three are the same person.
        let groups = ContactsService.groupDuplicates([
            Fixture.contact("Neha", "Kapoor", phones: ["+1 415 555 0101"]),
            Fixture.contact("N", "K", phones: ["4155550101"], emails: ["neha@example.com"]),
            Fixture.contact("Nehu", "", emails: ["neha@example.com"]),
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.contacts.count == 3)
        #expect(groups.first?.reasons == [.phone, .email])
    }

    @Test func shortNumbersAndOneLetterNamesAreNotEnough() {
        let groups = ContactsService.groupDuplicates([
            Fixture.contact("A", "", phones: ["12345"]),
            Fixture.contact("A", "", phones: ["12345"]),
        ])
        #expect(groups.isEmpty)
    }

    @Test func emptyAddressBook() {
        #expect(ContactsService.groupDuplicates([]).isEmpty)
    }

    @Test func fullestContactIsKept() {
        let groups = ContactsService.groupDuplicates([
            Fixture.contact("Sam", "Lee"),
            Fixture.contact("Sam", "Lee", phones: ["+1 415 555 0199"], emails: ["sam@example.com"]),
        ])
        #expect(groups.first?.primary.phones == ["+1 415 555 0199"])
    }

    @Test func dedupKeys() {
        #expect(ContactsService.phoneDedupKey("+91 98765 43210") == ContactsService.phoneDedupKey("9876543210"))
        #expect(ContactsService.phoneDedupKey("(415) 555-0101") == "4155550101")
        #expect(ContactsService.phoneDedupKey("+91 98765 43210") != ContactsService.phoneDedupKey("+91 98765 43211"))
        #expect(ContactsService.emailDedupKey(" Asha@Example.COM ") == "asha@example.com")
        #expect(ContactsService.nameKey(for: Fixture.contact("Sean", "O'Brien")) == ContactsService.nameKey(for: Fixture.contact("O Brien", "Sean")))
    }
}

@Suite("Merge preview defaults and Merge all")
struct MergeDraftTests {
    private let photo = Data([1, 2, 3])

    private func group() -> ContactGroup {
        ContactGroup(
            id: "g1",
            contacts: [
                Fixture.summary("a", name: "Asha Verma", phones: ["+91 98765 43210"], emails: ["Asha@Example.com"], fields: 3),
                Fixture.summary("b", name: "Asha V", phones: ["9876543210", "+1 555 010 0000"], emails: ["asha@example.com"], thumbnail: photo, fields: 2),
            ],
            reasons: [.phone]
        )
    }

    @Test func keepsOneCopyOfEachNumberAndEmailByDefault() {
        let draft = MergeDraft(group: group())
        #expect(draft.phones.map(\.display) == ["+91 98765 43210", "+1 555 010 0000"])
        #expect(draft.phones.first?.duplicatesRemoved == 1)
        #expect(draft.emails.count == 1)
        #expect(draft.emails.first?.duplicatesRemoved == 1)
        #expect(draft.phones.allSatisfy(\.isIncluded) && draft.emails.allSatisfy(\.isIncluded))
    }

    @Test func defaultsToTheFullestContactsNameAndAnyAvailablePhoto() {
        let draft = MergeDraft(group: group())
        #expect(draft.primary.id == "a")
        #expect(draft.finalName == "Asha Verma")
        // The kept contact has no photo, so the other contact's photo is used.
        #expect(draft.photoFrom == "b")
        #expect(draft.nameOptions.map(\.id) == ["a", "b"])
    }

    @Test func editedDraftBecomesTheMergePlan() {
        var draft = MergeDraft(group: group())
        draft.useCustomName = true
        draft.customGiven = "  Asha "
        draft.customFamily = "Verma-Rao"
        draft.phones[1].isIncluded = false
        draft.emails[0].isIncluded = false
        draft.photoFrom = nil

        let plan = draft.plan
        #expect(plan.primaryID == "a")
        #expect(plan.contactIDs == ["a", "b"])
        #expect(plan.name == .custom(given: "Asha", family: "Verma-Rao"))
        #expect(plan.phoneKeys == ["9876543210"])
        #expect(plan.emailKeys.isEmpty)
        #expect(plan.photoFrom == nil)
        #expect(draft.finalName == "Asha Verma-Rao")
    }

    @Test func blankTypedNameIsInvalid() {
        var draft = MergeDraft(group: group())
        draft.useCustomName = true
        draft.customGiven = "   "
        #expect(!draft.isValid)
        draft.customGiven = "A"
        #expect(draft.isValid)
    }

    @Test func mergeAllSkipsUntickedGroups() {
        var first = MergeDraft(group: group())
        var second = MergeDraft(group: ContactGroup(
            id: "g2",
            contacts: [Fixture.summary("c", name: "Sam Lee"), Fixture.summary("d", name: "Sam Lee")],
            reasons: [.name]
        ))
        first.isIncluded = false
        second.useCustomName = true
        second.customGiven = "Samuel"

        let approved = MergeDraft.approved([first, second])
        #expect(approved.map(\.id) == ["g2"])
        #expect(approved.first?.plan.name == .custom(given: "Samuel", family: ""))
        #expect(MergeDraft.approved([first]).isEmpty)
    }
}

@Suite("Merge result")
struct MergeResultTests {
    private func pair() -> (kept: CNMutableContact, other: CNMutableContact) {
        let kept = Fixture.contact("Asha", "Verma", phones: ["+91 98765 43210"], emails: ["asha@example.com"])
        kept.namePrefix = "Dr"
        let other = Fixture.contact("Asha", "V", phones: ["9876543210", "+1 555 010 0000"], emails: ["ASHA@example.com", "work@example.com"], image: Data([9, 9]))
        other.birthday = DateComponents(month: 4, day: 12)
        let address = CNMutablePostalAddress()
        address.street = "1 MG Road"
        address.city = "Bengaluru"
        other.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: address)]
        return (kept, other)
    }

    private func plan(
        _ kept: CNContact, _ other: CNContact,
        name: NameChoice? = nil,
        phones: Set<String>? = nil,
        emails: Set<String>? = nil,
        photoFrom: String?? = .none
    ) -> MergePlan {
        let allPhones = Set((kept.phoneNumbers + other.phoneNumbers).map { ContactsService.phoneDedupKey($0.value.stringValue) })
        let allEmails = Set((kept.emailAddresses + other.emailAddresses).map { ContactsService.emailDedupKey($0.value as String) })
        return MergePlan(
            contactIDs: [kept.identifier, other.identifier],
            primaryID: kept.identifier,
            name: name ?? .contact(kept.identifier),
            phoneKeys: phones ?? allPhones,
            emailKeys: emails ?? allEmails,
            photoFrom: photoFrom ?? kept.identifier
        )
    }

    @Test func defaultMergeCombinesEverythingOnce() throws {
        let (kept, other) = pair()
        let result = try ContactsService.mergedContact(plan(kept, other), from: [kept, other])

        #expect(result.removed.map(\.identifier) == [other.identifier])
        #expect(result.kept.identifier == kept.identifier)
        #expect(result.kept.phoneNumbers.map { $0.value.stringValue } == ["+91 98765 43210", "+1 555 010 0000"])
        #expect(result.kept.emailAddresses.map { $0.value as String } == ["asha@example.com", "work@example.com"])
        #expect(result.kept.postalAddresses.count == 1)
        #expect(result.kept.birthday?.day == 12)
        #expect(result.kept.givenName == "Asha" && result.kept.familyName == "Verma" && result.kept.namePrefix == "Dr")
    }

    @Test func editedMergeFollowsTheUsersChoices() throws {
        let (kept, other) = pair()
        let edited = plan(
            kept, other,
            name: .custom(given: "Asha", family: "Rao"),
            phones: ["9876543210"],
            emails: [],
            photoFrom: .some(other.identifier)
        )
        let result = try ContactsService.mergedContact(edited, from: [kept, other])

        #expect(result.kept.givenName == "Asha" && result.kept.familyName == "Rao")
        #expect(result.kept.namePrefix.isEmpty)
        #expect(result.kept.phoneNumbers.map { $0.value.stringValue } == ["+91 98765 43210"])
        #expect(result.kept.emailAddresses.isEmpty)
        #expect(result.kept.imageData == Data([9, 9]))
    }

    @Test func nameCanComeFromTheOtherContact() throws {
        let (kept, other) = pair()
        let result = try ContactsService.mergedContact(plan(kept, other, name: .contact(other.identifier)), from: [kept, other])
        #expect(result.kept.familyName == "V")
        #expect(result.kept.namePrefix.isEmpty)
    }

    @Test func choosingNoPhotoRemovesIt() throws {
        let (kept, other) = pair()
        kept.imageData = Data([1])
        let result = try ContactsService.mergedContact(plan(kept, other, photoFrom: .some(nil)), from: [kept, other])
        #expect(result.kept.imageData == nil)
    }

    @Test func missingContactStopsTheMerge() {
        let (kept, other) = pair()
        #expect(throws: ContactsError.self) {
            try ContactsService.mergedContact(plan(kept, other), from: [kept])
        }
    }
}
