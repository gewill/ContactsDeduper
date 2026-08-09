import Contacts
import Foundation

struct DuplicateGroup: Identifiable {
    let id: String
    let reasons: [DuplicateReason]
    let contacts: [CNContact]

    var displayName: String {
        contacts.first?.displayName ?? "未命名联系人"
    }

    var detail: String {
        "\(contacts.count) 个联系人 · \(reasons.count) 条依据"
    }

    var reasonSummary: String {
        guard let firstReason = reasons.first else { return "疑似重复" }
        if reasons.count == 1 {
            return firstReason.description
        }
        return "\(firstReason.description)等 \(reasons.count) 条依据"
    }
}

struct DuplicateReason: Identifiable {
    let id: String
    let description: String
    let contactIDs: Set<String>

    func matchingContactNames(in contacts: [CNContact]) -> String {
        contacts
            .filter { contactIDs.contains($0.identifier) }
            .map(\.displayName)
            .sorted()
            .joined(separator: "、")
    }
}

struct BulkMergeResult: Identifiable {
    let id = UUID()
    let mergedGroupCount: Int
    let deletedContactCount: Int
    let contactCountBefore: Int
    let contactCountAfter: Int
    let remainingDuplicateGroupCount: Int
    let completedAt: Date
    let duration: TimeInterval
}

extension CNContact {
    var displayName: String {
        let formatter = CNContactFormatter()
        formatter.style = .fullName
        return formatter.string(from: self)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? organizationName.nilIfEmpty
            ?? "未命名联系人"
    }

    var phoneSummary: String {
        phoneNumbers.map { $0.value.stringValue }.joined(separator: ", ")
    }

