import Foundation

struct PhoneRegionOption: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let callingCode: String
    let trunkPrefix: String?

    var id: String { code }

    var localizedName: String {
        Locale.current.localizedString(forRegionCode: code) ?? name
    }
}

struct PhoneMatchingContext: Sendable {
    let defaultRegionCode: String?
    let isDefaultRegionAuthoritative: Bool

    static var automatic: PhoneMatchingContext {
        PhoneMatchingContext(
            defaultRegionCode: nil,
            isDefaultRegionAuthoritative: false
        )
    }
}

let supportedPhoneRegions: [PhoneRegionOption] = [
    PhoneRegionOption(code: "US", name: "United States", callingCode: "1", trunkPrefix: nil),
    PhoneRegionOption(code: "CA", name: "Canada", callingCode: "1", trunkPrefix: nil),
    PhoneRegionOption(code: "CN", name: "China mainland", callingCode: "86", trunkPrefix: "0"),
    PhoneRegionOption(code: "GB", name: "United Kingdom", callingCode: "44", trunkPrefix: "0"),
    PhoneRegionOption(code: "DE", name: "Germany", callingCode: "49", trunkPrefix: "0"),
    PhoneRegionOption(code: "JP", name: "Japan", callingCode: "81", trunkPrefix: "0"),
    PhoneRegionOption(code: "TW", name: "Taiwan", callingCode: "886", trunkPrefix: "0"),
    PhoneRegionOption(code: "HK", name: "Hong Kong", callingCode: "852", trunkPrefix: nil),
    PhoneRegionOption(code: "MO", name: "Macao", callingCode: "853", trunkPrefix: nil),
    PhoneRegionOption(code: "SG", name: "Singapore", callingCode: "65", trunkPrefix: nil),
    PhoneRegionOption(code: "AU", name: "Australia", callingCode: "61", trunkPrefix: "0"),
    PhoneRegionOption(code: "FR", name: "France", callingCode: "33", trunkPrefix: "0"),
    PhoneRegionOption(code: "ES", name: "Spain", callingCode: "34", trunkPrefix: nil),
    PhoneRegionOption(code: "IT", name: "Italy", callingCode: "39", trunkPrefix: nil),
    PhoneRegionOption(code: "IN", name: "India", callingCode: "91", trunkPrefix: "0")
]

enum PhoneMatching {
    private struct ParsedPhone: Sendable {
        let digits: String
        let extensionDigits: String?
        let isExplicitInternational: Bool
        let containsLetters: Bool
    }

    private static let regionRules = Dictionary(
        uniqueKeysWithValues: supportedPhoneRegions.map { ($0.code, $0) }
    )

    /// Conservative matching key used by both duplicate detection and merge
    /// de-duplication. No suffix-only fallback is used because it can merge
    /// unrelated contacts across countries, and a merge deletes records.
    static func matchKey(
        _ value: String,
        regionCode: String?,
        isRegionAuthoritative: Bool
    ) -> String? {
        let parsed = parse(value)
        guard !parsed.containsLetters, parsed.digits.count >= 7 else { return nil }
        let rule = regionRule(for: regionCode)

        let baseKey: String
        if parsed.isExplicitInternational {
            baseKey = "+\(parsed.digits)"
        } else if parsed.digits.count == 11, parsed.digits.hasPrefix("1") {
            if isRegionAuthoritative, let rule {
                baseKey = regionalKey(parsed.digits, rule: rule)
            } else if let rule, rule.callingCode == "1" {
                baseKey = regionalKey(parsed.digits, rule: rule)
            } else if isChineseMobile(parsed.digits) {
                baseKey = "+86\(parsed.digits)"
            } else {
                baseKey = "national:\(parsed.digits)"
            }
        } else if isRegionAuthoritative, let rule {
            baseKey = regionalKey(parsed.digits, rule: rule)
        } else if isNANPNumber(parsed.digits) {
            baseKey = "+1\(parsed.digits)"
        } else if let rule {
            baseKey = regionalKey(parsed.digits, rule: rule)
        } else {
            baseKey = "national:\(parsed.digits)"
        }

        return baseKey + (parsed.extensionDigits.map { ";ext=\($0)" } ?? "")
    }

