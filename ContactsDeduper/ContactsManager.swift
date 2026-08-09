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
        var countsByName: [String: Int] = [:]
        for contact in contacts where contactIDs.contains(contact.identifier) {
            countsByName[contact.displayName, default: 0] += 1
        }

        return countsByName
            .map { name, count in
                count == 1 ? name : "\(name)（\(count) 个）"
            }
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

struct ContactAccount: Identifiable, Hashable {
    let id: String
    let name: String
    let typeName: String
    let contactCount: Int
}

struct DuplicateContactList: Identifiable {
    let id: String
    let name: String
    let containerName: String
    let containerIdentifier: String
    let groups: [CNGroup]
    let membersByGroupIdentifier: [String: [CNContact]]

    var uniqueMemberCount: Int {
        Set(membersByGroupIdentifier.values.flatMap { $0.map(\.identifier) }).count
    }

    var detail: String {
        "\(groups.count) 个 List · \(uniqueMemberCount) 位联系人"
    }
}

struct ContactListBulkMergeResult {
    let mergedSetCount: Int
    let deletedListCount: Int
    let addedMemberCount: Int
}

enum DuplicateMatchKind: String {
    case name
    case phone
    case email
}

/// How much evidence two contacts must share before they count as duplicates.
enum DuplicateMatchRule: String, CaseIterable, Identifiable {
    case dual
    case any
    case nameOnly
    case phoneOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dual:
            return "两项相同"
        case .any:
            return "任一项相同"
        case .nameOnly:
            return "仅名称相同"
        case .phoneOnly:
            return "仅电话相同"
        }
    }

    var shortTitle: String {
        switch self {
        case .dual:
            return "两项"
        case .any:
            return "任一项"
        case .nameOnly:
            return "仅名称"
        case .phoneOnly:
            return "仅电话"
        }
    }

    var detail: String {
        switch self {
        case .dual:
            return "名称、电话、邮箱中至少两项同时相同才算重复"
        case .any:
            return "名称、电话或邮箱任意一项相同就算重复"
        case .nameOnly:
            return "只看名称，公司类联系人按公司名比对"
        case .phoneOnly:
            return "只看电话，忽略名称与邮箱"
        }
    }

    var consideredKinds: Set<DuplicateMatchKind> {
        switch self {
        case .dual, .any:
            return [.name, .phone, .email]
        case .nameOnly:
            return [.name]
        case .phoneOnly:
            return [.phone]
        }
    }

    var requiredMatchCount: Int {
        self == .dual ? 2 : 1
    }
}

struct BulkMergePlanItem: Identifiable {
    let id: String
    let title: String
    let reasonSummary: String
    let keeperName: String
    let keeperSummary: String
    let removedNames: [String]
    let additions: [String]

    var removedSummary: String {
        removedNames.joined(separator: "、")
    }

    var additionSummary: String {
        additions.isEmpty ? "无新增资料" : "补齐 \(additions.joined(separator: " · "))"
    }
}

private struct ContactPair: Hashable {
    let first: String
    let second: String
}

