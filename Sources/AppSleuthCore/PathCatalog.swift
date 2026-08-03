import Foundation

public struct SearchLocation: Sendable {
    public let root: URL
    public let kind: FindingKind
    public let scope: FindingScope
    public let baseRisk: RiskLevel
    public let removable: Bool

    public init(root: URL, kind: FindingKind, scope: FindingScope, baseRisk: RiskLevel, removable: Bool = true) {
        self.root = root
        self.kind = kind
        self.scope = scope
        self.baseRisk = baseRisk
        self.removable = removable
    }
}

public enum PathCatalog {
    public static func defaultLocations(homeDirectory home: URL) -> [SearchLocation] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        return [
            SearchLocation(root: library.appendingPathComponent("Application Support"), kind: .applicationSupport, scope: .user, baseRisk: .review),
            SearchLocation(root: library.appendingPathComponent("Preferences"), kind: .preference, scope: .user, baseRisk: .review),
            SearchLocation(root: library.appendingPathComponent("Caches"), kind: .cache, scope: .user, baseRisk: .safe),
            SearchLocation(root: library.appendingPathComponent("Logs"), kind: .log, scope: .user, baseRisk: .safe),
            SearchLocation(root: library.appendingPathComponent("Logs/DiagnosticReports"), kind: .log, scope: .user, baseRisk: .safe),
            SearchLocation(root: library.appendingPathComponent("Saved Application State"), kind: .savedState, scope: .user, baseRisk: .review),
            SearchLocation(root: library.appendingPathComponent("HTTPStorages"), kind: .webData, scope: .user, baseRisk: .review),
            SearchLocation(root: library.appendingPathComponent("WebKit"), kind: .webData, scope: .user, baseRisk: .review),
            SearchLocation(root: library.appendingPathComponent("Cookies"), kind: .webData, scope: .user, baseRisk: .review),
            SearchLocation(root: library.appendingPathComponent("Containers"), kind: .container, scope: .user, baseRisk: .review),
            SearchLocation(root: library.appendingPathComponent("Group Containers"), kind: .groupContainer, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("Application Scripts"), kind: .applicationScript, scope: .user, baseRisk: .review),
            SearchLocation(root: library.appendingPathComponent("LaunchAgents"), kind: .launchAgent, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("LaunchServices"), kind: .backgroundHelper, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("Internet Plug-Ins"), kind: .plugin, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("QuickLook"), kind: .plugin, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("Spotlight"), kind: .plugin, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("PreferencePanes"), kind: .plugin, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("Services"), kind: .plugin, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("Screen Savers"), kind: .plugin, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("Audio/Plug-Ins/Components"), kind: .plugin, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("Audio/Plug-Ins/VST"), kind: .plugin, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("Audio/Plug-Ins/VST3"), kind: .plugin, scope: .user, baseRisk: .high),
            SearchLocation(root: library.appendingPathComponent("Frameworks"), kind: .framework, scope: .user, baseRisk: .high, removable: false),
            SearchLocation(root: library.appendingPathComponent("Fonts"), kind: .font, scope: .user, baseRisk: .high, removable: false),
            SearchLocation(root: library.appendingPathComponent("ColorSync/Profiles"), kind: .colorProfile, scope: .user, baseRisk: .high, removable: false),

            SearchLocation(root: URL(fileURLWithPath: "/Library/Application Support"), kind: .applicationSupport, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Preferences"), kind: .preference, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Caches"), kind: .cache, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Logs"), kind: .log, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"), kind: .log, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/LaunchAgents"), kind: .launchAgent, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/LaunchDaemons"), kind: .launchDaemon, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/LaunchServices"), kind: .backgroundHelper, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), kind: .privilegedHelper, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/StartupItems"), kind: .startupItem, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Internet Plug-Ins"), kind: .plugin, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/QuickLook"), kind: .plugin, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Spotlight"), kind: .plugin, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/PreferencePanes"), kind: .plugin, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Services"), kind: .plugin, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Screen Savers"), kind: .plugin, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/Components"), kind: .plugin, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST"), kind: .plugin, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3"), kind: .plugin, scope: .system, baseRisk: .high),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Frameworks"), kind: .framework, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Fonts"), kind: .font, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/Library/ColorSync/Profiles"), kind: .colorProfile, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/Library/SystemExtensions"), kind: .systemExtension, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/Library/Extensions"), kind: .driverExtension, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/usr/local/bin"), kind: .commandLineTool, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/opt/homebrew/bin"), kind: .commandLineTool, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/usr/local/share/zsh/site-functions"), kind: .shellIntegration, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/opt/homebrew/share/zsh/site-functions"), kind: .shellIntegration, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/usr/local/share/fish/vendor_completions.d"), kind: .shellIntegration, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/opt/homebrew/share/fish/vendor_completions.d"), kind: .shellIntegration, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/opt/homebrew/Caskroom"), kind: .packageManagerRecord, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/opt/homebrew/Cellar"), kind: .packageManagerRecord, scope: .system, baseRisk: .protected, removable: false),
            SearchLocation(root: URL(fileURLWithPath: "/var/db/receipts"), kind: .receipt, scope: .system, baseRisk: .protected, removable: false)
        ]
    }
}
