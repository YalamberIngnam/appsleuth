import Foundation

public struct MatchEvidence: Equatable, Sendable {
    public let confidence: Int
    public let reasons: [String]
}

public struct Matcher {
    private static let removableSuffixes = [
        ".savedstate", ".plist", ".cache", ".log", ".app", ".qlgenerator",
        ".plugin", ".appex", ".prefpane", ".saver", ".component", ".vst",
        ".vst3", ".framework", ".kext", ".dext", ".systemextension", ".ttf",
        ".otf", ".ttc", ".dfont", ".icc", ".icm", ".bom"
    ]

    public init() {}

    public func evidence(for candidate: URL, app: ApplicationIdentity, kind: FindingKind) -> MatchEvidence? {
        let rawName = candidate.lastPathComponent.lowercased()
        let stem = Self.stripKnownSuffixes(rawName)
        let bundleID = app.bundleIdentifier.lowercased()
        let normalizedStem = Self.normalize(stem)
        let normalizedName = Self.normalize(app.name)

        // Product-name matching must never associate a third-party app with
        // Apple's private identifiers. For example, Parsec (tv.parsec.www)
        // is unrelated to macOS components named com.apple.parsec.*.
        if !Self.isAppleOwnedIdentifier(bundleID), Self.isAppleOwnedIdentifier(stem) {
            return nil
        }

        var confidence = 0
        var reasons: [String] = []

        if stem == bundleID {
            confidence = 100
            reasons.append("filename exactly matches bundle identifier \(app.bundleIdentifier)")
        } else if Self.containsIdentifier(stem, identifier: bundleID) {
            confidence = 94
            reasons.append("filename contains the complete bundle identifier")
        }

        if !normalizedName.isEmpty, normalizedStem == normalizedName, confidence < 92 {
            confidence = 92
            reasons = ["filename exactly matches normalized application name \(app.name)"]
        }

        let productTokens = Self.distinctiveTokens(in: app.name)
        if !productTokens.isEmpty,
           productTokens.allSatisfy({ normalizedStem.contains($0) }),
           confidence < 80 {
            confidence = 80
            reasons = ["filename contains all distinctive application-name tokens: \(productTokens.joined(separator: ", "))"]
        }

        if [.launchAgent, .launchDaemon, .privilegedHelper, .startupItem, .preference].contains(kind),
           let plistEvidence = plistEvidence(at: candidate, app: app),
           plistEvidence.confidence > confidence {
            confidence = plistEvidence.confidence
            reasons = plistEvidence.reasons
        }

        guard confidence >= 75 else { return nil }
        return MatchEvidence(confidence: confidence, reasons: reasons)
    }

    private func plistEvidence(at url: URL, app: ApplicationIdentity) -> MatchEvidence? {
        guard url.pathExtension.lowercased() == "plist",
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any]
        else { return nil }

        var strings: [String] = []
        for key in ["Label", "BundleIdentifier", "Program"] {
            if let value = dictionary[key] as? String { strings.append(value) }
        }
        if let arguments = dictionary["ProgramArguments"] as? [String] {
            strings.append(contentsOf: arguments)
        }
        if let identifiers = dictionary["AssociatedBundleIdentifiers"] as? [String] {
            strings.append(contentsOf: identifiers)
        }

        let bundleID = app.bundleIdentifier.lowercased()
        if strings.contains(where: { $0.lowercased() == bundleID }) {
            return MatchEvidence(confidence: 100, reasons: ["property list declares the exact application bundle identifier"])
        }
        if strings.contains(where: { Self.containsIdentifier($0.lowercased(), identifier: bundleID) }) {
            return MatchEvidence(confidence: 96, reasons: ["property list references the complete application bundle identifier"])
        }
        if strings.contains(where: { $0.hasPrefix(app.path + "/") || $0 == app.path }) {
            return MatchEvidence(confidence: 100, reasons: ["property list launches a program inside the application bundle"])
        }
        if let executable = app.executableName?.lowercased(),
           strings.contains(where: { URL(fileURLWithPath: $0).lastPathComponent.lowercased() == executable }) {
            return MatchEvidence(confidence: 88, reasons: ["property list references the application executable by exact name"])
        }
        return nil
    }

    private static func stripKnownSuffixes(_ value: String) -> String {
        var result = value
        var changed = true
        while changed {
            changed = false
            for suffix in removableSuffixes where result.hasSuffix(suffix) {
                result.removeLast(suffix.count)
                changed = true
                break
            }
        }
        return result
    }

    private static func containsIdentifier(_ value: String, identifier: String) -> Bool {
        guard let range = value.range(of: identifier) else { return false }
        let allowed = CharacterSet.alphanumerics
        let before = range.lowerBound == value.startIndex ? nil : value[value.index(before: range.lowerBound)].unicodeScalars.first
        let after = range.upperBound == value.endIndex ? nil : value[range.upperBound].unicodeScalars.first
        return before.map { !allowed.contains($0) } ?? true
            && after.map { !allowed.contains($0) } ?? true
    }

    private static func isAppleOwnedIdentifier(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered == "com.apple"
            || lowered.hasPrefix("com.apple.")
            || lowered.contains(".com.apple.")
            || lowered == "is.workflow"
            || lowered.hasPrefix("is.workflow.")
            || lowered.contains(".is.workflow.")
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func distinctiveTokens(in name: String) -> [String] {
        let ignored: Set<String> = ["app", "application", "for", "mac", "macos", "the"]
        return name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !ignored.contains($0) && Int($0) == nil }
            .map(normalize)
    }
}
