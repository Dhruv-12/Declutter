import Contacts
import Foundation

/// A read-only snapshot of a contact, safe to pass around the app.
nonisolated struct ContactSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let organization: String
    let phones: [String]
    let emails: [String]
    let thumbnail: Data?
    /// How much information the contact holds; the fullest one is kept when merging.
    let fieldCount: Int

    var displayName: String {
        if !name.isEmpty { return name }
        if !organization.isEmpty { return organization }
        return phones.first ?? emails.first ?? "No Name"
    }

    var initials: String {
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

nonisolated enum MatchReason: String, CaseIterable, Sendable {
    case name = "Same name"
    case phone = "Same phone"
    case email = "Same email"
}

nonisolated struct ContactGroup: Identifiable, Hashable, Sendable {
    let id: String
    let contacts: [ContactSummary]
    let reasons: [MatchReason]

    /// The contact with the most details. The others are merged into it.
    var primary: ContactSummary {
        contacts.max { $0.fieldCount < $1.fieldCount } ?? contacts[0]
    }
}

nonisolated struct ContactScanResult: Sendable {
    let groups: [ContactGroup]
    let totalContacts: Int
}

enum ContactsError: LocalizedError {
    case notFound

    var errorDescription: String? {
        "Some of these contacts no longer exist. Pull to refresh and try again."
    }
}

/// Finds and fixes duplicate contacts. Everything stays on the device.
nonisolated enum ContactsService {
    private static var summaryKeys: [CNKeyDescriptor] {
        [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
        ]
    }

    // MARK: - Finding duplicates

    @concurrent
    static func findDuplicates() async throws -> ContactScanResult {
        let store = CNContactStore()
        var contacts: [CNContact] = []
        let request = CNContactFetchRequest(keysToFetch: summaryKeys)
        request.unifyResults = true
        try store.enumerateContacts(with: request) { contact, _ in contacts.append(contact) }

        // Link contacts that share a name, phone number or email address.
        var unionFind = UnionFind(count: contacts.count)
        var firstIndexForKey: [String: Int] = [:]

        func link(_ index: Int, key: String, reason: MatchReason) {
            let fullKey = "\(reason.rawValue):\(key)"
            if let other = firstIndexForKey[fullKey] {
                unionFind.union(other, index)
            } else {
                firstIndexForKey[fullKey] = index
            }
        }

        for (index, contact) in contacts.enumerated() {
            if let name = nameKey(for: contact) { link(index, key: name, reason: .name) }
            for phone in Set(contact.phoneNumbers.compactMap { phoneKey($0.value.stringValue) }) {
                link(index, key: phone, reason: .phone)
            }
            for email in Set(contact.emailAddresses.map { ($0.value as String).lowercased().trimmingCharacters(in: .whitespaces) }) where !email.isEmpty {
                link(index, key: email, reason: .email)
            }
        }

        var members: [Int: [Int]] = [:]
        for index in contacts.indices {
            members[unionFind.find(index), default: []].append(index)
        }

        let groups = members.values
            .filter { $0.count > 1 }
            .map { indices -> ContactGroup in
                let groupContacts = indices.map { contacts[$0] }
                return ContactGroup(
                    id: groupContacts.map(\.identifier).sorted().joined(separator: "|"),
                    contacts: groupContacts.map(summary),
                    reasons: reasons(for: groupContacts)
                )
            }
            .sorted { $0.primary.displayName.localizedStandardCompare($1.primary.displayName) == .orderedAscending }

        return ContactScanResult(groups: groups, totalContacts: contacts.count)
    }

    /// Name with case, accents, spacing and word order ignored, so "José  Silva" matches "silva jose".
    static func nameKey(for contact: CNContact) -> String? {
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let words = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .sorted()
        let key = words.joined(separator: " ")
        return key.count >= 2 ? key : nil
    }

    /// Last 10 digits, so "+91 98765 43210" and "098765 43210" match.
    static func phoneKey(_ phone: String) -> String? {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        return String(digits.suffix(10))
    }

    private static func reasons(for contacts: [CNContact]) -> [MatchReason] {
        var found: Set<MatchReason> = []
        let names = contacts.compactMap(nameKey)
        if Set(names).count < names.count { found.insert(.name) }
        let phones = contacts.flatMap { Set($0.phoneNumbers.compactMap { phoneKey($0.value.stringValue) }) }
        if Set(phones).count < phones.count { found.insert(.phone) }
        let emails = contacts.flatMap { Set($0.emailAddresses.map { ($0.value as String).lowercased() }) }
        if Set(emails).count < emails.count { found.insert(.email) }
        return MatchReason.allCases.filter(found.contains)
    }

    private static func summary(_ contact: CNContact) -> ContactSummary {
        let fields = [
            contact.givenName, contact.familyName, contact.organizationName, contact.jobTitle, contact.nickname,
        ].filter { !$0.isEmpty }.count
            + contact.phoneNumbers.count + contact.emailAddresses.count
            + contact.postalAddresses.count + contact.urlAddresses.count
            + (contact.birthday == nil ? 0 : 1) + (contact.thumbnailImageData == nil ? 0 : 1)

        return ContactSummary(
            id: contact.identifier,
            name: CNContactFormatter.string(from: contact, style: .fullName) ?? "",
            organization: contact.organizationName,
            phones: contact.phoneNumbers.map { $0.value.stringValue },
            emails: contact.emailAddresses.map { $0.value as String },
            thumbnail: contact.thumbnailImageData,
            fieldCount: fields
        )
    }

    // MARK: - Changing contacts

    /// Merges a group exactly as the user approved it in the merge editor: the chosen name, only the
    /// ticked phone numbers and emails, and the chosen photo. Every other detail apps are allowed to
    /// read is combined, then the other contacts are deleted.
    /// (Notes need a special Apple entitlement, so they can't be copied.)
    @concurrent
    static func merge(_ plan: MergePlan) async throws {
        let store = CNContactStore()
        let keys = summaryKeys + [
            CNContactImageDataKey,
            CNContactNamePrefixKey,
            CNContactMiddleNameKey,
            CNContactNameSuffixKey,
            CNContactPreviousFamilyNameKey,
            CNContactPhoneticGivenNameKey,
            CNContactPhoneticMiddleNameKey,
            CNContactPhoneticFamilyNameKey,
            CNContactDepartmentNameKey,
            CNContactNonGregorianBirthdayKey,
            CNContactDatesKey,
            CNContactSocialProfilesKey,
            CNContactInstantMessageAddressesKey,
            CNContactRelationsKey,
        ].map { $0 as CNKeyDescriptor }
        let fetched = try store.unifiedContacts(
            matching: CNContact.predicateForContacts(withIdentifiers: plan.contactIDs),
            keysToFetch: keys
        )
        // If any contact changed or vanished since the preview, stop rather than merge something unexpected.
        let byID = Dictionary(fetched.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        guard byID.count == plan.contactIDs.count,
              let original = byID[plan.primaryID],
              let primary = original.mutableCopy() as? CNMutableContact
        else { throw ContactsError.notFound }

        // Same order as the editor: the kept contact first, then the others as listed.
        let others = plan.contactIDs.filter { $0 != plan.primaryID }.compactMap { byID[$0] }
        let ordered = [original] + others

        let request = CNSaveRequest()
        for other in others {
            fillIfEmpty(&primary.previousFamilyName, other.previousFamilyName)
            fillIfEmpty(&primary.nickname, other.nickname)
            fillIfEmpty(&primary.organizationName, other.organizationName)
            fillIfEmpty(&primary.departmentName, other.departmentName)
            fillIfEmpty(&primary.jobTitle, other.jobTitle)
            if primary.birthday == nil { primary.birthday = other.birthday }
            if primary.nonGregorianBirthday == nil { primary.nonGregorianBirthday = other.nonGregorianBirthday }

            primary.urlAddresses = mergeValues(primary.urlAddresses, other.urlAddresses) {
                ($0 as String).lowercased()
            }
            primary.postalAddresses = mergeValues(primary.postalAddresses, other.postalAddresses) {
                CNPostalAddressFormatter.string(from: $0, style: .mailingAddress).lowercased()
            }
            primary.dates = mergeValues(primary.dates, other.dates) {
                "\($0.year)-\($0.month)-\($0.day)"
            }
            primary.socialProfiles = mergeValues(primary.socialProfiles, other.socialProfiles) {
                "\($0.service)|\($0.username)|\($0.urlString)".lowercased()
            }
            primary.instantMessageAddresses = mergeValues(primary.instantMessageAddresses, other.instantMessageAddresses) {
                "\($0.service)|\($0.username)".lowercased()
            }
            primary.contactRelations = mergeValues(primary.contactRelations, other.contactRelations) {
                $0.name.lowercased()
            }

            if let removable = other.mutableCopy() as? CNMutableContact {
                request.delete(removable)
            }
        }

        // Phone numbers and emails: one copy of each, and only the ones the user ticked.
        primary.phoneNumbers = pickValues(ordered.flatMap(\.phoneNumbers), keep: plan.phoneKeys) {
            phoneDedupKey($0.stringValue)
        }
        primary.emailAddresses = pickValues(ordered.flatMap(\.emailAddresses), keep: plan.emailKeys) {
            emailDedupKey($0 as String)
        }

        // Name: copied whole from the chosen contact, or the user's own.
        switch plan.name {
        case .contact(let id):
            if let source = byID[id] {
                primary.namePrefix = source.namePrefix
                primary.givenName = source.givenName
                primary.middleName = source.middleName
                primary.familyName = source.familyName
                primary.nameSuffix = source.nameSuffix
                primary.phoneticGivenName = source.phoneticGivenName
                primary.phoneticMiddleName = source.phoneticMiddleName
                primary.phoneticFamilyName = source.phoneticFamilyName
            }
        case .custom(let given, let family):
            primary.namePrefix = ""
            primary.givenName = given
            primary.middleName = ""
            primary.familyName = family
            primary.nameSuffix = ""
            primary.phoneticGivenName = ""
            primary.phoneticMiddleName = ""
            primary.phoneticFamilyName = ""
        }

        // Photo: the chosen contact's, or none.
        if let photoID = plan.photoFrom {
            if photoID != plan.primaryID { primary.imageData = byID[photoID]?.imageData }
        } else {
            primary.imageData = nil
        }

        request.update(primary)
        try store.execute(request)
    }

    /// Phone numbers are the same if their digits match, ignoring spaces, symbols and a country
    /// code: "+91 98765 43210" and "9876543210" both become "9876543210".
    static func phoneDedupKey(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        return digits.isEmpty ? phone.lowercased() : String(digits.suffix(10))
    }

    static func emailDedupKey(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// First copy of each value whose key is in `keep`, as fresh labeled values.
    private static func pickValues<Value: NSCopying & NSSecureCoding>(
        _ values: [CNLabeledValue<Value>],
        keep: Set<String>,
        key: (Value) -> String
    ) -> [CNLabeledValue<Value>] {
        var seen = Set<String>()
        return values.compactMap { item in
            let itemKey = key(item.value)
            guard keep.contains(itemKey), seen.insert(itemKey).inserted else { return nil }
            return CNLabeledValue(label: item.label, value: item.value)
        }
    }

    /// Permanently deletes contacts. Contacts have no "Recently Deleted" folder.
    @concurrent
    static func delete(_ ids: [String]) async throws {
        let store = CNContactStore()
        let contacts = try store.unifiedContacts(
            matching: CNContact.predicateForContacts(withIdentifiers: ids),
            keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
        )
        let request = CNSaveRequest()
        for contact in contacts {
            if let removable = contact.mutableCopy() as? CNMutableContact { request.delete(removable) }
        }
        try store.execute(request)
    }

    private static func fillIfEmpty(_ value: inout String, _ other: String) {
        if value.isEmpty { value = other }
    }

    /// Adds values from `other` whose key isn't already present, as fresh labeled values.
    private static func mergeValues<Value: NSCopying & NSSecureCoding>(
        _ existing: [CNLabeledValue<Value>],
        _ other: [CNLabeledValue<Value>],
        key: (Value) -> String
    ) -> [CNLabeledValue<Value>] {
        var result = existing
        var seen = Set(existing.map { key($0.value) })
        for item in other where seen.insert(key(item.value)).inserted {
            result.append(CNLabeledValue(label: item.label, value: item.value))
        }
        return result
    }
}
