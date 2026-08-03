import AppSleuthCore
import Darwin
import Foundation

enum TerminalMenuAction: CaseIterable {
    case list
    case leftovers
    case services
    case scan
    case explain
    case uninstall
    case purge
    case restore
    case doctor
    case optimize
    case help
    case quit

    var shortcut: Character {
        switch self {
        case .list: return "l"
        case .leftovers: return "o"
        case .services: return "a"
        case .scan: return "s"
        case .explain: return "e"
        case .uninstall: return "u"
        case .purge: return "x"
        case .restore: return "r"
        case .doctor: return "p"
        case .optimize: return "m"
        case .help: return "h"
        case .quit: return "q"
        }
    }

    var label: String {
        switch self {
        case .list: return "List installed applications"
        case .leftovers: return "Find and review suspected leftovers"
        case .services: return "Show active third-party user services"
        case .scan: return "Scan an installed application"
        case .explain: return "Explain matching evidence"
        case .uninstall: return "Preview an uninstall plan"
        case .purge: return "Permanently purge an application"
        case .restore: return "Preview a restore"
        case .doctor: return "Check permissions and scan access"
        case .optimize: return "Optimize & check with safe previews"
        case .help: return "Show command-line help"
        case .quit: return "Quit"
        }
    }

    var compactLabel: String {
        switch self {
        case .list: return "List applications"
        case .leftovers: return "Suspected leftovers"
        case .services: return "Active user services"
        case .scan: return "Scan application"
        case .explain: return "Explain matches"
        case .uninstall: return "Preview uninstall"
        case .purge: return "Permanent purge"
        case .restore: return "Preview restore"
        case .doctor: return "Permissions & access"
        case .optimize: return "Optimize & check"
        case .help: return "Help"
        case .quit: return "Quit"
        }
    }
}

enum TerminalInput: Equatable {
    case up
    case down
    case enter
    case character(Character)
    case escape
    case endOfInput
}

enum HomeOverviewSection: Hashable {
    case disk
    case applications
    case jobs
}

final class TerminalUI {
    private var originalSettings = termios()
    private var hasOriginalSettings = false
    private var rawModeEnabled = false

    static var isAvailable: Bool {
        isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }

    func enter() {
        guard Self.isAvailable else { return }
        if tcgetattr(STDIN_FILENO, &originalSettings) == 0 {
            hasOriginalSettings = true
        }
        enableRawMode()
        write("\u{001B}[?1049h\u{001B}[?25l")
    }

    func leave() {
        disableRawMode()
        write("\u{001B}[0m\u{001B}[?25h\u{001B}[?1049l")
    }

    func renderHome(
        version: String,
        selectedIndex: Int,
        overview: SystemOverview,
        loadingSections: Set<HomeOverviewSection> = [],
        applicationNames: [String] = []
    ) {
        let width = contentWidth()
        let terminalRows = terminalSize().rows
        var lines: [String] = []

        if terminalRows >= 22 {
            let logo = [
                #"    _                _____ __           __  __"#,
                #"   / \   ____  ____  / ___// /__  __  __/ /_/ /_"#,
                #"  / _ \ / __ \/ __ \ \__ \/ / _ \/ / / / __/ __ \"#,
                #" / ___ / /_/ / /_/ /___/ / /  __/ /_/ / /_/ / / /"#,
                #"/_/  |_\____/ .___//____/_/\___/\__,_/\__/_/ /_/"#,
                #"          /_/"#
            ]
            lines.append(contentsOf: logo.map {
                centered("\u{001B}[1;38;5;45m\($0)\u{001B}[0m", width: width)
            })
        } else {
            lines.append(centered(
                "\u{001B}[1;38;5;45m╭────────────── APP SLEUTH ──────────────╮\u{001B}[0m",
                width: width
            ))
        }

        lines.append(centered("\u{001B}[1mEvidence-first macOS cleanup · v\(version)\u{001B}[0m", width: width))
        lines.append(centered(
            "\u{001B}[2mDiscovery is read-only. Changes require an exact command and confirmation.\u{001B}[0m",
            width: width
        ))
        lines.append("")
        lines.append(leftAligned("\u{001B}[1;36mMAC OVERVIEW\u{001B}[0m", width: width))
        lines.append(leftAligned(
            diskSummary(overview, loading: loadingSections.contains(.disk)),
            width: width
        ))
        lines.append(leftAligned(
            applicationSummary(overview, loading: loadingSections.contains(.applications)),
            width: width
        ))
        lines.append(leftAligned(
            applicationNameSummary(
                applicationNames,
                totalApplicationCount: overview.externalApplicationCount,
                loading: loadingSections.contains(.applications),
                width: width
            ),
            width: width
        ))
        lines.append(leftAligned(
            serviceSummary(overview, loading: loadingSections.contains(.jobs)),
            width: width
        ))
        lines.append("")

        let actions = TerminalMenuAction.allCases
        let menuRows = (actions.count + 1) / 2
        let leftWidth = width / 2
        let rightWidth = width - leftWidth
        for menuRow in 0..<menuRows {
            let left = menuCell(
                action: actions[menuRow],
                index: menuRow,
                selectedIndex: selectedIndex,
                width: leftWidth
            )
            let rightIndex = menuRow + menuRows
            let right = rightIndex < actions.count
                ? menuCell(
                    action: actions[rightIndex],
                    index: rightIndex,
                    selectedIndex: selectedIndex,
                    width: rightWidth
                )
                : String(repeating: " ", count: rightWidth)
            lines.append(left + right)
        }
        lines.append("")
        lines.append(centered(
            "\u{001B}[2mUse ↑/↓ and Return, or press a shortcut key.\u{001B}[0m",
            width: width
        ))
        renderCenteredBlock(lines)
    }

