import Contacts
import XCTest

/// Backup is the safety net users are told to create before a destructive merge, so
/// these cover the round trip field by field and every way a file is rejected.
final class ContactsBackupTests: XCTestCase {

    // MARK: - Fixtures

    /// A contact with every field the backup schema claims to support populated, so a
    /// field dropped from the schema shows up as a failure here.
    private func makeFullyPopulatedContact() -> CNContact {
        let contact = CNMutableContact()
        contact.contactType = .person
        contact.namePrefix = "Dr."
        contact.givenName = "三"
        contact.middleName = "小"
        contact.familyName = "张"
        contact.previousFamilyName = "李"
        contact.nameSuffix = "Jr."
        contact.nickname = "阿三"
        contact.phoneticGivenName = "San"
        contact.phoneticMiddleName = "Xiao"
        contact.phoneticFamilyName = "Zhang"
        contact.organizationName = "顺丰速运"
        contact.departmentName = "运营部"
        contact.jobTitle = "经理"

        contact.phoneNumbers = [
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "5550000001")),
            CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "5550000002"))
        ]
        contact.emailAddresses = [
            CNLabeledValue(label: CNLabelHome, value: "home@example.com" as NSString),
            CNLabeledValue(label: CNLabelWork, value: "work@example.com" as NSString)
        ]

        let address = CNMutablePostalAddress()
        address.street = "科技路 1 号"
        address.subLocality = "高新区"
        address.city = "深圳"
        address.subAdministrativeArea = "南山"
        address.state = "广东"
        address.postalCode = "518000"
        address.country = "中国"
        address.isoCountryCode = "CN"
        contact.postalAddresses = [
            CNLabeledValue(label: CNLabelHome, value: address.copy() as! CNPostalAddress)
        ]

        contact.urlAddresses = [
            CNLabeledValue(label: CNLabelURLAddressHomePage, value: "https://example.com" as NSString)
        ]

        var birthday = DateComponents()
        birthday.year = 1990
        birthday.month = 5
        birthday.day = 20
        contact.birthday = birthday

        var lunar = DateComponents()
        lunar.calendar = Calendar(identifier: .chinese)
        lunar.year = 1990
        lunar.month = 4
        lunar.day = 26
        contact.nonGregorianBirthday = lunar

        var anniversary = DateComponents()
        anniversary.year = 2015
        anniversary.month = 10
        anniversary.day = 1
        contact.dates = [
            CNLabeledValue(label: CNLabelDateAnniversary, value: anniversary as NSDateComponents)
        ]

        contact.contactRelations = [
            CNLabeledValue(label: CNLabelContactRelationFriend, value: CNContactRelation(name: "王五"))
        ]
        contact.socialProfiles = [
            CNLabeledValue(
                label: CNSocialProfileServiceTwitter,
                value: CNSocialProfile(
                    urlString: "https://twitter.com/zhangsan",
                    username: "zhangsan",
                    userIdentifier: "42",
                    service: CNSocialProfileServiceTwitter
                )
            )
        ]
        contact.instantMessageAddresses = [
            CNLabeledValue(
                label: CNInstantMessageServiceSkype,
                value: CNInstantMessageAddress(username: "zhangsan", service: CNInstantMessageServiceSkype)
            )
        ]
        contact.imageData = Data([0x89, 0x50, 0x4E, 0x47])

        return contact.copy() as! CNContact
    }

    private func encodedArchive(with contacts: [CNContact]) throws -> Data {
        try ContactsBackupArchive(contacts: contacts).encoded()
    }

    // MARK: - Round trip

    func testEverySupportedFieldSurvivesEncodeDecodeAndReconstruction() throws {
        let original = makeFullyPopulatedContact()
        let data = try encodedArchive(with: [original])
        let restored = try ContactsBackupArchive.decode(from: data).contacts.first?.makeMutableContact()

        let rebuilt = try XCTUnwrap(restored)
        XCTAssertEqual(rebuilt.contactType, original.contactType)
        XCTAssertEqual(rebuilt.namePrefix, original.namePrefix)
        XCTAssertEqual(rebuilt.givenName, original.givenName)
        XCTAssertEqual(rebuilt.middleName, original.middleName)
        XCTAssertEqual(rebuilt.familyName, original.familyName)
        XCTAssertEqual(rebuilt.previousFamilyName, original.previousFamilyName)
        XCTAssertEqual(rebuilt.nameSuffix, original.nameSuffix)
        XCTAssertEqual(rebuilt.nickname, original.nickname)
        XCTAssertEqual(rebuilt.phoneticGivenName, original.phoneticGivenName)
        XCTAssertEqual(rebuilt.phoneticMiddleName, original.phoneticMiddleName)
        XCTAssertEqual(rebuilt.phoneticFamilyName, original.phoneticFamilyName)
        XCTAssertEqual(rebuilt.organizationName, original.organizationName)
        XCTAssertEqual(rebuilt.departmentName, original.departmentName)
        XCTAssertEqual(rebuilt.jobTitle, original.jobTitle)

        XCTAssertEqual(
            rebuilt.phoneNumbers.map { [$0.label ?? "", $0.value.stringValue] },
            original.phoneNumbers.map { [$0.label ?? "", $0.value.stringValue] }
        )
        XCTAssertEqual(
            rebuilt.emailAddresses.map { [$0.label ?? "", String($0.value)] },
            original.emailAddresses.map { [$0.label ?? "", String($0.value)] }
        )
        XCTAssertEqual(
            rebuilt.urlAddresses.map { [$0.label ?? "", String($0.value)] },
            original.urlAddresses.map { [$0.label ?? "", String($0.value)] }
        )

        let restoredAddress = try XCTUnwrap(rebuilt.postalAddresses.first?.value)
        let originalAddress = try XCTUnwrap(original.postalAddresses.first?.value)
        XCTAssertEqual(restoredAddress.street, originalAddress.street)
        XCTAssertEqual(restoredAddress.subLocality, originalAddress.subLocality)
        XCTAssertEqual(restoredAddress.city, originalAddress.city)
        XCTAssertEqual(restoredAddress.subAdministrativeArea, originalAddress.subAdministrativeArea)
        XCTAssertEqual(restoredAddress.state, originalAddress.state)
        XCTAssertEqual(restoredAddress.postalCode, originalAddress.postalCode)
        XCTAssertEqual(restoredAddress.country, originalAddress.country)
        XCTAssertEqual(restoredAddress.isoCountryCode, originalAddress.isoCountryCode)

        XCTAssertEqual(rebuilt.birthday?.year, original.birthday?.year)
        XCTAssertEqual(rebuilt.birthday?.month, original.birthday?.month)
        XCTAssertEqual(rebuilt.birthday?.day, original.birthday?.day)
        XCTAssertEqual(rebuilt.nonGregorianBirthday?.year, original.nonGregorianBirthday?.year)
        XCTAssertEqual(rebuilt.nonGregorianBirthday?.month, original.nonGregorianBirthday?.month)
        XCTAssertEqual(rebuilt.nonGregorianBirthday?.day, original.nonGregorianBirthday?.day)

        XCTAssertEqual(
            (rebuilt.dates.first?.value as DateComponents?)?.year,
            (original.dates.first?.value as DateComponents?)?.year
        )
        XCTAssertEqual(rebuilt.contactRelations.first?.value.name, original.contactRelations.first?.value.name)

        let restoredProfile = try XCTUnwrap(rebuilt.socialProfiles.first?.value)
        let originalProfile = try XCTUnwrap(original.socialProfiles.first?.value)
        XCTAssertEqual(restoredProfile.urlString, originalProfile.urlString)
        XCTAssertEqual(restoredProfile.username, originalProfile.username)
        XCTAssertEqual(restoredProfile.userIdentifier, originalProfile.userIdentifier)
        XCTAssertEqual(restoredProfile.service, originalProfile.service)

        let restoredIM = try XCTUnwrap(rebuilt.instantMessageAddresses.first?.value)
        let originalIM = try XCTUnwrap(original.instantMessageAddresses.first?.value)
        XCTAssertEqual(restoredIM.username, originalIM.username)
        XCTAssertEqual(restoredIM.service, originalIM.service)

        XCTAssertEqual(rebuilt.imageData, original.imageData)
    }

    func testArchiveKeepsItsVersionAndExportDate() throws {
        let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let archive = ContactsBackupArchive(contacts: [makeFullyPopulatedContact()], exportedAt: exportedAt)
        let decoded = try ContactsBackupArchive.decode(from: try archive.encoded())

        XCTAssertEqual(decoded.formatVersion, ContactsBackupArchive.currentVersion)
        XCTAssertEqual(decoded.exportedAt.timeIntervalSince1970, exportedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.contacts.count, 1)
    }

    func testEmptyContactRoundTripsWithoutInventingValues() throws {
        let data = try encodedArchive(with: [CNMutableContact().copy() as! CNContact])
        let rebuilt = try XCTUnwrap(ContactsBackupArchive.decode(from: data).contacts.first?.makeMutableContact())

        XCTAssertEqual(rebuilt.givenName, "")
        XCTAssertTrue(rebuilt.phoneNumbers.isEmpty)
        XCTAssertNil(rebuilt.birthday)
        XCTAssertNil(rebuilt.imageData)
    }

    // MARK: - Rejecting bad input

    func testMalformedJSONIsRejected() {
        let data = Data("not a backup".utf8)
        XCTAssertThrowsError(try ContactsBackupArchive.decode(from: data)) { error in
            XCTAssertEqual(error as? ContactsBackupError, .invalidFile)
        }
    }

    func testWellFormedJSONOfTheWrongShapeIsRejected() {
        let data = Data(#"{"hello":"world"}"#.utf8)
        XCTAssertThrowsError(try ContactsBackupArchive.decode(from: data)) { error in
            XCTAssertEqual(error as? ContactsBackupError, .invalidFile)
        }
    }

    func testFutureFormatVersionIsRejected() throws {
        let data = Data(#"{"formatVersion":99,"exportedAt":"2026-01-01T00:00:00Z","contacts":[]}"#.utf8)
        XCTAssertThrowsError(try ContactsBackupArchive.decode(from: data)) { error in
            XCTAssertEqual(error as? ContactsBackupError, .unsupportedVersion(99))
        }
    }

    func testOversizedFileIsRejectedBeforeParsing() {
        let data = Data(count: ContactsBackupArchive.maximumFileSize + 1)
        XCTAssertThrowsError(try ContactsBackupArchive.decode(from: data)) { error in
            XCTAssertEqual(error as? ContactsBackupError, .fileTooLarge)
        }
    }

    // MARK: - Import de-duplication signature

    func testIdenticalContactsShareASignature() {
        let first = BackupContact(contact: makeFullyPopulatedContact())
        let second = BackupContact(contact: makeFullyPopulatedContact())
        XCTAssertEqual(first.duplicateSignature, second.duplicateSignature)
    }

    func testSignatureIgnoresPhoneOrdering() {
        let ascending = CNMutableContact()
        ascending.givenName = "三"
        ascending.phoneNumbers = [
            CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "5550000001")),
            CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "5550000002"))
        ]
        let descending = CNMutableContact()
        descending.givenName = "三"
        descending.phoneNumbers = Array(ascending.phoneNumbers.reversed())

        XCTAssertEqual(
            BackupContact(contact: ascending.copy() as! CNContact).duplicateSignature,
            BackupContact(contact: descending.copy() as! CNContact).duplicateSignature
        )
    }

    func testSignatureSeparatesContactsThatDifferInOneField() {
        let base = CNMutableContact()
        base.givenName = "三"
        base.familyName = "张"

        let other = base.mutableCopy() as! CNMutableContact
        other.jobTitle = "经理"

        XCTAssertNotEqual(
            BackupContact(contact: base.copy() as! CNContact).duplicateSignature,
            BackupContact(contact: other.copy() as! CNContact).duplicateSignature
        )
    }

    func testSignatureIgnoresCaseAndSurroundingWhitespace() {
        let plain = CNMutableContact()
        plain.givenName = "Ann"
        plain.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "ANN@example.com" as NSString)]

        let padded = CNMutableContact()
        padded.givenName = "  ann  "
        padded.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "ann@EXAMPLE.com " as NSString)]

        XCTAssertEqual(
            BackupContact(contact: plain.copy() as! CNContact).duplicateSignature,
            BackupContact(contact: padded.copy() as! CNContact).duplicateSignature
        )
    }

    func testSignatureIsSensitiveToImageOnlyDifferences() {
        // The image is deliberately outside the signature: import restores a missing
        // avatar onto an otherwise identical contact rather than adding a second copy.
        let withoutImage = CNMutableContact()
        withoutImage.givenName = "三"

        let withImage = withoutImage.mutableCopy() as! CNMutableContact
        withImage.imageData = Data([0x01, 0x02])

        XCTAssertEqual(
            BackupContact(contact: withoutImage.copy() as! CNContact).duplicateSignature,
            BackupContact(contact: withImage.copy() as! CNContact).duplicateSignature
        )
    }
}

extension ContactsBackupError: @retroactive Equatable {
    public static func == (lhs: ContactsBackupError, rhs: ContactsBackupError) -> Bool {
        switch (lhs, rhs) {
        case (.accessDenied, .accessDenied),
             (.unreadableFile, .unreadableFile),
             (.fileTooLarge, .fileTooLarge),
             (.invalidFile, .invalidFile),
             (.tooManyContacts, .tooManyContacts):
            return true
        case let (.unsupportedVersion(lhsVersion), .unsupportedVersion(rhsVersion)):
            return lhsVersion == rhsVersion
        default:
            return false
        }
    }
}
