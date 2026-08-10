import Contacts
import XCTest

/// Timing for the duplicate matcher. The loose rules union whole buckets and cost
/// roughly linear time; `.dual` tallies evidence per contact *pair*, so its cost
/// grows with the square of the largest bucket. These measure both shapes.
///
/// Fixtures are seeded, so a run is comparable to the previous one.
@MainActor
final class DuplicateMatchingPerformanceTests: XCTestCase {
    private var manager: ContactsManager!

    override func setUp() {
        super.setUp()
        manager = ContactsManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

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

    /// An address book shaped roughly like a real one: mostly unique people with one
    /// or two numbers, a slice of company-only entries, and a slice of near-duplicates
    /// that repeat an earlier record's name and number.
    private func makeAddressBook(count: Int, seed: UInt64 = 42) -> [CNContact] {
        var generator = SeededGenerator(seed: seed)
        let families = ["王", "李", "张", "刘", "陈", "杨", "黄", "赵", "周", "吴"]
        let companies = ["顺丰速运", "阿里巴巴", "京东物流", "美团", "字节跳动"]
        var contacts: [CNContact] = []
        contacts.reserveCapacity(count)

        for index in 0..<count {
            let roll = Int.random(in: 0..<100, using: &generator)

            if roll < 15 {
                // Company-only entry.
                let company = companies[index % companies.count]
                contacts.append(
                    makeContact(
                        phones: ["555\(String(format: "%07d", index))"],
                        organization: company
                    )
                )
                continue
            }

            if roll < 25, index > 0 {
                // Near-duplicate of an earlier person: same name, same first number.
                let source = index / 2
                contacts.append(
                    makeContact(
                        given: "名\(source)",
                        family: families[source % families.count],
                        phones: ["555\(String(format: "%07d", source))"]
                    )
                )
                continue
            }

            var phones = ["555\(String(format: "%07d", index))"]
            if roll > 70 {
                phones.append("666\(String(format: "%07d", index))")
            }
            contacts.append(
                makeContact(
                    given: "名\(index)",
                    family: families[index % families.count],
                    phones: phones,
                    emails: roll > 50 ? ["user\(index)@example.com"] : []
                )
            )
        }

        return contacts
    }

    /// Everyone on one switchboard number: a single bucket of `count` members, which
    /// is the worst case for the pairwise path.
    private func makeSharedNumberBook(count: Int) -> [CNContact] {
        (0..<count).map {
            makeContact(given: "名\($0)", family: "员工", phones: ["5551234567"])
        }
    }

    // MARK: - Realistic address book

    func testPerformanceDualRuleOnTwoThousandContacts() {
        let contacts = makeAddressBook(count: 2_000)
        measure {
            _ = manager.findDuplicates(in: contacts, rule: .dual)
        }
    }

    func testPerformanceAnyRuleOnTwoThousandContacts() {
        let contacts = makeAddressBook(count: 2_000)
        measure {
            _ = manager.findDuplicates(in: contacts, rule: .any)
        }
    }

    func testPerformanceDualRuleOnTenThousandContacts() {
        let contacts = makeAddressBook(count: 10_000)
        measure {
            _ = manager.findDuplicates(in: contacts, rule: .dual)
        }
    }

    // MARK: - Worst case: one huge bucket

    func testPerformanceDualRuleOnSharedNumberBucket() {
        // 800 contacts on one number is ~320k candidate pairs.
        let contacts = makeSharedNumberBook(count: 800)
        measure {
            _ = manager.findDuplicates(in: contacts, rule: .dual)
        }
    }

    func testPerformanceAnyRuleOnSharedNumberBucket() {
        // Same input on the bucket path, for contrast with the pairwise cost above.
        let contacts = makeSharedNumberBook(count: 800)
        measure {
            _ = manager.findDuplicates(in: contacts, rule: .any)
        }
    }

    // MARK: - displayName cost

    func testPerformanceSortingByDisplayName() {
        // The pattern fetchContacts(in:) uses: format every name once, then sort the
        // pairs. Calling displayName from the comparator instead runs
        // CNContactFormatter O(n log n) times and measured ~780ms on this fixture,
        // roughly ten times what the decorated sort costs.
        let contacts = makeAddressBook(count: 2_000)
        measure {
            _ = contacts
                .map { (name: $0.displayName, contact: $0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map(\.contact)
        }
    }

    // MARK: - Correctness at scale

    func testLargeAddressBookStillFindsItsPlantedDuplicates() {
        // Guards against a fast-but-wrong regression: the seeded book plants
        // name+number repeats, and the strict rule must still surface them.
        let contacts = makeAddressBook(count: 2_000)
        let groups = manager.findDuplicates(in: contacts, rule: .dual)

        XCTAssertFalse(groups.isEmpty)
        XCTAssertTrue(
            groups.allSatisfy { $0.contacts.count > 1 },
            "A duplicate group must always hold at least two contacts."
        )
        XCTAssertTrue(
            groups.allSatisfy { !$0.reasons.isEmpty },
            "Every group must be able to explain itself."
        )
    }

    func testSharedNumberAloneDoesNotMergeUnderTheStrictRule() {
        // The worst-case fixture must produce no merges: one shared number is one
        // kind of evidence, and every name differs.
        let contacts = makeSharedNumberBook(count: 800)
        XCTAssertTrue(manager.findDuplicates(in: contacts, rule: .dual).isEmpty)
        XCTAssertEqual(manager.findDuplicates(in: contacts, rule: .any).count, 1)
    }
}
