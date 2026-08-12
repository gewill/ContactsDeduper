import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    private let supportedLocales = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de"]
    private let localizedCallPattern = #"\b(?:String\s*\(\s*localized\s*:|Text|Button|Label|Section|Picker|NavigationLink|ProgressView|ContentUnavailableView|LabeledContent|Menu|Toggle|TextField|SecureField|navigationTitle|accessibilityLabel|confirmationDialog|alert|help)\s*\(\s*""#

    func testEverySupportedLocaleContainsEveryLocalizedString() throws {
        let tables = try localizationTables()

        let expectedKeys = Set(try XCTUnwrap(tables["zh-Hans"]).keys)
        XCTAssertFalse(expectedKeys.isEmpty)

        for locale in supportedLocales {
            let strings = try XCTUnwrap(tables[locale])
            XCTAssertEqual(Set(strings.keys), expectedKeys, "\(locale) has missing or extra localization keys")
            XCTAssertTrue(strings.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

            for key in expectedKeys {
                let value = try XCTUnwrap(strings[key])
                XCTAssertEqual(
                    try placeholderArguments(in: value),
                    try placeholderArguments(in: key),
                    "\(locale) changed placeholders for \(key)"
                )
                if try placeholderArguments(in: key).count > 1 {
                    XCTAssertTrue(
                        try placeholders(in: value).allSatisfy(\.isExplicit),
                        "\(locale) must number every placeholder in \(key)"
                    )
                }
            }
        }
    }

    func testEveryLocalizedSourceStringExistsInEveryTable() throws {
        let expectedKeys = Set(try XCTUnwrap(try localizationTables()["zh-Hans"]).keys)
        let sources = try FileManager.default.contentsOfDirectory(
            at: repositoryRoot.appendingPathComponent("ContactsDeduper"),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let literals = try sources.flatMap(localizedLiterals(in:))
        XCTAssertFalse(literals.isEmpty)

        for literal in literals {
            XCTAssertTrue(
                expectedKeys.contains(where: literal.matches),
                "Missing localization key for \(literal.file.lastPathComponent):\(literal.line)"
            )
        }
    }

    func testNonChineseBundlesResolvePermissionFlowStrings() throws {
        let permissionKeys = [
            "允许访问通讯录",
            "打开系统设置",
            "授予完整通讯录权限",
            "需要通讯录权限"
        ]

        for locale in supportedLocales.filter({ !$0.hasPrefix("zh") }) {
            let bundleURL = repositoryRoot
                .appendingPathComponent("ContactsDeduper")
                .appendingPathComponent("\(locale).lproj")
            let bundle = try XCTUnwrap(Bundle(url: bundleURL))
            for key in permissionKeys {
                let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
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

        for (locale, metadata) in localizations {
            XCTAssertLessThanOrEqual(try XCTUnwrap(metadata["name"]).count, 30, locale)
            XCTAssertLessThanOrEqual(try XCTUnwrap(metadata["subtitle"]).count, 30, locale)
            XCTAssertLessThanOrEqual(try XCTUnwrap(metadata["keywords"]).count, 100, locale)
            XCTAssertFalse(try XCTUnwrap(metadata["description"]).isEmpty, locale)

            let privacyURL = try XCTUnwrap(URL(string: try XCTUnwrap(metadata["privacyPolicyURL"])))
            let privacyFilename = privacyURL.lastPathComponent
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

    private func localizationTables() throws -> [String: [String: String]] {
        let resources = repositoryRoot.appendingPathComponent("ContactsDeduper")
        return try supportedLocales.reduce(into: [:]) { result, locale in
            let file = resources
                .appendingPathComponent("\(locale).lproj")
                .appendingPathComponent("Localizable.strings")
            result[locale] = try loadStrings(at: file)
        }
    }

    private func placeholders(in value: String) throws -> [Placeholder] {
        let pattern = #"%(?:(\d+)\$)?(@|lld|\.1f)"#
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

    private func localizedLiterals(in file: URL) throws -> [LocalizedLiteral] {
        let source = try String(contentsOf: file, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: localizedCallPattern)
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: source) else { return nil }
            let line = source[..<matchRange.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            guard let segments = stringSegments(in: source, afterOpeningQuote: matchRange.upperBound) else {
                XCTFail("Unterminated localized string at \(file.lastPathComponent):\(line)")
                return nil
            }
            return LocalizedLiteral(file: file, line: line, segments: segments)
        }
    }

    private func stringSegments(
        in source: String,
        afterOpeningQuote start: String.Index
    ) -> [String]? {
        var index = start
        var segments = [""]
        var interpolationDepth = 0

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)

            if interpolationDepth == 0 {
                if character == "\"" { return segments }
                if character == "\\", next < source.endIndex {
                    if source[next] == "(" {
                        interpolationDepth = 1
                        segments.append("")
                        index = source.index(after: next)
                        continue
                    }
                    segments[segments.count - 1].append(source[next])
                    index = source.index(after: next)
                    continue
                }
                segments[segments.count - 1].append(character)
            } else if character == "(" {
                interpolationDepth += 1
            } else if character == ")" {
                interpolationDepth -= 1
            }
            index = next
        }
        return nil
    }
}

private struct Placeholder {
    let position: Int?
    let type: String

    var isExplicit: Bool { position != nil }
}

private struct LocalizedLiteral {
    let file: URL
    let line: Int
    let segments: [String]

    func matches(_ key: String) -> Bool {
        let placeholderPattern = #"%(?:\d+\$)?(?:@|lld|\.1f)"#
        let pattern = "^" + segments
            .map { segment in
                let formatSegment = segments.count > 1
                    ? segment.replacingOccurrences(of: "%", with: "%%")
                    : segment
                return NSRegularExpression.escapedPattern(for: formatSegment)
            }
            .joined(separator: placeholderPattern) + "$"
        return key.range(of: pattern, options: .regularExpression) != nil
    }
}
