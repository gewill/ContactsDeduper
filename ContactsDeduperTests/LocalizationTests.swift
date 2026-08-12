import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    // Catalog keys are stable identifiers. Change localized copy without renaming its key.
    private let supportedLocales = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de"]

    func testEverySupportedLocaleContainsEveryLocalizedString() throws {
        let catalog = try localizationCatalog()
        XCTAssertEqual(try XCTUnwrap(catalog["sourceLanguage"] as? String), "en")
        let entries = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        XCTAssertFalse(entries.isEmpty)

        for (key, entry) in entries {
            XCTAssertNotNil(key.range(of: #"^[a-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)+$"#, options: .regularExpression))
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: [String: Any]])
            XCTAssertEqual(Set(localizations.keys), Set(supportedLocales), "\(key) has missing or extra locales")
            let source = try localizedValue(in: localizations, locale: "en")

            for locale in supportedLocales {
                let value = try localizedValue(in: localizations, locale: locale)
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertEqual(
                    try placeholderArguments(in: value),
                    try placeholderArguments(in: source),
                    "\(locale) changed placeholders for \(key)"
                )
                if try placeholderArguments(in: source).count > 1 {
                    XCTAssertTrue(
                        try placeholders(in: value).allSatisfy(\.isExplicit),
                        "\(locale) must number every placeholder in \(key)"
                    )
                }
            }
        }
    }

    func testSwiftSourceUsesEnglishAndGeneratedCatalogSymbols() throws {
        let sources = try FileManager.default.contentsOfDirectory(
            at: repositoryRoot.appendingPathComponent("ContactsDeduper"),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let source = try sources.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        XCTAssertTrue(source.contains(".AppStrings."))

        let chineseStringLiteral = try NSRegularExpression(pattern: #"\"[^\"\n]*\p{Han}[^\"\n]*\""#)
        let range = NSRange(source.startIndex..., in: source)
        XCTAssertTrue(
            chineseStringLiteral.matches(in: source, range: range).isEmpty,
            "Swift source should use English identifiers/fallbacks and generated catalog symbols"
        )
    }

    func testNonChineseBundlesResolvePermissionFlowStrings() throws {
        let permissionKeys = [
            "permission.allowContactsAccess",
            "common.openSystemSettings",
            "permission.grantFullContactsAccess",
            "permission.contactsAccessRequired"
        ]
        let bundle = Bundle(for: Self.self)

        for locale in supportedLocales.filter({ !$0.hasPrefix("zh") }) {
            let localizationURL = try XCTUnwrap(bundle.url(forResource: locale, withExtension: "lproj"))
            let localizedBundle = try XCTUnwrap(Bundle(url: localizationURL))
            for key in permissionKeys {
                let localized = localizedBundle.localizedString(forKey: key, value: nil, table: "AppStrings")
                XCTAssertNotEqual(localized, key, "\(locale) displayed the source key for \(key)")
                XCTAssertFalse(localized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        let privacyFiles = [
            "en-US": "PRIVACY.en.md",
            "zh-Hans": "PRIVACY.md",
            "zh-Hant": "PRIVACY.zh-Hant.md",
            "ja": "PRIVACY.ja.md",
            "ko": "PRIVACY.ko.md",
            "es-ES": "PRIVACY.es.md",
            "fr-FR": "PRIVACY.fr.md",
            "de-DE": "PRIVACY.de.md"
        ]

        for (locale, metadata) in localizations {
            XCTAssertLessThanOrEqual(try XCTUnwrap(metadata["name"]).count, 30, locale)
            XCTAssertLessThanOrEqual(try XCTUnwrap(metadata["subtitle"]).count, 30, locale)
            XCTAssertLessThanOrEqual(try XCTUnwrap(metadata["keywords"]).count, 100, locale)
            XCTAssertFalse(try XCTUnwrap(metadata["description"]).isEmpty, locale)

            let privacyURL = try XCTUnwrap(URL(string: try XCTUnwrap(metadata["privacyPolicyURL"])))
            XCTAssertEqual(privacyURL.scheme, "https", locale)
            XCTAssertEqual(privacyURL.host, "contactsdeduper.gewill.org", locale)
            XCTAssertTrue(privacyURL.path.hasSuffix("/privacy"), locale)
            let privacyFilename = try XCTUnwrap(privacyFiles[locale])
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

    private func localizationCatalog() throws -> [String: Any] {
        let file = repositoryRoot
            .appendingPathComponent("ContactsDeduper")
            .appendingPathComponent("AppStrings.xcstrings")
        let data = try Data(contentsOf: file)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func localizedValue(
        in localizations: [String: [String: Any]],
        locale: String
    ) throws -> String {
        let localization = try XCTUnwrap(localizations[locale])
        let stringUnit = try XCTUnwrap(localization["stringUnit"] as? [String: String])
        XCTAssertEqual(stringUnit["state"], "translated", locale)
        return try XCTUnwrap(stringUnit["value"])
    }

    private func placeholders(in value: String) throws -> [Placeholder] {
        let pattern = #"%(?:(\d+)\$)?(?:\([^)]+\))?(@|lld|\.1f)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            let position = Range(match.range(at: 1), in: value).flatMap { Int(value[$0]) }
            guard let typeRange = Range(match.range(at: 2), in: value) else {
                XCTFail("Invalid placeholder in \(value)")
                return nil
            }
            return Placeholder(position: position, type: String(value[typeRange]))
        }
    }

    private func placeholderArguments(in value: String) throws -> [Int: String] {
        var nextImplicitArgument = 1
        return try placeholders(in: value).reduce(into: [:]) { result, placeholder in
            let argument = placeholder.position ?? nextImplicitArgument
            if placeholder.position == nil {
                nextImplicitArgument += 1
            }
            result[argument] = placeholder.type
        }
    }

}

private struct Placeholder {
    let position: Int?
    let type: String

    var isExplicit: Bool { position != nil }
}