    var emailSummary: String {
        emailAddresses.map { String($0.value) }.joined(separator: ", ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

@MainActor
final class ContactsManager: ObservableObject {
    @Published private(set) var authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @Published private(set) var allContacts: [CNContact] = []
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published private(set) var bulkMergeProgress: Double?
    @Published private(set) var bulkMergeStatus: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store = CNContactStore()

    var isBulkMerging: Bool {
        bulkMergeProgress != nil
    }

    func requestAccessAndLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if authorizationStatus == .notDetermined {
                _ = try await store.requestAccess(for: .contacts)
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
            }

            guard hasContactsAccess else {
                errorMessage = "请在系统设置中允许访问通讯录。"
                return
            }

            let contacts = try fetchContacts()
            allContacts = contacts
            duplicateGroups = findDuplicates(in: contacts)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await requestAccessAndLoad()
    }

    func makeBackupDocument() throws -> ContactsBackupDocument {
        guard hasContactsAccess else {
            throw ContactsBackupError.accessDenied
        }

        let archive = ContactsBackupArchive(contacts: try fetchContacts())
        return ContactsBackupDocument(data: try archive.encoded())
    }

    func previewBackup(data: Data) throws -> ContactImportPreview {
        guard hasContactsAccess else {
            throw ContactsBackupError.accessDenied
        }

        let archive = try ContactsBackupArchive.decode(from: data)
        let existingContacts = try fetchContacts()
        return ContactImportPreview(
            exportedAt: archive.exportedAt,
            contactCount: archive.contacts.count,
            contactsToAdd: countContactsToAdd(archive.contacts, comparedWith: existingContacts)
        )
    }

    func importBackup(data: Data) async throws -> ContactImportResult {
        guard hasContactsAccess else {
            throw ContactsBackupError.accessDenied
        }

        isLoading = true
        defer { isLoading = false }

        let archive = try ContactsBackupArchive.decode(from: data)
        let existingContacts = try fetchContacts()
        var existingBySignature = Dictionary(grouping: existingContacts) {
            BackupContact(contact: $0).duplicateSignature
        }

        let request = CNSaveRequest()
        var addedCount = 0
        var skippedCount = 0
        var restoredImageCount = 0

        for backupContact in archive.contacts {
            let signature = backupContact.duplicateSignature
            if var matches = existingBySignature[signature], !matches.isEmpty {
                let existingContact = matches.removeFirst()
                existingBySignature[signature] = matches
                skippedCount += 1

                if let imageData = backupContact.imageData, !existingContact.imageDataAvailable {
                    let mutableContact = existingContact.mutableCopy() as! CNMutableContact
                    mutableContact.imageData = imageData
                    request.update(mutableContact)
                    restoredImageCount += 1
                }
            } else {
                request.add(backupContact.makeMutableContact(), toContainerWithIdentifier: nil)
                addedCount += 1
            }
        }

        if addedCount > 0 || restoredImageCount > 0 {
            try store.execute(request)
        }

        let contacts = try fetchContacts()
        allContacts = contacts
        duplicateGroups = findDuplicates(in: contacts)
        errorMessage = nil

        return ContactImportResult(
            addedCount: addedCount,
            skippedCount: skippedCount,
            restoredImageCount: restoredImageCount
        )
    }

    func deleteAllContacts() async throws -> Int {
        guard hasContactsAccess else {
            throw ContactsBackupError.accessDenied
        }

        isLoading = true
        defer { isLoading = false }

        let contacts = try fetchContacts()
        guard !contacts.isEmpty else { return 0 }

        let request = CNSaveRequest()
        for contact in contacts {
            request.delete(contact.mutableCopy() as! CNMutableContact)
        }

        do {
            try store.execute(request)
        } catch {
            let remainingContacts = try fetchContacts()
            allContacts = remainingContacts
            duplicateGroups = findDuplicates(in: remainingContacts)
            throw error
        }

        allContacts = []
        duplicateGroups = []
        errorMessage = nil
        return contacts.count
    }

    func merge(_ group: DuplicateGroup, keeping keeper: CNContact) async {
        do {
            let mutableKeeper = keeper.mutableCopy() as! CNMutableContact
            for contact in group.contacts where contact.identifier != keeper.identifier {
                mergeValues(from: contact, into: mutableKeeper)
            }

            let request = CNSaveRequest()
            request.update(mutableKeeper)

            for contact in group.contacts where contact.identifier != keeper.identifier {
                let mutableContact = contact.mutableCopy() as! CNMutableContact
                request.delete(mutableContact)
            }

            try store.execute(request)
            await refresh()
        } catch {
            errorMessage = "合并失败：\(error.localizedDescription)"
        }
    }

    func mergeAllDuplicates() async throws -> BulkMergeResult {
        guard hasContactsAccess else {
            throw ContactsBackupError.accessDenied
        }

        let groups = duplicateGroups
        guard !groups.isEmpty else {
            return BulkMergeResult(
                mergedGroupCount: 0,
                deletedContactCount: 0,
                contactCountBefore: allContacts.count,
                contactCountAfter: allContacts.count,
                remainingDuplicateGroupCount: 0,
                completedAt: Date(),
                duration: 0
            )
        }

        let startedAt = Date()
        let contactCountBefore = allContacts.count

        bulkMergeProgress = 0
        bulkMergeStatus = "正在准备合并"
        defer {
            bulkMergeProgress = nil
            bulkMergeStatus = nil
        }

        let request = CNSaveRequest()
        var deletedContactCount = 0

        for (index, group) in groups.enumerated() {
            guard let keeper = preferredKeeper(in: group) else { continue }
            let mutableKeeper = keeper.mutableCopy() as! CNMutableContact

            for contact in group.contacts where contact.identifier != keeper.identifier {
                mergeValues(from: contact, into: mutableKeeper)
                request.delete(contact.mutableCopy() as! CNMutableContact)
                deletedContactCount += 1
            }
            request.update(mutableKeeper)

            bulkMergeStatus = "正在整理第 \(index + 1) / \(groups.count) 组"
            bulkMergeProgress = Double(index + 1) / Double(groups.count) * 0.85
            await Task.yield()
        }

        bulkMergeStatus = "正在写入通讯录"
        bulkMergeProgress = 0.92
        await Task.yield()

        do {
            try store.execute(request)
        } catch {
            if let remainingContacts = try? fetchContacts() {
                allContacts = remainingContacts
                duplicateGroups = findDuplicates(in: remainingContacts)
            }
            throw error
        }

        bulkMergeStatus = "正在重新扫描"
        bulkMergeProgress = 0.98
        await Task.yield()

        let contacts = try fetchContacts()
        allContacts = contacts
        duplicateGroups = findDuplicates(in: contacts)
        errorMessage = nil

        return BulkMergeResult(
            mergedGroupCount: groups.count,
            deletedContactCount: deletedContactCount,
            contactCountBefore: contactCountBefore,
            contactCountAfter: contacts.count,
            remainingDuplicateGroupCount: duplicateGroups.count,
            completedAt: Date(),
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    func delete(_ contact: CNContact) async {
        do {
            let request = CNSaveRequest()
            request.delete(contact.mutableCopy() as! CNMutableContact)
            try store.execute(request)
            await refresh()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    private func fetchContacts() throws -> [CNContact] {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactTypeKey as CNKeyDescriptor,
            CNContactNamePrefixKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactPreviousFamilyNameKey as CNKeyDescriptor,
            CNContactNameSuffixKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactPhoneticGivenNameKey as CNKeyDescriptor,
            CNContactPhoneticMiddleNameKey as CNKeyDescriptor,
            CNContactPhoneticFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactNonGregorianBirthdayKey as CNKeyDescriptor,
            CNContactDatesKey as CNKeyDescriptor,
            CNContactRelationsKey as CNKeyDescriptor,
            CNContactSocialProfilesKey as CNKeyDescriptor,
            CNContactInstantMessageAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor
        ]

        var contacts: [CNContact] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName

        try store.enumerateContacts(with: request) { contact, _ in
            contacts.append(contact)
        }

        return contacts
    }

    private func countContactsToAdd(
        _ backupContacts: [BackupContact],
        comparedWith existingContacts: [CNContact]
    ) -> Int {
        var existingCounts: [String: Int] = [:]
        for contact in existingContacts {
            existingCounts[BackupContact(contact: contact).duplicateSignature, default: 0] += 1
        }

        var additions = 0
        for contact in backupContacts {
            let signature = contact.duplicateSignature
            if existingCounts[signature, default: 0] > 0 {
                existingCounts[signature, default: 0] -= 1
            } else {
                additions += 1
            }
        }
        return additions
    }

    private var hasContactsAccess: Bool {
        if authorizationStatus == .authorized {
            return true
        }
#if os(iOS)
        if #available(iOS 18.0, *), authorizationStatus == .limited {
            return true
        }
#endif
        return false
    }

    private func findDuplicates(in contacts: [CNContact]) -> [DuplicateGroup] {
        var buckets: [String: Set<String>] = [:]
        var byID: [String: CNContact] = [:]
        var reasonByKey: [String: String] = [:]

        for contact in contacts {
            byID[contact.identifier] = contact

            let phones = contact.phoneNumbers
                .map { normalizePhone($0.value.stringValue) }
                .filter { !$0.isEmpty }
            for phone in phones {
                let key = "phone:\(phone)"
                buckets[key, default: []].insert(contact.identifier)
                reasonByKey[key] = "相同电话 \(phone)"
            }

            let emails = contact.emailAddresses
                .map { normalizeEmail(String($0.value)) }
                .filter { !$0.isEmpty }
            for email in emails {
                let key = "email:\(email)"
                buckets[key, default: []].insert(contact.identifier)
                reasonByKey[key] = "相同邮箱 \(email)"
            }

            let nameKey = normalizeName(contact)
            if !nameKey.isEmpty {
                let key = "name:\(nameKey)"
                buckets[key, default: []].insert(contact.identifier)
                reasonByKey[key] = "相同姓名 \(contact.displayName)"
            }
        }

        var parent = Dictionary(uniqueKeysWithValues: contacts.map { ($0.identifier, $0.identifier) })
        func root(_ id: String) -> String {
            var current = id
            while let next = parent[current], next != current {
                current = next
            }
            return current
        }
        func union(_ first: String, _ second: String) {
            let firstRoot = root(first)
            let secondRoot = root(second)
            if firstRoot != secondRoot {
                parent[secondRoot] = firstRoot
            }
        }

        let duplicateBuckets = buckets.filter { $0.value.count > 1 }
        for ids in duplicateBuckets.values {
            guard let first = ids.first else { continue }
            for id in ids.dropFirst() {
                union(first, id)
            }
        }

        var groupedIDs: [String: Set<String>] = [:]
        for ids in duplicateBuckets.values {
            for id in ids {
                groupedIDs[root(id), default: []].insert(id)
            }
        }

        var reasonsByRoot: [String: [DuplicateReason]] = [:]
        for (key, ids) in duplicateBuckets.sorted(by: { $0.key < $1.key }) {
            guard let first = ids.first else { continue }
            reasonsByRoot[root(first), default: []].append(
                DuplicateReason(
                    id: key,
                    description: reasonByKey[key] ?? "疑似重复",
                    contactIDs: ids
                )
            )
        }

        let groups = groupedIDs.compactMap { rootID, ids -> DuplicateGroup? in
            let contacts = ids.compactMap { byID[$0] }.sorted { $0.displayName < $1.displayName }
            guard contacts.count > 1 else { return nil }
            return DuplicateGroup(
                id: rootID,
                reasons: reasonsByRoot[rootID, default: []],
                contacts: contacts
            )
        }

        return groups.sorted {
            if $0.contacts.count == $1.contacts.count {
                return $0.displayName < $1.displayName
            }
            return $0.contacts.count > $1.contacts.count
        }
    }

    private func mergeValues(from contact: CNContact, into keeper: CNMutableContact) {
        if keeper.namePrefix.isEmpty { keeper.namePrefix = contact.namePrefix }
        if keeper.givenName.isEmpty { keeper.givenName = contact.givenName }
        if keeper.familyName.isEmpty { keeper.familyName = contact.familyName }
        if keeper.middleName.isEmpty { keeper.middleName = contact.middleName }
        if keeper.previousFamilyName.isEmpty { keeper.previousFamilyName = contact.previousFamilyName }
        if keeper.nameSuffix.isEmpty { keeper.nameSuffix = contact.nameSuffix }
        if keeper.nickname.isEmpty { keeper.nickname = contact.nickname }
        if keeper.phoneticGivenName.isEmpty { keeper.phoneticGivenName = contact.phoneticGivenName }
        if keeper.phoneticMiddleName.isEmpty { keeper.phoneticMiddleName = contact.phoneticMiddleName }
        if keeper.phoneticFamilyName.isEmpty { keeper.phoneticFamilyName = contact.phoneticFamilyName }
        if keeper.organizationName.isEmpty { keeper.organizationName = contact.organizationName }
        if keeper.departmentName.isEmpty { keeper.departmentName = contact.departmentName }
        if keeper.jobTitle.isEmpty { keeper.jobTitle = contact.jobTitle }
        if keeper.birthday == nil { keeper.birthday = contact.birthday }
        if keeper.nonGregorianBirthday == nil { keeper.nonGregorianBirthday = contact.nonGregorianBirthday }
        if keeper.imageData == nil, contact.imageDataAvailable {
            keeper.imageData = contact.imageData
        }

        keeper.phoneNumbers = uniqueLabeledValues(
            existing: keeper.phoneNumbers,
            incoming: contact.phoneNumbers,
            normalizer: { normalizePhone($0.value.stringValue) }
        )
        keeper.emailAddresses = uniqueLabeledValues(
            existing: keeper.emailAddresses,
            incoming: contact.emailAddresses,
            normalizer: { normalizeEmail(String($0.value)) }
        )
        keeper.postalAddresses = uniqueLabeledValues(
            existing: keeper.postalAddresses,
            incoming: contact.postalAddresses,
            normalizer: { "\($0.value.street)|\($0.value.city)|\($0.value.state)|\($0.value.postalCode)|\($0.value.country)" }
        )
        keeper.urlAddresses = uniqueLabeledValues(
            existing: keeper.urlAddresses,
            incoming: contact.urlAddresses,
            normalizer: { String($0.value).lowercased() }
        )
        keeper.dates = uniqueLabeledValues(
            existing: keeper.dates,
            incoming: contact.dates,
            normalizer: { value in
                let date = value.value as DateComponents
                return "\(date.era ?? -1)|\(date.year ?? -1)|\(date.month ?? -1)|\(date.day ?? -1)"
            }
        )
        keeper.contactRelations = uniqueLabeledValues(
            existing: keeper.contactRelations,
            incoming: contact.contactRelations,
            normalizer: { $0.value.name.lowercased() }
        )
        keeper.socialProfiles = uniqueLabeledValues(
            existing: keeper.socialProfiles,
            incoming: contact.socialProfiles,
            normalizer: {
                "\($0.value.service)|\($0.value.username)|\($0.value.userIdentifier)|\($0.value.urlString)".lowercased()
            }
        )
        keeper.instantMessageAddresses = uniqueLabeledValues(
            existing: keeper.instantMessageAddresses,
            incoming: contact.instantMessageAddresses,
            normalizer: { "\($0.value.service)|\($0.value.username)".lowercased() }
        )
    }

    private func preferredKeeper(in group: DuplicateGroup) -> CNContact? {
        group.contacts.max { first, second in
            let firstScore = contactInformationScore(first)
            let secondScore = contactInformationScore(second)
            if firstScore == secondScore {
                return first.identifier > second.identifier
            }
            return firstScore < secondScore
        }
    }

    private func contactInformationScore(_ contact: CNContact) -> Int {
        let textValues = [
            contact.namePrefix, contact.givenName, contact.middleName, contact.familyName,
            contact.previousFamilyName, contact.nameSuffix, contact.nickname,
            contact.phoneticGivenName, contact.phoneticMiddleName, contact.phoneticFamilyName,
            contact.organizationName, contact.departmentName, contact.jobTitle
        ]
        let populatedTextCount = textValues.filter { !$0.isEmpty }.count
        let collectionValueCount = contact.phoneNumbers.count
            + contact.emailAddresses.count
            + contact.postalAddresses.count
            + contact.urlAddresses.count
            + contact.dates.count
            + contact.contactRelations.count
            + contact.socialProfiles.count
            + contact.instantMessageAddresses.count

        return populatedTextCount
            + collectionValueCount * 2
            + (contact.birthday == nil ? 0 : 2)
            + (contact.nonGregorianBirthday == nil ? 0 : 2)
            + (contact.imageDataAvailable ? 3 : 0)
    }

    private func uniqueLabeledValues<Value>(
        existing: [CNLabeledValue<Value>],
        incoming: [CNLabeledValue<Value>],
        normalizer: (CNLabeledValue<Value>) -> String
    ) -> [CNLabeledValue<Value>] {
        var seen = Set(existing.map(normalizer))
        var result = existing

        for value in incoming {
            let key = normalizer(value)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }

        return result
    }

    private func normalizePhone(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        if digits.hasPrefix("1"), digits.count == 11 {
            return String(digits.dropFirst())
        }
        return digits
    }

    private func normalizeEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeName(_ contact: CNContact) -> String {
        [contact.familyName, contact.givenName, contact.middleName]
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
