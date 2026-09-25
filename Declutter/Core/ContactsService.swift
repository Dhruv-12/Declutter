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

    /// What the contact will look like after merging.
    var mergedPreview: (name: String, phones: [String], emails: [String]) {
        let name = primary.name.isEmpty ? (contacts.first { !$0.name.isEmpty }?.name ?? primary.displayName) : primary.name
        var phones: [String] = [], phoneKeys: Set<String> = []
        var emails: [String] = [], emailKeys: Set<String> = []
        for contact in [primary] + contacts.filter({ $0.id != primary.id }) {
            for phone in contact.phones where phoneKeys.insert(ContactsService.phoneKey(phone) ?? phone).inserted {
                phones.append(phone)
            }
            for email in contact.emails where emailKeys.insert(email.lowercased()).inserted {
                emails.append(email)
            }
        }
        return (name, phones, emails)
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

    /// Copies every detail apps are allowed to read from the other contacts into `primaryID`,
    /// then deletes the others. (Notes need a special Apple entitlement, so they can't be copied.)
    @concurrent
    static func merge(_ ids: [String], into primaryID: String) async throws {
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
        let contacts = try store.unifiedContacts(
            matching: CNContact.predicateForContacts(withIdentifiers: ids),
            keysToFetch: keys
        )
        // If any contact changed or vanished since the preview, stop rather than merge something unexpected.
        guard contacts.count == ids.count, let primary = contacts.first(where: { $0.identifier == primaryID })?.mutableCopy() as? CNMutableContact
        else { throw ContactsError.notFound }

        let request = CNSaveRequest()
        for other in contacts where other.identifier != primaryID {
            fillIfEmpty(&primary.namePrefix, other.namePrefix)
            fillIfEmpty(&primary.givenName, other.givenName)
            fillIfEmpty(&primary.middleName, other.middleName)
            fillIfEmpty(&primary.familyName, other.familyName)
            fillIfEmpty(&primary.nameSuffix, other.nameSuffix)
            fillIfEmpty(&primary.previousFamilyName, other.previousFamilyName)
            fillIfEmpty(&primary.phoneticGivenName, other.phoneticGivenName)
            fillIfEmpty(&primary.phoneticMiddleName, other.phoneticMiddleName)
            fillIfEmpty(&primary.phoneticFamilyName, other.phoneticFamilyName)
            fillIfEmpty(&primary.nickname, other.nickname)
            fillIfEmpty(&primary.organizationName, other.organizationName)
            fillIfEmpty(&primary.departmentName, other.departmentName)
            fillIfEmpty(&primary.jobTitle, other.jobTitle)
            if primary.birthday == nil { primary.birthday = other.birthday }
            if primary.nonGregorianBirthday == nil { primary.nonGregorianBirthday = other.nonGregorianBirthday }
            if primary.imageData == nil { primary.imageData = other.imageData }

            primary.phoneNumbers = mergeValues(primary.phoneNumbers, other.phoneNumbers) {
                phoneKey($0.stringValue) ?? $0.stringValue
            }
            primary.emailAddresses = mergeValues(primary.emailAddresses, other.emailAddresses) {
                ($0 as String).lowercased()
            }
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
        request.update(primary)
        try store.execute(request)
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