    private func menuCell(
        action: TerminalMenuAction,
        index: Int,
        selectedIndex: Int,
        width: Int
    ) -> String {
        let content = " \(index == selectedIndex ? "›" : " ") [\(action.shortcut)] \(action.compactLabel)"
        let cell = leftAligned(content, width: width)
        return index == selectedIndex
            ? "\u{001B}[1;30;46m\(cell)\u{001B}[0m"
            : cell
    }

    func prompt(_ message: String) -> String? {
        clear()
        write("\u{001B}[1;36mAppSleuth\u{001B}[0m\n\n")
        return readPrompt(message)
    }

    func promptInline(_ message: String) -> String? {
        readPrompt(message)
    }

    func selectApplication(
        _ applications: [InstalledApplication],
        title: String
    ) -> InstalledApplication? {
        guard !applications.isEmpty else { return nil }
        var selectedIndex = 0
        while true {
            renderApplicationSelector(
                applications,
                title: title,
                selectedIndex: selectedIndex
            )
            switch readInput() {
            case .up:
                selectedIndex = (selectedIndex - 1 + applications.count) % applications.count
            case .down:
                selectedIndex = (selectedIndex + 1) % applications.count
            case .enter:
                return applications[selectedIndex]
            case let .character(character) where character.lowercased() == "q":
                return nil
            case .escape, .endOfInput:
                return nil
            case .character:
                continue
            }
        }
    }

    func browseApplications(_ applications: [InstalledApplication]) {
        guard !applications.isEmpty else { return }
        var selectedIndex = 0
        while true {
            renderApplicationBrowser(applications, selectedIndex: selectedIndex)
            switch readInput() {
            case .up:
                selectedIndex = (selectedIndex - 1 + applications.count) % applications.count
            case .down:
                selectedIndex = (selectedIndex + 1) % applications.count
            case let .character(character) where character.lowercased() == "q":
                return
            case .escape, .endOfInput:
                return
            case .enter, .character:
                continue
            }
        }
    }

