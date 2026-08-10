import Contacts
import XCTest

/// Exercises the duplicate matcher directly. `findDuplicates(in:rule:)` only reads
/// the contacts it is handed, so these tests never touch `CNContactStore` and never
/// need Contacts permission.
@MainActor
final class DuplicateMatchingTests: XCTestCase {
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
        organization: String = ""
    ) -> CNContact {
        let contact = CNMutableContact()
        contact.givenName = given
        contact.familyName = family
        contact.organizationName = organization
        contact.phoneNumbers = phones.map {
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
        }
        contact.emailAddresses = emails.map {
            CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
        }
        return contact.copy() as! CNContact
    }

    /// Renders the grouping as a sorted shape like `"AB CD"` so expectations stay
    /// readable and independent of contact ordering.
    private func shape(
        _ groups: [DuplicateGroup],
        _ labels: [String: String]
    ) -> String {
        groups
            .map { group in
                group.contacts.compactMap { labels[$0.identifier] }.sorted().joined()
            }
            .sorted()
            .joined(separator: " ")
    }

    // MARK: - displayName

    func testDisplayNameFormatsLocallyBuiltContact() {
        // Guards the areKeysAvailable check in CNContact.displayName: it must not
        // swallow names on contacts that were never fetched from the store.
        XCTAssertEqual(makeContact(given: "三", family: "张").displayName, "张三")
    }

    func testDisplayNameFallsBackToOrganization() {
        XCTAssertEqual(makeContact(organization: "顺丰速运").displayName, "顺丰速运")
    }

    // MARK: - Match rules

    /// A/B share name+phone, C shares only the phone, D shares only the name,
    /// E/F share only an email.
    private func makeMixedFixture() -> (contacts: [CNContact], labels: [String: String]) {
        let a = makeContact(given: "五", family: "王", phones: ["13800138000"], emails: ["w@x.com"])
        let b = makeContact(given: "五", family: "王", phones: ["138-0013-8000"])
        let c = makeContact(given: "六", family: "赵", phones: ["13800138000"])
        let d = makeContact(given: "五", family: "王", phones: ["18900000000"])
        let e = makeContact(given: "七", family: "钱", emails: ["shared@x.com"])
        let f = makeContact(given: "八", family: "孙", emails: ["shared@x.com"])

        return (
            [a, b, c, d, e, f],
            [
                a.identifier: "A", b.identifier: "B", c.identifier: "C",
                d.identifier: "D", e.identifier: "E", f.identifier: "F"
            ]
        )
    }

    func testDualRuleNeedsTwoKindsOfEvidence() {
        let fixture = makeMixedFixture()
        XCTAssertEqual(
            shape(manager.findDuplicates(in: fixture.contacts, rule: .dual), fixture.labels),
            "AB"
        )
    }

    func testAnyRuleChainsThroughASingleSharedField() {
        let fixture = makeMixedFixture()
        XCTAssertEqual(
            shape(manager.findDuplicates(in: fixture.contacts, rule: .any), fixture.labels),
            "ABCD EF"
        )
    }

    func testNameOnlyRuleIgnoresPhoneAndEmail() {
        let fixture = makeMixedFixture()
        XCTAssertEqual(
            shape(manager.findDuplicates(in: fixture.contacts, rule: .nameOnly), fixture.labels),
            "ABD"
        )
    }

    func testPhoneOnlyRuleIgnoresNameAndEmail() {
        let fixture = makeMixedFixture()
        XCTAssertEqual(
            shape(manager.findDuplicates(in: fixture.contacts, rule: .phoneOnly), fixture.labels),
            "ABC"
        )
    }

    // MARK: - Reason attribution

    func testGroupCitesEveryKindOfEvidenceItMatchedOn() {
        let fixture = makeMixedFixture()
        let reasons = manager
            .findDuplicates(in: fixture.contacts, rule: .dual)
            .flatMap(\.reasons)

        XCTAssertEqual(reasons.filter { $0.description.hasPrefix("相同姓名") }.count, 1)
        XCTAssertEqual(reasons.filter { $0.description.hasPrefix("相同电话") }.count, 1)
    }

    func testReasonOnlyListsMembersOfItsOwnGroup() {
        // C shares the phone bucket with A and B but never joins their group, so the
        // phone reason must not name it.
        let fixture = makeMixedFixture()
        let phoneReason = manager
            .findDuplicates(in: fixture.contacts, rule: .dual)
            .flatMap(\.reasons)
            .first { $0.description.hasPrefix("相同电话") }

        let named = phoneReason?.contactIDs
            .compactMap { fixture.labels[$0] }
            .sorted()
            .joined()
        XCTAssertEqual(named, "AB")
    }

    // MARK: - Company contacts

    func testCompanyOnlyContactsMatchOnOrganizationName() {
        // Company entries carry no person name, so before the organization fallback
        // they could only ever match on phone.
        let contacts = [
            makeContact(phones: ["95338"], organization: "顺丰速运"),
            makeContact(phones: ["95338"], organization: "顺丰速运")
        ]
        let groups = manager.findDuplicates(in: contacts, rule: .dual)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(
            groups.first?.reasons.first { $0.description.hasPrefix("相同公司") }?.description,
            "相同公司 顺丰速运"
        )
    }

    func testColleaguesSharingEmployerAndSwitchboardStaySeparate() {
        // The regression the organization fallback must never introduce: two named
        // people at one company sharing its switchboard are not the same person.
        let contacts = [
            makeContact(given: "三", family: "张", phones: ["95188"], organization: "阿里巴巴"),
            makeContact(given: "四", family: "李", phones: ["95188"], organization: "阿里巴巴")
        ]
        XCTAssertTrue(manager.findDuplicates(in: contacts, rule: .dual).isEmpty)
    }

    func testCompanyMatchesTheSameNameTypedIntoTheNameField() {
        let contacts = [
            makeContact(phones: ["95338"], organization: "顺丰速运"),
            makeContact(family: "顺丰速运", phones: ["95338"])
        ]
        XCTAssertEqual(manager.findDuplicates(in: contacts, rule: .dual).count, 1)
    }

    func testSameCompanyWithDifferentNumbersNeedsTheLooserRule() {
        let contacts = [
            makeContact(phones: ["13800000001"], organization: "顺丰速运"),
            makeContact(phones: ["13800000002"], organization: "顺丰速运")
        ]
        XCTAssertTrue(manager.findDuplicates(in: contacts, rule: .dual).isEmpty)
        XCTAssertEqual(manager.findDuplicates(in: contacts, rule: .nameOnly).count, 1)
    }

    // MARK: - Multi-valued phone and email fields

    func testMatchesOnASecondaryPhoneNotJustTheFirst() {
        let contacts = [
            makeContact(given: "三", family: "张", phones: ["5550000001", "5550000002"]),
            makeContact(given: "四", family: "李", phones: ["5550000009", "5550000002"])
        ]
        XCTAssertEqual(manager.findDuplicates(in: contacts, rule: .phoneOnly).count, 1)
    }

    func testMatchesOnASecondaryEmailNotJustTheFirst() {
        let contacts = [
            makeContact(given: "三", family: "张", emails: ["a@x.com", "shared@x.com"]),
            makeContact(given: "四", family: "李", emails: ["b@x.com", "shared@x.com"])
        ]
        XCTAssertEqual(manager.findDuplicates(in: contacts, rule: .any).count, 1)
    }

    func testDualRuleCombinesEvidenceFromDifferentFieldKinds() {
        // Different names, but a secondary phone and a secondary email both line up.
        let contacts = [
            makeContact(
                given: "三", family: "张",
                phones: ["5550000001", "5550000002"],
                emails: ["a@x.com", "shared@x.com"]
            ),
            makeContact(
                given: "四", family: "李",
                phones: ["5550000009", "5550000002"],
                emails: ["b@x.com", "shared@x.com"]
            )
        ]
        XCTAssertEqual(manager.findDuplicates(in: contacts, rule: .dual).count, 1)
    }

    func testTwoSharedPhonesAreStillOnlyOneKindOfEvidence() {
        // "两项" counts kinds of evidence, not matches: sharing two numbers is still
        // just "phone". Change this only if the rule itself is redefined.
        let contacts = [
            makeContact(given: "三", family: "张", phones: ["5550000001", "5550000002"]),
            makeContact(given: "四", family: "李", phones: ["5550000001", "5550000002"])
        ]
        XCTAssertTrue(manager.findDuplicates(in: contacts, rule: .dual).isEmpty)
        XCTAssertEqual(manager.findDuplicates(in: contacts, rule: .any).count, 1)
    }

    func testRepeatedNumberOnOneContactIsNotSelfEvidence() {
        let contacts = [makeContact(given: "三", family: "张", phones: ["5550000001", "5550000001"])]
        XCTAssertTrue(manager.findDuplicates(in: contacts, rule: .phoneOnly).isEmpty)
        XCTAssertTrue(manager.findDuplicates(in: contacts, rule: .any).isEmpty)
    }

    func testAContactWithTwoNumbersChainsTwoOthersIntoOneGroup() {
        let contacts = [
            makeContact(given: "甲", family: "王", phones: ["5550000001", "5550000002"]),
            makeContact(given: "乙", family: "王", phones: ["5550000001"]),
            makeContact(given: "丙", family: "王", phones: ["5550000002"])
        ]
        let groups = manager.findDuplicates(in: contacts, rule: .phoneOnly)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.contacts.count, 3)
    }

    func testEverySharedValueProducesItsOwnReason() {
        let contacts = [
            makeContact(given: "三", family: "张", phones: ["5550000001", "5550000002"]),
            makeContact(given: "三", family: "张", phones: ["5550000001", "5550000002"])
        ]
        let reasons = manager
            .findDuplicates(in: contacts, rule: .dual)
            .flatMap(\.reasons)
            .map(\.description)
            .sorted()

        XCTAssertEqual(reasons, ["相同姓名 张三", "相同电话 5550000001", "相同电话 5550000002"])
    }

    func testLabelsDoNotAffectMatching() {
        let home = CNMutableContact()
        home.givenName = "三"
        home.familyName = "张"
        home.phoneNumbers = [
            CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "5550000001"))
        ]
        let work = CNMutableContact()
        work.givenName = "四"
        work.familyName = "李"
        work.phoneNumbers = [
            CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "555-000-0001"))
        ]

        let contacts = [home.copy() as! CNContact, work.copy() as! CNContact]
        XCTAssertEqual(manager.findDuplicates(in: contacts, rule: .phoneOnly).count, 1)
    }

    // MARK: - Phone normalization

    func testNANPCountryCodeIsStripped() {
        XCTAssertEqual(
            manager.normalizePhone("+1 415 555 3695"),
            manager.normalizePhone("(415) 555-3695")
        )
    }

    func testKnownGapInternationalPrefixDefeatsPhoneMatching() {
        // Documents github.com/gewill/ContactsDeduper/issues/1. When phone
        // normalization learns country codes, delete this test rather than
        // relaxing it.
        let contacts = [
            makeContact(given: "九", family: "周", phones: ["13800138000"]),
            makeContact(given: "九", family: "周", phones: ["+8613800138000"])
        ]
        XCTAssertTrue(
            manager.findDuplicates(in: contacts, rule: .dual).isEmpty,
            "Country-code handling landed; update this test and close issue #1."
        )
    }
}
