import Contacts
import XCTest

/// Merging deletes contacts, so what it carries over and which record it keeps are
/// the two decisions that can silently destroy data.
@MainActor
final class ContactMergeTests: XCTestCase {
    private var manager: ContactsManager!

    override func setUp() {
        super.setUp()
        manager = ContactsManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeContact(
        given: String = "",
        family: String = "",
        phones: [String] = [],
        emails: [String] = [],
        organization: String = "",
        jobTitle: String = "",
        imageData: Data? = nil,
        birthdayYear: Int? = nil
    ) -> CNContact {
        let contact = CNMutableContact()
        contact.givenName = given
        contact.familyName = family
        contact.organizationName = organization
        contact.jobTitle = jobTitle
        contact.imageData = imageData
        contact.phoneNumbers = phones.map {
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
        }
        contact.emailAddresses = emails.map {
            CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
        }
        if let birthdayYear {
            var birthday = DateComponents()
            birthday.year = birthdayYear
            birthday.month = 1
            birthday.day = 1
            contact.birthday = birthday
        }
        return contact.copy() as! CNContact
    }

    private func merged(_ keeper: CNContact, with others: CNContact...) -> CNMutableContact {
        let result = keeper.mutableCopy() as! CNMutableContact
        for other in others {
            manager.mergeValues(from: other, into: result)
        }
        return result
    }

    // MARK: - Field preservation

    func testEmptyScalarFieldsAreFilledFromTheOtherContact() {
        let keeper = makeContact(given: "三", family: "张")
        let other = makeContact(given: "三", family: "张", organization: "顺丰速运", jobTitle: "经理")

        let result = merged(keeper, with: other)
        XCTAssertEqual(result.organizationName, "顺丰速运")
        XCTAssertEqual(result.jobTitle, "经理")
    }

    func testPopulatedScalarFieldsAreNeverOverwritten() {
        let keeper = makeContact(given: "三", family: "张", organization: "顺丰速运")
        let other = makeContact(given: "三", family: "张", organization: "阿里巴巴")

        XCTAssertEqual(merged(keeper, with: other).organizationName, "顺丰速运")
    }

    func testDistinctPhonesAndEmailsFromBothContactsAreKept() {
        let keeper = makeContact(given: "三", phones: ["5550000001"], emails: ["a@x.com"])
        let other = makeContact(given: "三", phones: ["5550000002"], emails: ["b@x.com"])

        let result = merged(keeper, with: other)
        XCTAssertEqual(
            result.phoneNumbers.map { $0.value.stringValue }.sorted(),
            ["5550000001", "5550000002"]
        )
        XCTAssertEqual(result.emailAddresses.map { String($0.value) }.sorted(), ["a@x.com", "b@x.com"])
    }

    func testTheSameNumberWrittenDifferentlyIsNotDuplicated() {
        // De-duplication runs on the normalized value, not the raw string.
        let keeper = makeContact(given: "三", phones: ["5550000001"])
        let other = makeContact(given: "三", phones: ["555-000-0001"])

        XCTAssertEqual(merged(keeper, with: other).phoneNumbers.count, 1)
    }

    func testEmailCasingDoesNotCreateASecondEntry() {
        let keeper = makeContact(given: "三", emails: ["ann@example.com"])
        let other = makeContact(given: "三", emails: ["ANN@Example.com"])

        XCTAssertEqual(merged(keeper, with: other).emailAddresses.count, 1)
    }

    func testMissingAvatarIsRestoredButAnExistingOneIsKept() {
        let keeperImage = Data([0x01])
        let otherImage = Data([0x02])

        let withoutImage = makeContact(given: "三")
        let withImage = makeContact(given: "三", imageData: otherImage)
        XCTAssertEqual(merged(withoutImage, with: withImage).imageData, otherImage)

        let alreadyHasImage = makeContact(given: "三", imageData: keeperImage)
        XCTAssertEqual(merged(alreadyHasImage, with: withImage).imageData, keeperImage)
    }

    func testMissingBirthdayIsFilledButAnExistingOneIsKept() {
        let withoutBirthday = makeContact(given: "三")
        let born1990 = makeContact(given: "三", birthdayYear: 1990)
        XCTAssertEqual(merged(withoutBirthday, with: born1990).birthday?.year, 1990)

        let born1985 = makeContact(given: "三", birthdayYear: 1985)
        XCTAssertEqual(merged(born1985, with: born1990).birthday?.year, 1985)
    }

    func testMergingThreeContactsAccumulatesEveryDistinctValue() {
        let keeper = makeContact(given: "三", phones: ["5550000001"])
        let second = makeContact(given: "三", phones: ["5550000002"], organization: "顺丰速运")
        let third = makeContact(given: "三", phones: ["5550000003"], jobTitle: "经理")

        let result = merged(keeper, with: second, third)
        XCTAssertEqual(result.phoneNumbers.count, 3)
        XCTAssertEqual(result.organizationName, "顺丰速运")
        XCTAssertEqual(result.jobTitle, "经理")
    }

    // MARK: - Keeper selection

    private func makeGroup(_ contacts: [CNContact]) -> DuplicateGroup {
        DuplicateGroup(
            id: contacts.map(\.identifier).sorted().joined(separator: "|"),
            reasons: [],
            contacts: contacts
        )
    }

    func testKeeperIsTheContactWithTheMostInformation() {
        let sparse = makeContact(given: "三", family: "张")
        let rich = makeContact(
            given: "三",
            family: "张",
            phones: ["5550000001", "5550000002"],
            emails: ["a@x.com"],
            organization: "顺丰速运",
            imageData: Data([0x01])
        )

        XCTAssertEqual(manager.preferredKeeper(in: makeGroup([sparse, rich]))?.identifier, rich.identifier)
        // Order of the group must not change the answer.
        XCTAssertEqual(manager.preferredKeeper(in: makeGroup([rich, sparse]))?.identifier, rich.identifier)
    }

    func testAnAvatarOutweighsNothingElseChanging() {
        let plain = makeContact(given: "三", family: "张", phones: ["5550000001"])
        let withAvatar = makeContact(
            given: "三",
            family: "张",
            phones: ["5550000001"],
            imageData: Data([0x01])
        )

        XCTAssertEqual(
            manager.preferredKeeper(in: makeGroup([plain, withAvatar]))?.identifier,
            withAvatar.identifier
        )
    }

    func testKeeperSelectionIsStableWhenScoresTie() {
        // Which identifier wins is arbitrary — equally rich records are equally good
        // keepers. What matters is that the answer never depends on group ordering,
        // so the same scan always deletes the same record.
        let first = makeContact(given: "三", family: "张", phones: ["5550000001"])
        let second = makeContact(given: "四", family: "李", phones: ["5550000002"])
        let expected = min(first.identifier, second.identifier)

        XCTAssertEqual(manager.preferredKeeper(in: makeGroup([first, second]))?.identifier, expected)
        XCTAssertEqual(manager.preferredKeeper(in: makeGroup([second, first]))?.identifier, expected)
    }

    func testKeeperIsNilForAnEmptyGroup() {
        XCTAssertNil(manager.preferredKeeper(in: makeGroup([])))
    }

    // MARK: - What the merge preview promises

    func testPreviewCountsEveryFieldTheMergeWillAdd() {
        let keeper = makeContact(given: "三", family: "张")
        let other = makeContact(
            given: "三",
            family: "张",
            phones: ["5550000001", "5550000002"],
            emails: ["a@x.com"],
            organization: "顺丰速运",
            imageData: Data([0x01]),
            birthdayYear: 1990
        )

        let summaries = manager.additionSummaries(keeper: keeper, others: [other])
        XCTAssertTrue(summaries.contains("电话 +2"), "\(summaries)")
        XCTAssertTrue(summaries.contains("邮箱 +1"), "\(summaries)")
        XCTAssertTrue(summaries.contains("生日"), "\(summaries)")
        XCTAssertTrue(summaries.contains("头像"), "\(summaries)")
        XCTAssertTrue(summaries.contains("文字资料 +1"), "\(summaries)")
    }

    func testPreviewPromisesNothingWhenTheKeeperAlreadyHasEverything() {
        let keeper = makeContact(given: "三", family: "张", phones: ["5550000001"], emails: ["a@x.com"])
        let other = makeContact(given: "三", family: "张", phones: ["555-000-0001"])

        XCTAssertTrue(manager.additionSummaries(keeper: keeper, others: [other]).isEmpty)
    }

    func testPreviewSummaryMatchesWhatTheMergeActuallyProduces() {
        // The preview is a dry run of mergeValues, so the two must not drift apart.
        let keeper = makeContact(given: "三", family: "张", phones: ["5550000001"])
        let other = makeContact(given: "三", family: "张", phones: ["5550000002"], emails: ["a@x.com"])

        let summaries = manager.additionSummaries(keeper: keeper, others: [other])
        let result = merged(keeper, with: other)

        XCTAssertEqual(summaries.contains("电话 +1"), result.phoneNumbers.count == 2)
        XCTAssertEqual(summaries.contains("邮箱 +1"), result.emailAddresses.count == 1)
    }

    func testPlanItemRendersAdditionsAndRemovals() {
        let nothingNew = BulkMergePlanItem(
            id: "a",
            title: "张三",
            reasonSummary: "相同姓名 张三",
            keeperName: "张三",
            keeperSummary: "",
            removedNames: ["张三"],
            additions: []
        )
        XCTAssertEqual(nothingNew.additionSummary, "无新增资料")
        XCTAssertEqual(nothingNew.removedSummary, "张三")

        let withAdditions = BulkMergePlanItem(
            id: "b",
            title: "张三",
            reasonSummary: "相同姓名 张三",
            keeperName: "张三",
            keeperSummary: "",
            removedNames: ["张三", "张小三"],
            additions: ["电话 +1", "头像"]
        )
        XCTAssertEqual(withAdditions.additionSummary, "补齐 电话 +1 · 头像")
        XCTAssertEqual(withAdditions.removedSummary, "张三、张小三")
    }

    // MARK: - Import preview arithmetic

    func testImportCountsOnlyContactsThatAreMissing() {
        let existing = [
            makeContact(given: "三", family: "张"),
            makeContact(given: "四", family: "李")
        ]
        let incoming = [
            BackupContact(contact: makeContact(given: "三", family: "张")),
            BackupContact(contact: makeContact(given: "五", family: "王"))
        ]

        XCTAssertEqual(manager.countContactsToAdd(incoming, comparedWith: existing), 1)
    }

    func testRepeatedIncomingContactsAreCountedOncePerExistingCopy() {
        // Two identical records in the file, one already on the device: exactly one
        // of them is new.
        let existing = [makeContact(given: "三", family: "张")]
        let incoming = [
            BackupContact(contact: makeContact(given: "三", family: "张")),
            BackupContact(contact: makeContact(given: "三", family: "张"))
        ]

        XCTAssertEqual(manager.countContactsToAdd(incoming, comparedWith: existing), 1)
    }

    func testImportAddsNothingWhenTheBackupIsAlreadyOnTheDevice() {
        let existing = [makeContact(given: "三", family: "张")]
        let incoming = [BackupContact(contact: makeContact(given: "三", family: "张"))]

        XCTAssertEqual(manager.countContactsToAdd(incoming, comparedWith: existing), 0)
    }

    // MARK: - Permission state

    func testAuthorizedMapsToGrantedAccess() {
        let state = ContactsManager.permissionState(for: .authorized)
        XCTAssertEqual(state, .granted)
        XCTAssertTrue(state.allowsAccess)
        XCTAssertFalse(state.isFixableInSettings)
    }

    func testDeniedIsFixableInSettings() {
        let state = ContactsManager.permissionState(for: .denied)
        XCTAssertEqual(state, .denied)
        XCTAssertFalse(state.allowsAccess)
        XCTAssertTrue(state.isFixableInSettings)
    }

    func testRestrictedCannotBeFixedByTheUser() {
        // Screen Time or an MDM profile: pointing at Settings would be a dead end.
        let state = ContactsManager.permissionState(for: .restricted)
        XCTAssertEqual(state, .restricted)
        XCTAssertFalse(state.allowsAccess)
        XCTAssertFalse(state.isFixableInSettings)
    }

    func testNotDeterminedIsNeitherAccessNorASettingsProblem() {
        let state = ContactsManager.permissionState(for: .notDetermined)
        XCTAssertEqual(state, .notDetermined)
        XCTAssertFalse(state.allowsAccess)
        XCTAssertFalse(state.isFixableInSettings)
    }

    #if os(iOS)
    @available(iOS 18.0, *)
    func testLimitedAllowsAccessButStillPromptsForMore() {
        // Limited access works, so the app proceeds — but only over the contacts the
        // user picked, which is why it stays "fixable" and the UI keeps nagging.
        let state = ContactsManager.permissionState(for: .limited)
        XCTAssertEqual(state, .limited)
        XCTAssertTrue(state.allowsAccess)
        XCTAssertTrue(state.isFixableInSettings)
    }
    #endif

    // MARK: - Group presentation

    func testGroupSummarisesASingleReasonVerbatim() {
        let contacts = [makeContact(given: "三", family: "张"), makeContact(given: "三", family: "张")]
        let group = DuplicateGroup(
            id: "g",
            reasons: [DuplicateReason(id: "name:张三", description: "相同姓名 张三", contactIDs: [])],
            contacts: contacts
        )

        XCTAssertEqual(group.reasonSummary, "相同姓名 张三")
        XCTAssertEqual(group.detail, "2 个联系人 · 1 条依据")
    }

    func testGroupSummarisesMultipleReasonsWithACount() {
        let group = DuplicateGroup(
            id: "g",
            reasons: [
                DuplicateReason(id: "name:张三", description: "相同姓名 张三", contactIDs: []),
                DuplicateReason(id: "phone:1", description: "相同电话 5550000001", contactIDs: [])
            ],
            contacts: [makeContact(given: "三", family: "张"), makeContact(given: "三", family: "张")]
        )

        XCTAssertEqual(group.reasonSummary, "相同姓名 张三等 2 条依据")
    }

    func testGroupWithoutReasonsStillDescribesItself() {
        let group = DuplicateGroup(id: "g", reasons: [], contacts: [])
        XCTAssertEqual(group.reasonSummary, "疑似重复")
        XCTAssertEqual(group.displayName, "未命名联系人")
    }

    func testReasonNamesTheContactsItMatched() {
        let first = makeContact(given: "三", family: "张")
        let second = makeContact(given: "四", family: "李")
        let reason = DuplicateReason(
            id: "phone:1",
            description: "相同电话 5550000001",
            contactIDs: [first.identifier, second.identifier]
        )

        XCTAssertEqual(reason.matchingContactNames(in: [first, second]), "张三、李四")
    }

    func testReasonCollapsesRepeatedNamesWithACount() {
        let first = makeContact(given: "三", family: "张")
        let second = makeContact(given: "三", family: "张")
        let reason = DuplicateReason(
            id: "phone:1",
            description: "相同电话 5550000001",
            contactIDs: [first.identifier, second.identifier]
        )

        XCTAssertEqual(reason.matchingContactNames(in: [first, second]), "张三（2 个）")
    }
}