    /// Region-independent key for preserving distinct stored values while merging.
    /// Explicit international forms and unmarked Chinese/NANP shapes share the same
    /// keys as scanning; ambiguous national formats only de-duplicate by formatting.
    static func storageKey(_ value: String) -> String {
        let parsed = parse(value)
        if parsed.containsLetters {
            return value.lowercased().filter { $0.isLetter || $0.isNumber }
        }

        let baseKey: String
        if parsed.isExplicitInternational, parsed.digits.hasPrefix("1"),
           parsed.digits.count == 11, isNANPNumber(parsed.digits) {
            baseKey = "+1\(parsed.digits.dropFirst())"
        } else if parsed.isExplicitInternational {
            baseKey = "+\(parsed.digits)"
        } else if isNANPNumber(parsed.digits) {
            baseKey = parsed.digits.count == 11
                ? "+1\(parsed.digits.dropFirst())"
                : "+1\(parsed.digits)"
        } else if isChineseMobile(parsed.digits) {
            baseKey = "+86\(parsed.digits)"
        } else {
            baseKey = "national:\(parsed.digits)"
        }
        return baseKey + (parsed.extensionDigits.map { ";ext=\($0)" } ?? "")
    }

    private static func parse(_ value: String) -> ParsedPhone {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let extensionPattern = #"(?i)\s*(?:ext\.?|extension|x|#)\s*(\d+)\s*$"#
        let extensionRange = trimmed.range(of: extensionPattern, options: .regularExpression)
        let base = extensionRange.map { String(trimmed[..<$0.lowerBound]) } ?? trimmed
        let extensionDigits = extensionRange.map {
            String(trimmed[$0]).compactMap(\.wholeNumberValue).map(String.init).joined()
        }
        let isExplicitInternational = base.hasPrefix("+") || base.hasPrefix("00")
        var digits = base.compactMap(\.wholeNumberValue).map(String.init).joined()
        if base.hasPrefix("00"), digits.hasPrefix("00") {
            digits.removeFirst(2)
        }

        return ParsedPhone(
            digits: digits,
            extensionDigits: extensionDigits.flatMap { $0.isEmpty ? nil : $0 },
            isExplicitInternational: isExplicitInternational,
            containsLetters: base.rangeOfCharacter(from: .letters) != nil
        )
    }

    private static func regionRule(for regionCode: String?) -> PhoneRegionOption? {
        guard let regionCode else { return nil }
        let code = regionCode.uppercased().replacingOccurrences(of: "_", with: "-")
        let region = code.split(separator: "-").last.map(String.init) ?? code
        return regionRules[region == "UK" ? "GB" : region]
    }

    private static func regionalKey(_ digits: String, rule: PhoneRegionOption) -> String {
        var nationalNumber = digits

        if rule.callingCode == "1", nationalNumber.count == 11, nationalNumber.hasPrefix("1") {
            nationalNumber.removeFirst()
        } else if let trunkPrefix = rule.trunkPrefix,
                  nationalNumber.hasPrefix(trunkPrefix),
                  nationalNumber.count >= 7 {
            nationalNumber.removeFirst(trunkPrefix.count)
        }
        return "+\(rule.callingCode)\(nationalNumber)"
    }

    private static func isChineseMobile(_ digits: String) -> Bool {
        guard digits.count == 11, digits.first == "1" else { return false }
        return digits.dropFirst().first.map { ("3"..."9").contains(String($0)) } ?? false
    }

    private static func isNANPNumber(_ digits: String) -> Bool {
        let nationalDigits: String
        if digits.count == 11, digits.hasPrefix("1") {
            nationalDigits = String(digits.dropFirst())
        } else {
            nationalDigits = digits
        }
        guard nationalDigits.count == 10 else { return false }
        let values = Array(nationalDigits)
        return ("2"..."9").contains(String(values[0]))
            && ("2"..."9").contains(String(values[3]))
    }
}
