import Contacts
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContactsBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw ContactsBackupError.unreadableFile
        }
        guard data.count <= ContactsBackupArchive.maximumFileSize else {
            throw ContactsBackupError.fileTooLarge
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ContactsBackupArchive: Codable {
    static let currentVersion = 1
    static let maximumFileSize = 100 * 1_024 * 1_024
    static let maximumContactCount = 100_000

    let formatVersion: Int
    let exportedAt: Date
    let contacts: [BackupContact]

    init(contacts: [CNContact], exportedAt: Date = Date()) {
        formatVersion = Self.currentVersion
        self.exportedAt = exportedAt
        self.contacts = contacts.map(BackupContact.init)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> ContactsBackupArchive {
        guard data.count <= maximumFileSize else {
            throw ContactsBackupError.fileTooLarge
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let archive = try decoder.decode(ContactsBackupArchive.self, from: data)
            guard archive.formatVersion == currentVersion else {
                throw ContactsBackupError.unsupportedVersion(archive.formatVersion)
            }
            guard archive.contacts.count <= maximumContactCount else {
                throw ContactsBackupError.tooManyContacts
            }
            return archive
        } catch let error as ContactsBackupError {
            throw error
        } catch {
            throw ContactsBackupError.invalidFile
        }
    }
}

struct BackupContact: Codable {
    let contactType: Int
    let namePrefix: String
    let givenName: String
    let middleName: String
    let familyName: String
    let previousFamilyName: String
    let nameSuffix: String
    let nickname: String
    let phoneticGivenName: String
    let phoneticMiddleName: String
    let phoneticFamilyName: String
    let organizationName: String
    let departmentName: String
    let jobTitle: String
    let phoneNumbers: [BackupLabeledString]
    let emailAddresses: [BackupLabeledString]
    let postalAddresses: [BackupPostalAddress]
    let urlAddresses: [BackupLabeledString]
    let birthday: BackupDateComponents?
    let nonGregorianBirthday: BackupDateComponents?
    let dates: [BackupLabeledDate]
    let contactRelations: [BackupLabeledString]
    let socialProfiles: [BackupSocialProfile]
    let instantMessageAddresses: [BackupInstantMessageAddress]
    let imageData: Data?

    init(contact: CNContact) {
        contactType = contact.contactType.rawValue
        namePrefix = contact.namePrefix
        givenName = contact.givenName
        middleName = contact.middleName
        familyName = contact.familyName
        previousFamilyName = contact.previousFamilyName
        nameSuffix = contact.nameSuffix
        nickname = contact.nickname
        phoneticGivenName = contact.phoneticGivenName
        phoneticMiddleName = contact.phoneticMiddleName
        phoneticFamilyName = contact.phoneticFamilyName
        organizationName = contact.organizationName
        departmentName = contact.departmentName
        jobTitle = contact.jobTitle
        phoneNumbers = contact.phoneNumbers.map {
            BackupLabeledString(label: $0.label, value: $0.value.stringValue)
        }
        emailAddresses = contact.emailAddresses.map {
            BackupLabeledString(label: $0.label, value: String($0.value))
        }
        postalAddresses = contact.postalAddresses.map(BackupPostalAddress.init)
        urlAddresses = contact.urlAddresses.map {
            BackupLabeledString(label: $0.label, value: String($0.value))
        }
        birthday = contact.birthday.map(BackupDateComponents.init)
        nonGregorianBirthday = contact.nonGregorianBirthday.map(BackupDateComponents.init)
        dates = contact.dates.map {
            BackupLabeledDate(label: $0.label, value: $0.value as DateComponents)
        }
        contactRelations = contact.contactRelations.map {
            BackupLabeledString(label: $0.label, value: $0.value.name)
        }
        socialProfiles = contact.socialProfiles.map(BackupSocialProfile.init)
        instantMessageAddresses = contact.instantMessageAddresses.map(BackupInstantMessageAddress.init)
        imageData = contact.imageData
    }

    var duplicateSignature: String {
        let scalarValues = [
            String(contactType), namePrefix, givenName, middleName, familyName,
            previousFamilyName, nameSuffix, nickname, phoneticGivenName,
            phoneticMiddleName, phoneticFamilyName, organizationName,
            departmentName, jobTitle
        ].map(Self.normalizeText)

        let phones = phoneNumbers.map {
            "\(Self.normalizeLabel($0.label)):\($0.value.filter(\.isNumber))"
        }.sorted()
        let emails = emailAddresses.map {
            "\(Self.normalizeLabel($0.label)):\(Self.normalizeText($0.value))"
        }.sorted()
        let addresses = postalAddresses.map(\.signature).sorted()
        let urls = urlAddresses.map {
            "\(Self.normalizeLabel($0.label)):\(Self.normalizeText($0.value))"
        }.sorted()
        let birthdayValue = birthday?.signature ?? ""
        let nonGregorianBirthdayValue = nonGregorianBirthday?.signature ?? ""
        let dateValues = dates.map(\.signature).sorted()
        let relationValues = contactRelations.map {
            "\(Self.normalizeLabel($0.label)):\(Self.normalizeText($0.value))"
        }.sorted()
        let socialValues = socialProfiles.map(\.signature).sorted()
        let instantMessageValues = instantMessageAddresses.map(\.signature).sorted()

        return [
            scalarValues.joined(separator: "|"),
            phones.joined(separator: "|"),
            emails.joined(separator: "|"),
            addresses.joined(separator: "|"),
            urls.joined(separator: "|"),
            birthdayValue,
            nonGregorianBirthdayValue,
            dateValues.joined(separator: "|"),
            relationValues.joined(separator: "|"),
            socialValues.joined(separator: "|"),
            instantMessageValues.joined(separator: "|")
        ].joined(separator: "\n")
    }

    func makeMutableContact() -> CNMutableContact {
        let contact = CNMutableContact()
        contact.contactType = CNContactType(rawValue: contactType) ?? .person
        contact.namePrefix = namePrefix
        contact.givenName = givenName
        contact.middleName = middleName
        contact.familyName = familyName
        contact.previousFamilyName = previousFamilyName
        contact.nameSuffix = nameSuffix
        contact.nickname = nickname
        contact.phoneticGivenName = phoneticGivenName
        contact.phoneticMiddleName = phoneticMiddleName
        contact.phoneticFamilyName = phoneticFamilyName
        contact.organizationName = organizationName
        contact.departmentName = departmentName
        contact.jobTitle = jobTitle
        contact.phoneNumbers = phoneNumbers.map {
            CNLabeledValue(label: $0.label, value: CNPhoneNumber(stringValue: $0.value))
        }
        contact.emailAddresses = emailAddresses.map {
            CNLabeledValue(label: $0.label, value: $0.value as NSString)
        }
        contact.postalAddresses = postalAddresses.map(\.labeledValue)
        contact.urlAddresses = urlAddresses.map {
            CNLabeledValue(label: $0.label, value: $0.value as NSString)
        }
        contact.birthday = birthday?.dateComponents
        contact.nonGregorianBirthday = nonGregorianBirthday?.dateComponents
        contact.dates = dates.map(\.labeledValue)
        contact.contactRelations = contactRelations.map {
            CNLabeledValue(label: $0.label, value: CNContactRelation(name: $0.value))
        }
        contact.socialProfiles = socialProfiles.map(\.labeledValue)
        contact.instantMessageAddresses = instantMessageAddresses.map(\.labeledValue)
        contact.imageData = imageData
        return contact
    }

    private static func normalizeText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizeLabel(_ value: String?) -> String {
        normalizeText(value ?? "")
    }
}

struct BackupLabeledString: Codable {
    let label: String?
    let value: String
}

struct BackupLabeledDate: Codable {
    let label: String?
    let value: BackupDateComponents

    init(label: String?, value: DateComponents) {
        self.label = label
        self.value = BackupDateComponents(value: value)
    }

    var labeledValue: CNLabeledValue<NSDateComponents> {
        CNLabeledValue(label: label, value: value.dateComponents as NSDateComponents)
    }

    var signature: String {
        "\((label ?? "").lowercased()):\(value.signature)"
    }
}

struct BackupSocialProfile: Codable {
    let label: String?
    let urlString: String
    let username: String
    let userIdentifier: String
    let service: String

    init(value: CNLabeledValue<CNSocialProfile>) {
        label = value.label
        urlString = value.value.urlString
        username = value.value.username
        userIdentifier = value.value.userIdentifier
        service = value.value.service
    }

    var labeledValue: CNLabeledValue<CNSocialProfile> {
        CNLabeledValue(
            label: label,
            value: CNSocialProfile(
                urlString: urlString,
                username: username,
                userIdentifier: userIdentifier,
                service: service
            )
        )
    }

    var signature: String {
        [label ?? "", urlString, username, userIdentifier, service]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }
}

struct BackupInstantMessageAddress: Codable {
    let label: String?
    let username: String
    let service: String

    init(value: CNLabeledValue<CNInstantMessageAddress>) {
        label = value.label
        username = value.value.username
        service = value.value.service
    }

    var labeledValue: CNLabeledValue<CNInstantMessageAddress> {
        CNLabeledValue(
            label: label,
            value: CNInstantMessageAddress(username: username, service: service)
        )
    }

    var signature: String {
        [label ?? "", username, service]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }
}

struct BackupPostalAddress: Codable {
    let label: String?
    let street: String
    let subLocality: String
    let city: String
    let subAdministrativeArea: String
    let state: String
    let postalCode: String
    let country: String
    let isoCountryCode: String

    init(value: CNLabeledValue<CNPostalAddress>) {
        label = value.label
        street = value.value.street
        subLocality = value.value.subLocality
        city = value.value.city
        subAdministrativeArea = value.value.subAdministrativeArea
        state = value.value.state
        postalCode = value.value.postalCode
        country = value.value.country
        isoCountryCode = value.value.isoCountryCode
    }

    var labeledValue: CNLabeledValue<CNPostalAddress> {
        let address = CNMutablePostalAddress()
        address.street = street
        address.subLocality = subLocality
        address.city = city
        address.subAdministrativeArea = subAdministrativeArea
        address.state = state
        address.postalCode = postalCode
        address.country = country
        address.isoCountryCode = isoCountryCode
        return CNLabeledValue(label: label, value: address.copy() as! CNPostalAddress)
    }

    var signature: String {
        [label ?? "", street, subLocality, city, subAdministrativeArea, state, postalCode, country, isoCountryCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }
}

struct BackupDateComponents: Codable {
    let era: Int?
    let year: Int?
    let month: Int?
    let day: Int?
    let isLeapMonth: Bool?

    init(value: DateComponents) {
        era = value.era
        year = value.year
        month = value.month
        day = value.day
        isLeapMonth = value.isLeapMonth
    }

    var dateComponents: DateComponents {
        var value = DateComponents()
        value.era = era
        value.year = year
        value.month = month
        value.day = day
        value.isLeapMonth = isLeapMonth
        return value
    }

    var signature: String {
        "\(era ?? -1)|\(year ?? -1)|\(month ?? -1)|\(day ?? -1)|\(isLeapMonth == true)"
    }
}

struct ContactImportPreview {
    let exportedAt: Date
    let contactCount: Int
    let contactsToAdd: Int
}

struct ContactImportResult {
    let addedCount: Int
    let skippedCount: Int
    let restoredImageCount: Int
}

enum ContactsBackupError: LocalizedError {
    case accessDenied
    case unreadableFile
    case fileTooLarge
    case invalidFile
    case unsupportedVersion(Int)
    case tooManyContacts

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "请先允许访问通讯录。"
        case .unreadableFile:
            return "无法读取所选文件。"
        case .fileTooLarge:
            return "备份文件超过 100 MB，无法导入。"
        case .invalidFile:
            return "这不是有效的 ContactsDeduper 备份文件。"
        case .unsupportedVersion(let version):
            return "暂不支持版本 \(version) 的备份文件。"
        case .tooManyContacts:
            return "备份中的联系人数量异常，已停止导入。"
        }
    }
}