    private func readPrompt(_ message: String) -> String? {
        write("\(message)\n> \u{001B}[?25h")
        var bytes: [UInt8] = []
        while let byte = FileHandle.standardInput.readData(ofLength: 1).first {
            switch byte {
            case 3, 4:
                write("\u{001B}[?25l")
                return nil
            case 10, 13:
                write("\n\u{001B}[?25l")
                return String(bytes: bytes, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            case 8, 127:
                guard !bytes.isEmpty else { continue }
                var characterStart = bytes.count - 1
                while characterStart > 0, bytes[characterStart] & 0b1100_0000 == 0b1000_0000 {
                    characterStart -= 1
                }
                bytes.removeSubrange(characterStart...)
                write("\u{8} \u{8}")
            default:
                guard byte >= 32 else { continue }
                bytes.append(byte)
                FileHandle.standardOutput.write(Data([byte]))
            }
        }
        write("\u{001B}[?25l")
        return nil
    }

    func prepareOutput(_ title: String) {
        clear()
        write("\u{001B}[1;36m\(title)\u{001B}[0m\n\n")
    }

    func showError(_ error: Error) {
        write("\n\u{001B}[1;31mError:\u{001B}[0m \(error)\n")
    }

    func waitForKey() {
        write("\n\u{001B}[2mPress any key to return to the AppSleuth menu.\u{001B}[0m")
        _ = readKey()
    }

    func readInput() -> TerminalInput {
        guard let byte = readByte() else { return .endOfInput }
        switch byte {
        case 3, 4:
            return .endOfInput
        case 10, 13:
            return .enter
        case 27:
            guard let second = readByte() else { return .escape }
            guard second == 91, let third = readByte() else { return .escape }
            switch third {
            case 65: return .up
            case 66: return .down
            default: return .escape
            }
        default:
            return .character(Character(String(UnicodeScalar(byte))))
        }
    }

    func readKey() -> Character {
        guard let byte = readByte() else { return "q" }
        if byte == 3 || byte == 4 { return "q" }
        return Character(String(UnicodeScalar(byte)))
    }

    private func readByte() -> UInt8? {
        FileHandle.standardInput.readData(ofLength: 1).first
    }

    private func clear() {
        write("\u{001B}[2J\u{001B}[H")
    }

    private func renderApplicationSelector(
        _ applications: [InstalledApplication],
        title: String,
        selectedIndex: Int
    ) {
        let width = contentWidth()
        let pageSize = max(5, min(12, terminalSize().rows - 9))
        let maximumStart = max(0, applications.count - pageSize)
        let start = min(max(0, selectedIndex - pageSize / 2), maximumStart)
        let end = min(applications.count, start + pageSize)
        var lines = [
            centered("\u{001B}[1;31m\(title)\u{001B}[0m", width: width),
            centered("Select with ↑/↓ and Return · q cancels", width: width),
            centered("\u{001B}[2mA complete evidence scan and dry-run plan follows selection.\u{001B}[0m", width: width),
            ""
        ]
        for index in start..<end {
            let item = applications[index]
            let number = String(index + 1) + "."
            let name = fitPlainText(item.application.name, width: max(16, width - 27))
            let size = formatBytes(item.bundleByteSize)
            let content = " \(index == selectedIndex ? "›" : " ") \(fitPlainText(number, width: 4)) \(fitPlainText(name, width: max(16, width - 27))) \(fitPlainText(size, width: 12))"
            let row = leftAligned(content, width: width)
            lines.append(index == selectedIndex
                ? "\u{001B}[1;37;41m\(row)\u{001B}[0m"
                : row)
        }
        lines.append("")
        lines.append(centered(
            "Showing \(start + 1)–\(end) of \(applications.count) third-party applications",
            width: width
        ))
        renderCenteredBlock(lines)
    }

    private func renderApplicationBrowser(
        _ applications: [InstalledApplication],
        selectedIndex: Int
    ) {
        let width = contentWidth()
        let pageSize = max(4, min(9, terminalSize().rows - 14))
        let maximumStart = max(0, applications.count - pageSize)
        let start = min(max(0, selectedIndex - pageSize / 2), maximumStart)
        let end = min(applications.count, start + pageSize)
        let nameWidth = max(15, width - 39)
        var lines = [
            centered("\u{001B}[1;38;5;45mINSTALLED APPLICATIONS\u{001B}[0m", width: width),
            centered("Browse with ↑/↓ · q returns to home", width: width),
            "",
            leftAligned(
                "      \(fitPlainText("Application", width: nameWidth)) \(fitPlainText("Version", width: 11)) \(fitPlainText("Size", width: 10)) Scope",
                width: width
            ),
            leftAligned(
                "      \(String(repeating: "─", count: nameWidth)) \(String(repeating: "─", count: 11)) \(String(repeating: "─", count: 10)) ──────",
                width: width
            )
        ]
        for index in start..<end {
            let item = applications[index]
            let number = fitPlainText(String(index + 1) + ".", width: 4)
            let name = fitPlainText(item.application.name, width: nameWidth)
            let version = fitPlainText(item.application.version ?? "—", width: 11)
            let size = fitPlainText(compactByteSize(item.bundleByteSize), width: 10)
            let scope = item.scope.rawValue
            let content = " \(index == selectedIndex ? "›" : " ") \(number) \(name) \(version) \(size) \(scope)"
            let row = leftAligned(content, width: width)
            lines.append(index == selectedIndex
                ? "\u{001B}[1;30;46m\(row)\u{001B}[0m"
                : row)
        }

        let selected = applications[selectedIndex]
        lines.append("")
        lines.append(leftAligned(
            "\u{001B}[1mSelected:\u{001B}[0m \(clippedPlainText(selected.application.name, width: max(1, width - 10)))",
            width: width
        ))
        lines.append(leftAligned(
            "Version \(selected.application.version ?? "—") · Size \(formatBytes(selected.bundleByteSize)) · Scope \(selected.scope.rawValue)",
            width: width
        ))
        lines.append(leftAligned(
            clippedPlainText("ID:   \(selected.application.bundleIdentifier)", width: width),
            width: width
        ))
        lines.append(leftAligned(
            clippedPlainText("Path: \(selected.application.path)", width: width),
            width: width
        ))
        lines.append("")
        lines.append(centered(
            "Showing \(start + 1)–\(end) of \(applications.count) applications",
            width: width
        ))
        renderCenteredBlock(lines)
    }

    private func fitPlainText(_ value: String, width: Int) -> String {
        let shortened = value.count > width
            ? String(value.prefix(max(1, width - 1))) + "…"
            : value
        return shortened + String(repeating: " ", count: max(0, width - shortened.count))
    }

    private func diskSummary(_ overview: SystemOverview, loading: Bool) -> String {
        if loading {
            return "Disk   \(loadingIndicator) Reading used and available storage…"
        }
        return "Disk   Used \(formatBytes(overview.usedDiskBytes)) / \(formatBytes(overview.totalDiskBytes))" +
            "   Available \(formatBytes(overview.availableDiskBytes))"
    }

    private func applicationSummary(_ overview: SystemOverview, loading: Bool) -> String {
        if loading {
            if overview.externalApplicationCount == 0 {
                return "Apps   \(loadingIndicator) Finding installed applications…"
            }
            return "Apps   \(loadingIndicator) \(overview.externalApplicationCount) found · Calculating bundle sizes…"
        }
        let sizePrefix = overview.indexedApplicationCount < overview.externalApplicationCount ? "≥" : "≈"
        let sizeCoverage = overview.indexedApplicationCount < overview.externalApplicationCount
            ? " (\(overview.indexedApplicationCount)/\(overview.externalApplicationCount) indexed)"
            : ""
        return "Apps   \(overview.externalApplicationCount) third-party bundles · Bundle space \(sizePrefix) \(formatBytes(overview.installedApplicationBytes))\(sizeCoverage)"
    }

    private func applicationNameSummary(
        _ applicationNames: [String],
        totalApplicationCount: Int,
        loading: Bool,
        width: Int
    ) -> String {
        guard !applicationNames.isEmpty else {
            return loading
                ? "Names  \(loadingIndicator) Loading application names…"
                : "Names  No third-party application names found"
        }
        let visibleNames = applicationNames.prefix(2)
        let remaining = max(0, totalApplicationCount - visibleNames.count)
        let remainder = remaining > 0 ? " · +\(remaining) more" : ""
        return clippedPlainText(
            "Names  \(visibleNames.joined(separator: " · "))\(remainder) · [l] full list",
            width: width
        )
    }

    private func serviceSummary(_ overview: SystemOverview, loading: Bool) -> String {
        if loading {
            return "Jobs   \(loadingIndicator) Inspecting active third-party user services…"
        }
        let serviceCount = overview.activeServiceInspectionAvailable
            ? String(overview.activeUserServices.count)
            : "Unavailable"
        return "Jobs   Active third-party user services \(serviceCount)"
    }

    private var loadingIndicator: String {
        "\u{001B}[38;5;45m◉\u{001B}[0m"
    }

    private func clippedPlainText(_ value: String, width: Int) -> String {
        guard value.count > width else { return value }
        return String(value.prefix(max(1, width - 1))) + "…"
    }

    private func formatBytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "Unavailable" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }

