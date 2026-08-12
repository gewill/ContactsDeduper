import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    private let supportedLocales = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de"]

    func testEverySupportedLocaleContainsEveryLocalizedString() throws {
        let resources = repositoryRoot.appendingPathComponent("ContactsDeduper")
        let tables = try supportedLocales.reduce(into: [String: [String: String]]()) { result, locale in
            let file = resources
                .appendingPathComponent("\(locale).lproj")
                .appendingPathComponent("Localizable.strings")
            result[locale] = try loadStrings(at: file)
        }

        let expectedKeys = Set(try XCTUnwrap(tables["zh-Hans"]).keys)
        XCTAssertFalse(expectedKeys.isEmpty)

        for locale in supportedLocales {
            let strings = try XCTUnwrap(tables[locale])
            XCTAssertEqual(Set(strings.keys), expectedKeys, "\(locale) has missing or extra localization keys")
            XCTAssertTrue(strings.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

            for key in expectedKeys {
                XCTAssertEqual(
                    placeholderArguments(in: try XCTUnwrap(strings[key])),
                    placeholderArguments(in: key),
                    "\(locale) changed placeholders for \(key)"
                )
            }
        }
    }

    func testContactsPermissionDescriptionExistsForEverySupportedLocale() throws {
        let resources = repositoryRoot.appendingPathComponent("ContactsDeduper")

        for locale in supportedLocales {
            let file = resources
                .appendingPathComponent("\(locale).lproj")
                .appendingPathComponent("InfoPlist.strings")
            let strings = try loadStrings(at: file)
            let description = try XCTUnwrap(strings["NSContactsUsageDescription"])
            XCTAssertFalse(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testAppStoreMetadataCoversEverySupportedLocaleAndFitsLimits() throws {
        let file = repositoryRoot.appendingPathComponent("AppStoreMetadata.json")
        let data = try Data(contentsOf: file)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let localizations = try XCTUnwrap(root["localizations"] as? [String: [String: String]])
        let expectedLocales = Set(["en-US", "zh-Hans", "zh-Hant", "ja", "ko", "es-ES", "fr-FR", "de-DE"])
        XCTAssertEqual(Set(localizations.keys), expectedLocales)

        for (locale, metadata) in localizations {
            XCTAssertLessThanOrEqual(try XCTUnwrap(metadata["name"]).count, 30, locale)
            XCTAssertLessThanOrEqual(try XCTUnwrap(metadata["subtitle"]).count, 30, locale)
            XCTAssertLessThanOrEqual(try XCTUnwrap(metadata["keywords"]).count, 100, locale)
            XCTAssertFalse(try XCTUnwrap(metadata["description"]).isEmpty, locale)

            let privacyURL = try XCTUnwrap(URL(string: try XCTUnwrap(metadata["privacyPolicyURL"])))
            let privacyFilename = privacyURL.pathComponents.dropFirst(5).joined(separator: ".")
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: repositoryRoot.appendingPathComponent(privacyFilename).path
                ),
                "Missing privacy policy for \(locale)"
            )
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadStrings(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(propertyList as? [String: String], "Invalid strings file: \(url.path)")
    }

    private func placeholderArguments(in value: String) -> [Int: String] {
        let pattern = #"%(?:(\d+)\$)?(@|lld|\.1f)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        var nextImplicitArgument = 1
        return regex.matches(in: value, range: range).reduce(into: [:]) { result, match in
            let argument: Int
            if let positionRange = Range(match.range(at: 1), in: value) {
                argument = Int(value[positionRange])!
            } else {
                argument = nextImplicitArgument
                nextImplicitArgument += 1
            }
            let typeRange = Range(match.range(at: 2), in: value)!
            result[argument] = String(value[typeRange])
        }
    }
}