extension CNContact {
    /// `CNContactFormatter` needs private sorting keys that no public
    /// `CNContactXXXKey` constant covers, so contacts must be fetched with this
    /// descriptor before a name can be formatted.
    static let displayNameDescriptor = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)

    var displayName: String {
        guard areKeysAvailable([Self.displayNameDescriptor]) else { return "未命名联系人" }
        return CNContactFormatter.string(from: self, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
    @Published private(set) var contactAccounts: [ContactAccount] = []
    @Published private(set) var activeAccount: ContactAccount?
    @Published private(set) var allContacts: [CNContact] = []
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published private(set) var duplicateContactLists: [DuplicateContactList] = []
    @Published private(set) var bulkMergeProgress: Double?
    @Published private(set) var bulkMergeStatus: String?
    @Published private(set) var contactListMergeProgress: Double?
    @Published private(set) var contactListMergeStatus: String?
    @Published private(set) var matchRule: DuplicateMatchRule = .dual
    @Published var isLoading = false
    @Published var errorMessage: String?

    private static let matchRuleDefaultsKey = "duplicateMatchRule"

    private let store = CNContactStore()

    init() {
        let storedRule = UserDefaults.standard.string(forKey: Self.matchRuleDefaultsKey)
        matchRule = storedRule.flatMap(DuplicateMatchRule.init(rawValue:)) ?? .dual
    }

    var isBulkMerging: Bool {
        bulkMergeProgress != nil
    }

    var isBulkMergingContactLists: Bool {
        contactListMergeProgress != nil
    }

    var totalContactCount: Int {
        contactAccounts.reduce(0) { $0 + $1.contactCount }
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

            contactAccounts = try fetchContactAccounts()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        if let activeAccount {
            await loadAccount(activeAccount)
        } else {
            await loadAccounts()
        }
    }

    func loadAccounts() async {
        guard hasContactsAccess else {
            await requestAccessAndLoad()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            contactAccounts = try fetchContactAccounts()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAccount(_ account: ContactAccount) async {
        guard hasContactsAccess else {
            await requestAccessAndLoad()
            return
        }

        if activeAccount?.id != account.id {
            allContacts = []
            duplicateGroups = []
            duplicateContactLists = []
        }
        activeAccount = account
        isLoading = true
        defer { isLoading = false }

        do {
            try reloadActiveAccount()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setMatchRule(_ rule: DuplicateMatchRule) {
        guard rule != matchRule else { return }
        matchRule = rule
        UserDefaults.standard.set(rule.rawValue, forKey: Self.matchRuleDefaultsKey)
        duplicateGroups = findDuplicates(in: allContacts)
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

        try refreshVisibleState()
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
            try? refreshVisibleState()
            throw error
        }

        allContacts = []
        duplicateGroups = []
        duplicateContactLists = []
        activeAccount = nil
        contactAccounts = try fetchContactAccounts()
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

    /// Dry run of `mergeAllDuplicates`: what each group would keep, delete, and gain.
    func makeBulkMergePlan() -> [BulkMergePlanItem] {
        duplicateGroups.compactMap { group in
            guard let keeper = preferredKeeper(in: group) else { return nil }
            let removed = group.contacts.filter { $0.identifier != keeper.identifier }
            guard !removed.isEmpty else { return nil }

            return BulkMergePlanItem(
                id: group.id,
                title: group.displayName,
                reasonSummary: group.reasonSummary,
                keeperName: keeper.displayName,
                keeperSummary: contactSummary(keeper),
                removedNames: removed.map(\.displayName),
                additions: additionSummaries(keeper: keeper, others: removed)
            )
        }
    }

    func mergeAllDuplicates(groupIDs: Set<String>) async throws -> BulkMergeResult {
        guard hasContactsAccess else {
            throw ContactsBackupError.accessDenied
        }

        let groups = duplicateGroups.filter { groupIDs.contains($0.id) }
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
            try? refreshVisibleState()
            throw error
        }

        bulkMergeStatus = "正在重新扫描"
        bulkMergeProgress = 0.98
        await Task.yield()

        try reloadActiveAccount()
        errorMessage = nil

        return BulkMergeResult(
            mergedGroupCount: groups.count,
            deletedContactCount: deletedContactCount,
            contactCountBefore: contactCountBefore,
            contactCountAfter: allContacts.count,
            remainingDuplicateGroupCount: duplicateGroups.count,
            completedAt: Date(),
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    func mergeAllDuplicateContactLists() async throws -> ContactListBulkMergeResult {
        guard hasContactsAccess else {
            throw ContactsBackupError.accessDenied
        }

        let duplicateLists = duplicateContactLists
        guard !duplicateLists.isEmpty else {
            return ContactListBulkMergeResult(
                mergedSetCount: 0,
                deletedListCount: 0,
                addedMemberCount: 0
            )
        }

        contactListMergeProgress = 0
        contactListMergeStatus = "正在准备 List 合并"
        defer {
            contactListMergeProgress = nil
            contactListMergeStatus = nil
        }

        let request = CNSaveRequest()
        var deletedListCount = 0
        var addedMemberCount = 0

        for (index, duplicateList) in duplicateLists.enumerated() {
            guard let keeper = preferredListKeeper(in: duplicateList) else { continue }
            var keeperMemberIDs = Set(
                duplicateList.membersByGroupIdentifier[keeper.identifier, default: []]
                    .map(\.identifier)
            )

            for group in duplicateList.groups where group.identifier != keeper.identifier {
                for contact in duplicateList.membersByGroupIdentifier[group.identifier, default: []] {
                    if keeperMemberIDs.insert(contact.identifier).inserted {
                        request.addMember(contact, to: keeper)
                        addedMemberCount += 1
                    }
                }
                request.delete(group.mutableCopy() as! CNMutableGroup)
                deletedListCount += 1
            }

            contactListMergeStatus = "正在整理第 \(index + 1) / \(duplicateLists.count) 组 List"
            contactListMergeProgress = Double(index + 1) / Double(duplicateLists.count) * 0.85
            await Task.yield()
        }

        contactListMergeStatus = "正在写入通讯录"
        contactListMergeProgress = 0.92
        await Task.yield()

        do {
            try store.execute(request)
        } catch {
            try? refreshVisibleState()
            throw error
        }

        contactListMergeStatus = "正在重新扫描"
        contactListMergeProgress = 0.98
        await Task.yield()
        try reloadActiveAccount()
        errorMessage = nil

        return ContactListBulkMergeResult(
            mergedSetCount: duplicateLists.count,
            deletedListCount: deletedListCount,
            addedMemberCount: addedMemberCount
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

    private func fetchContacts(in containerIdentifier: String? = nil) throws -> [CNContact] {
        let keys: [CNKeyDescriptor] = [
            CNContact.displayNameDescriptor,
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

        if let containerIdentifier {
            let predicate = CNContact.predicateForContactsInContainer(
                withIdentifier: containerIdentifier
            )
            let contacts = try fetchNonUnifiedContacts(matching: predicate, keysToFetch: keys)
            return uniqueContacts(contacts).sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }

        var contacts: [CNContact] = []
        var seenIdentifiers = Set<String>()
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName
        request.unifyResults = true

        try store.enumerateContacts(with: request) { contact, _ in
            if seenIdentifiers.insert(contact.identifier).inserted {
                contacts.append(contact)
            }
        }

        return contacts
    }

    private func updateContactState(with contacts: [CNContact], account: ContactAccount) throws {
        allContacts = contacts
        duplicateGroups = findDuplicates(in: contacts)
        duplicateContactLists = try fetchDuplicateContactLists(in: account)
    }

    private func fetchDuplicateContactLists(in account: ContactAccount) throws -> [DuplicateContactList] {
        var duplicates: [DuplicateContactList] = []
        let memberKeys = [CNContactIdentifierKey as CNKeyDescriptor]

        let groupPredicate = CNGroup.predicateForGroupsInContainer(withIdentifier: account.id)
        let groups = try store.groups(matching: groupPredicate)
        let groupsByName = Dictionary(grouping: groups) { normalizeListName($0.name) }

        for (normalizedName, matchingGroups) in groupsByName {
            guard !normalizedName.isEmpty, matchingGroups.count > 1 else { continue }

            var membersByGroupIdentifier: [String: [CNContact]] = [:]
            for group in matchingGroups {
                let memberPredicate = CNContact.predicateForContactsInGroup(
                    withIdentifier: group.identifier
                )
                membersByGroupIdentifier[group.identifier] = try fetchNonUnifiedContacts(
                    matching: memberPredicate,
                    keysToFetch: memberKeys
                )
            }

            let displayName = matchingGroups
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .sorted()
                .first ?? normalizedName
            duplicates.append(
                DuplicateContactList(
                    id: "\(account.id)|\(normalizedName)",
                    name: displayName,
                    containerName: account.name,
                    containerIdentifier: account.id,
                    groups: matchingGroups,
                    membersByGroupIdentifier: membersByGroupIdentifier
                )
            )
        }

        return duplicates.sorted {
            if $0.groups.count == $1.groups.count {
                if $0.name == $1.name {
                    return $0.containerName < $1.containerName
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.groups.count > $1.groups.count
        }
    }

    private func fetchContactAccounts() throws -> [ContactAccount] {
        let containers = try store.containers(matching: nil)
        let identifierKey = [CNContactIdentifierKey as CNKeyDescriptor]

        return try containers.map { container in
            let predicate = CNContact.predicateForContactsInContainer(
                withIdentifier: container.identifier
            )
            let contacts = try fetchNonUnifiedContacts(
                matching: predicate,
                keysToFetch: identifierKey
            )
            let trimmedName = container.name.trimmingCharacters(in: .whitespacesAndNewlines)

            return ContactAccount(
                id: container.identifier,
                name: trimmedName.isEmpty ? containerTypeName(container.type) : trimmedName,
                typeName: containerTypeName(container.type),
                contactCount: Set(contacts.map(\.identifier)).count
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func reloadActiveAccount() throws {
        guard let activeAccount else { return }
        let contacts = try fetchContacts(in: activeAccount.id)
        let refreshedAccount = ContactAccount(
            id: activeAccount.id,
            name: activeAccount.name,
            typeName: activeAccount.typeName,
            contactCount: contacts.count
        )
        self.activeAccount = refreshedAccount
        if let index = contactAccounts.firstIndex(where: { $0.id == refreshedAccount.id }) {
            contactAccounts[index] = refreshedAccount
        }
        try updateContactState(with: contacts, account: refreshedAccount)
    }

    private func refreshVisibleState() throws {
        contactAccounts = try fetchContactAccounts()
        if let activeAccount,
           let refreshedAccount = contactAccounts.first(where: { $0.id == activeAccount.id }) {
            self.activeAccount = refreshedAccount
            try reloadActiveAccount()
        } else {
            activeAccount = nil
            allContacts = []
            duplicateGroups = []
            duplicateContactLists = []
        }
    }

    private func uniqueContacts(_ contacts: [CNContact]) -> [CNContact] {
        var seenIdentifiers = Set<String>()
        return contacts.filter { seenIdentifiers.insert($0.identifier).inserted }
    }

    private func fetchNonUnifiedContacts(
        matching predicate: NSPredicate,
        keysToFetch: [CNKeyDescriptor]
    ) throws -> [CNContact] {
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.predicate = predicate
        request.unifyResults = false

        var contacts: [CNContact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            contacts.append(contact)
        }
        return contacts
    }

    private func containerTypeName(_ type: CNContainerType) -> String {
        switch type {
        case .local:
            return "本机"
        case .exchange:
            return "Exchange"
        case .cardDAV:
            return "CardDAV"
        case .unassigned:
            return "其他账户"
        @unknown default:
            return "其他账户"
        }
    }

    private func normalizeListName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        var kindByKey: [String: DuplicateMatchKind] = [:]

        for contact in contacts {
            byID[contact.identifier] = contact

            let phones = contact.phoneNumbers
                .map { normalizePhone($0.value.stringValue) }
                .filter { !$0.isEmpty }
            for phone in phones {
                let key = "phone:\(phone)"
                buckets[key, default: []].insert(contact.identifier)
                reasonByKey[key] = "相同电话 \(phone)"
                kindByKey[key] = .phone
            }

            let emails = contact.emailAddresses
                .map { normalizeEmail(String($0.value)) }
                .filter { !$0.isEmpty }
            for email in emails {
                let key = "email:\(email)"
                buckets[key, default: []].insert(contact.identifier)
                reasonByKey[key] = "相同邮箱 \(email)"
                kindByKey[key] = .email
            }

            if let nameSignal = nameSignal(for: contact) {
                let key = "name:\(nameSignal.key)"
                buckets[key, default: []].insert(contact.identifier)
                reasonByKey[key] = nameSignal.description
                kindByKey[key] = .name
            }
        }

        let consideredKinds = matchRule.consideredKinds
        let candidateBuckets = buckets.filter { key, ids in
            guard ids.count > 1, let kind = kindByKey[key] else { return false }
            return consideredKinds.contains(kind)
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

        if matchRule.requiredMatchCount > 1 {
            // A shared bucket is only one piece of evidence, so tally the kinds of
            // evidence per contact pair and link a pair only once it clears the bar.
            var kindsByPair: [ContactPair: Set<DuplicateMatchKind>] = [:]
            for (key, ids) in candidateBuckets {
                guard let kind = kindByKey[key] else { continue }
                let sortedIDs = ids.sorted()
                for firstIndex in sortedIDs.indices {
                    for secondIndex in sortedIDs.index(after: firstIndex)..<sortedIDs.endIndex {
                        let pair = ContactPair(
                            first: sortedIDs[firstIndex],
                            second: sortedIDs[secondIndex]
                        )
                        kindsByPair[pair, default: []].insert(kind)
                    }
                }
            }

            for (pair, kinds) in kindsByPair where kinds.count >= matchRule.requiredMatchCount {
                union(pair.first, pair.second)
            }
        } else {
            for ids in candidateBuckets.values {
                guard let first = ids.first else { continue }
                for id in ids.dropFirst() {
                    union(first, id)
                }
            }
        }

        var groupedIDs: [String: Set<String>] = [:]
        for contact in contacts {
            groupedIDs[root(contact.identifier), default: []].insert(contact.identifier)
        }

        // A bucket can span several groups now, so credit each group only with the
        // members it actually contains.
        var reasonsByRoot: [String: [DuplicateReason]] = [:]
        for (key, ids) in candidateBuckets {
            var idsByRoot: [String: Set<String>] = [:]
            for id in ids {
                idsByRoot[root(id), default: []].insert(id)
            }
            for (rootID, sharedIDs) in idsByRoot where sharedIDs.count > 1 {
                reasonsByRoot[rootID, default: []].append(
                    DuplicateReason(
                        id: key,
                        description: reasonByKey[key] ?? "疑似重复",
                        contactIDs: sharedIDs
                    )
                )
            }
        }

        let groups = groupedIDs.compactMap { rootID, ids -> DuplicateGroup? in
            let contacts = ids.compactMap { byID[$0] }.sorted { $0.displayName < $1.displayName }
            guard contacts.count > 1 else { return nil }
            return DuplicateGroup(
                id: stableGroupID(for: ids),
                reasons: reasonsByRoot[rootID, default: []].sorted { $0.id < $1.id },
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

    private func stableGroupID(for contactIDs: Set<String>) -> String {
        contactIDs.sorted().joined(separator: "|")
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

    private func preferredListKeeper(in duplicateList: DuplicateContactList) -> CNGroup? {
        duplicateList.groups.max { first, second in
            let firstCount = duplicateList.membersByGroupIdentifier[first.identifier]?.count ?? 0
            let secondCount = duplicateList.membersByGroupIdentifier[second.identifier]?.count ?? 0
            if firstCount == secondCount {
                return first.identifier > second.identifier
            }
            return firstCount < secondCount
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

    private func contactSummary(_ contact: CNContact) -> String {
        [contact.phoneSummary, contact.emailSummary, contact.organizationName]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func additionSummaries(keeper: CNContact, others: [CNContact]) -> [String] {
        let merged = keeper.mutableCopy() as! CNMutableContact
        for contact in others {
            mergeValues(from: contact, into: merged)
        }

        var summaries: [String] = []
        func appendGrowth(_ label: String, _ before: Int, _ after: Int) {
            if after > before {
                summaries.append("\(label) +\(after - before)")
            }
        }

        appendGrowth("电话", keeper.phoneNumbers.count, merged.phoneNumbers.count)
        appendGrowth("邮箱", keeper.emailAddresses.count, merged.emailAddresses.count)
        appendGrowth("地址", keeper.postalAddresses.count, merged.postalAddresses.count)
        appendGrowth("网址", keeper.urlAddresses.count, merged.urlAddresses.count)
        appendGrowth("纪念日", keeper.dates.count, merged.dates.count)
        appendGrowth("关系", keeper.contactRelations.count, merged.contactRelations.count)
        appendGrowth("社交", keeper.socialProfiles.count, merged.socialProfiles.count)
        appendGrowth(
            "即时通讯",
            keeper.instantMessageAddresses.count,
            merged.instantMessageAddresses.count
        )

        if keeper.birthday == nil, merged.birthday != nil {
            summaries.append("生日")
        }
        if keeper.nonGregorianBirthday == nil, merged.nonGregorianBirthday != nil {
            summaries.append("农历生日")
        }
        if !keeper.imageDataAvailable, merged.imageData != nil {
            summaries.append("头像")
        }

        let filledTextCount = zip(textFields(of: keeper), textFields(of: merged))
            .filter { $0.isEmpty && !$1.isEmpty }
            .count
        if filledTextCount > 0 {
            summaries.append("文字资料 +\(filledTextCount)")
        }

        return summaries
    }

    private func textFields(of contact: CNContact) -> [String] {
        [
            contact.namePrefix, contact.givenName, contact.middleName, contact.familyName,
            contact.previousFamilyName, contact.nameSuffix, contact.nickname,
            contact.phoneticGivenName, contact.phoneticMiddleName, contact.phoneticFamilyName,
            contact.organizationName, contact.departmentName, contact.jobTitle
        ]
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

    /// Company-only contacts carry no person name, so fall back to the organization —
    /// it is what `displayName` already shows for them. The fallback is deliberately
    /// *not* an extra signal for contacts that do have a person name: colleagues
    /// legitimately share an employer, and pairing that with a shared switchboard
    /// number would merge two different people.
    private func nameSignal(for contact: CNContact) -> (key: String, description: String)? {
        let personName = [contact.familyName, contact.givenName, contact.middleName]
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !personName.isEmpty {
            return (personName.lowercased(), "相同姓名 \(contact.displayName)")
        }

        let organizationName = contact.organizationName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !organizationName.isEmpty else { return nil }
        return (organizationName.lowercased(), "相同公司 \(organizationName)")
    }
}