    private func compactByteSize(_ bytes: UInt64?) -> String {
        guard bytes != nil else { return "—" }
        return formatBytes(bytes)
    }

    private func renderCenteredBlock(_ lines: [String]) {
        clear()
        let size = terminalSize()
        let topPadding = max(0, (size.rows - lines.count) / 2)
        if topPadding > 0 { write(String(repeating: "\n", count: topPadding)) }
        let width = contentWidth()
        let leftPadding = max(0, (size.columns - width) / 2)
        let prefix = String(repeating: " ", count: leftPadding)
        for line in lines {
            write(prefix + line + "\n")
        }
    }

    private func contentWidth() -> Int {
        max(20, min(78, terminalSize().columns - 2))
    }

    private func centered(_ value: String, width: Int) -> String {
        let length = visibleLength(value)
        let leading = max(0, (width - length) / 2)
        let trailing = max(0, width - length - leading)
        return String(repeating: " ", count: leading) + value + String(repeating: " ", count: trailing)
    }

    private func leftAligned(_ value: String, width: Int) -> String {
        let length = visibleLength(value)
        return value + String(repeating: " ", count: max(0, width - length))
    }

    private func visibleLength(_ value: String) -> Int {
        var count = 0
        var inEscape = false
        for scalar in value.unicodeScalars {
            if scalar.value == 27 {
                inEscape = true
                continue
            }
            if inEscape {
                if scalar.value == 109 { inEscape = false }
                continue
            }
            count += 1
        }
        return count
    }

    private func terminalSize() -> (rows: Int, columns: Int) {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 else {
            return (24, 80)
        }
        return (max(1, Int(size.ws_row)), max(1, Int(size.ws_col)))
    }

    private func enableRawMode() {
        guard hasOriginalSettings, !rawModeEnabled else { return }
        var raw = originalSettings
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
        if tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 {
            rawModeEnabled = true
        }
    }

    private func disableRawMode() {
        guard hasOriginalSettings, rawModeEnabled else { return }
        var settings = originalSettings
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &settings)
        rawModeEnabled = false
    }

    private func write(_ value: String) {
        FileHandle.standardOutput.write(Data(value.utf8))
    }
}
