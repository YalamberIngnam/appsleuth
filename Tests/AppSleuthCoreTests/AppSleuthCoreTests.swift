import XCTest
@testable import AppSleuthCore

private final class TestPrivilegedApplicationRemover: PrivilegedApplicationRemoving {
    let failAuthorization: Bool
    private(set) var authorizationCount = 0
    private(set) var removedPaths: [String] = []

    init(failAuthorization: Bool = false) {
        self.failAuthorization = failAuthorization
    }

    func authorize() throws {
        authorizationCount += 1
        if failAuthorization {
            throw AppSleuthError.unsafeOperation("simulated administrator cancellation")
        }
    }

    func removeApplication(atPath path: String) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: path
        )
        try FileManager.default.removeItem(atPath: path)
        removedPaths.append(path)
    }
}

private final class TestOptimizationCommandRunner: OptimizationCommandRunning {
    private var results: [String: CommandResult]
    private(set) var calls: [String] = []

    init(results: [String: CommandResult]) {
        self.results = results
    }

    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval?
    ) throws -> CommandResult {
        let key = Self.key(executable, arguments)
        calls.append(key)
        return results[key] ?? CommandResult(
            terminationStatus: 1,
            standardOutput: Data(),
            timedOut: false
        )
    }

    static func key(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).joined(separator: "\u{1f}")
    }
}

final class AppSleuthCoreTests: XCTestCase {
    private var fixtureRoot: URL!
    private var home: URL!
    private var applications: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-fixtures", isDirectory: true)
        fixtureRoot = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = fixtureRoot.appendingPathComponent("Users/tester", isDirectory: true)
        applications = fixtureRoot.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot, FileManager.default.fileExists(atPath: fixtureRoot.path) {
            try FileManager.default.removeItem(at: fixtureRoot)
        }
    }

    func testLocatorReadsBundleMetadataByNameAndIdentifier() throws {
        let appURL = try makeApplication(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let locator = ApplicationLocator(searchDirectories: [applications], homeDirectory: home)

        XCTAssertEqual(try locator.locate("Pixel Forge").path, appURL.path)
        XCTAssertEqual(try locator.locate("Pixel Forge.app").path, appURL.path)
        XCTAssertEqual(try locator.locate("dev.example.pixelforge").name, "Pixel Forge")
    }

    func testLocatorListsInstalledApplicationsInStableNameOrder() throws {
        _ = try makeApplication(name: "Zulu Paint", bundleID: "dev.example.zulu")
        _ = try makeApplication(name: "Alpha Notes", bundleID: "dev.example.alpha")
        let locator = ApplicationLocator(searchDirectories: [applications], homeDirectory: home)

        let installed = locator.installedApplications()

        XCTAssertEqual(installed.map(\.application.name), ["Alpha Notes", "Zulu Paint"])
        XCTAssertEqual(installed.map(\.scope), [.shared, .shared])
    }

    func testLocatorCanExcludeSystemApplications() throws {
        let systemApplications = fixtureRoot.appendingPathComponent("System/Applications", isDirectory: true)
        _ = try makeApplication(name: "Shared App", bundleID: "dev.example.shared")
        _ = try makeApplication(
            name: "System App",
            bundleID: "com.apple.system-app",
            directory: systemApplications
        )
        let locator = ApplicationLocator(
            searchLocations: [
                ApplicationSearchLocation(directory: applications, scope: .shared),
                ApplicationSearchLocation(directory: systemApplications, scope: .system)
            ]
        )

        let installed = locator.installedApplications(includeSystem: false)

        XCTAssertEqual(installed.map(\.application.name), ["Shared App"])
    }

    func testLeftoverScannerUsesVendorNamespaceAndMultipleEvidence() throws {
        let installedIdentity = try identity(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let installed = [InstalledApplication(application: installedIdentity, scope: .shared)]
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let preferences = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        try FileManager.default.createDirectory(
            at: caches.appendingPathComponent("org.abandoned.paint", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(
            to: preferences.appendingPathComponent("org.abandoned.paint.plist")
        )
        try FileManager.default.createDirectory(
            at: caches.appendingPathComponent("dev.example.old-helper", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: caches.appendingPathComponent("Plain Vendor Folder", isDirectory: true),
            withIntermediateDirectories: true
        )
        let locations = [
            SearchLocation(root: caches, kind: .cache, scope: .user, baseRisk: .safe),
            SearchLocation(root: preferences, kind: .preference, scope: .user, baseRisk: .review)
        ]

        let report = LeftoverScanner(
            locations: locations,
            homeDirectory: home,
            inspectRuntime: false
        ).scan(installedApplications: installed)

        XCTAssertEqual(report.candidates.count, 2)
        XCTAssertTrue(report.candidates.allSatisfy { $0.suspectedIdentifier == "org.abandoned.paint" })
        XCTAssertTrue(report.candidates.allSatisfy { $0.suspectedName == "Paint · Abandoned" })
        XCTAssertTrue(report.candidates.allSatisfy { $0.vendorNamespace == "org.abandoned" })
        XCTAssertTrue(report.candidates.allSatisfy { $0.finding.confidence == 90 })
        XCTAssertFalse(report.candidates.contains { $0.finding.path.contains("dev.example") })
        XCTAssertFalse(report.candidates.contains { $0.finding.path.contains("Plain Vendor") })
    }

    func testSystemOverviewNormalizesTeamPrefixedServiceNamespaces() {
        let inspector = SystemOverviewInspector()

        XCTAssertEqual(
            inspector.vendorNamespace(for: "TEAM123456.com.adobe.ccxprocess"),
            "com.adobe"
        )
        XCTAssertEqual(
            inspector.vendorNamespace(for: "org.blenderfoundation.updater"),
            "org.blenderfoundation"
        )
        XCTAssertNil(inspector.vendorNamespace(for: "unstructured-helper-name"))
        XCTAssertTrue(inspector.isAppleIdentifier("application.com.apple.Finder.123"))
        XCTAssertFalse(inspector.isAppleIdentifier("com.adobe.Photoshop"))
        XCTAssertEqual(inspector.indexedSizeValues(from: "1469378734\0(null)\0407081348"), [
            1_469_378_734,
            407_081_348
        ])
        XCTAssertEqual(
            ApplicationSizeInspector().indexedSizeEntries(
                from: "1469378734\0(null)\0407081348",
                expectedCount: 3
            ),
            [1_469_378_734, nil, 407_081_348]
        )

        let applicationSpace = inspector.summarizeApplicationSpace(
            installedApplications: [
                InstalledApplication(
                    application: ApplicationIdentity(
                        path: "/Applications/Pixel.app",
                        name: "Pixel",
                        bundleIdentifier: "dev.example.pixel",
                        executableName: "Pixel",
                        version: "1"
                    ),
                    scope: .shared,
                    bundleByteSize: 100
                ),
                InstalledApplication(
                    application: ApplicationIdentity(
                        path: "/Applications/Notes.app",
                        name: "Notes",
                        bundleIdentifier: "dev.example.notes",
                        executableName: "Notes",
                        version: "1"
                    ),
                    scope: .shared
                ),
                InstalledApplication(
                    application: ApplicationIdentity(
                        path: "/System/Applications/Finder.app",
                        name: "Finder",
                        bundleIdentifier: "com.apple.finder",
                        executableName: "Finder",
                        version: "1"
                    ),
                    scope: .system,
                    bundleByteSize: 9_999
                )
            ]
        )
        XCTAssertEqual(applicationSpace.byteSize, 100)
        XCTAssertEqual(applicationSpace.indexedApplicationCount, 1)
        XCTAssertEqual(applicationSpace.externalApplicationCount, 2)
        XCTAssertNotNil(applicationSpace.warning)
    }

    func testPathCatalogCoversExtendedInstallationArtifacts() {
        let locations = PathCatalog.defaultLocations(homeDirectory: home)
        let kinds = Set(locations.map(\.kind))

        XCTAssertTrue(kinds.contains(.webData))
        XCTAssertTrue(kinds.contains(.framework))
        XCTAssertTrue(kinds.contains(.font))
        XCTAssertTrue(kinds.contains(.colorProfile))
        XCTAssertTrue(kinds.contains(.commandLineTool))
        XCTAssertTrue(kinds.contains(.shellIntegration))
        XCTAssertTrue(kinds.contains(.packageManagerRecord))
        XCTAssertTrue(kinds.contains(.driverExtension))
        XCTAssertTrue(locations.contains {
            $0.root.path == home.appendingPathComponent("Library/HTTPStorages").path
        })
        XCTAssertTrue(locations.contains {
            $0.root.path == "/Library/SystemExtensions" && !$0.removable
        })
    }

    func testLeftoverScannerRecognizesBrokenLaunchAgent() throws {
        let launchAgents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plist = launchAgents.appendingPathComponent("org.abandoned.updater.plist")
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        let value: [String: Any] = [
            "Label": "org.abandoned.updater",
            "Program": fixtureRoot.appendingPathComponent("missing/updater").path
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        try data.write(to: plist)

        let report = LeftoverScanner(
            locations: [
                SearchLocation(root: launchAgents, kind: .launchAgent, scope: .user, baseRisk: .high)
            ],
            homeDirectory: home,
            inspectRuntime: false
        ).scan(installedApplications: [])

        let candidate = try XCTUnwrap(report.candidates.first)
        XCTAssertEqual(candidate.finding.confidence, 95)
        XCTAssertEqual(candidate.finding.kind, .launchAgent)
        XCTAssertTrue(candidate.finding.reasons.contains { $0.contains("no longer exists") })
        XCTAssertFalse(candidate.finding.removable)
        XCTAssertTrue(LeftoverCleanupPlanner().makePlan(
            from: report,
            selectedIDs: [candidate.finding.id]
        ).selected.isEmpty)
    }

    func testLeftoverScannerNormalizesTeamPrefixesAndExcludesAppleAndInstalledVendors() throws {
        let groups = home.appendingPathComponent("Library/Group Containers", isDirectory: true)
        let scripts = home.appendingPathComponent("Library/Application Scripts", isDirectory: true)
        for name in [
            "TEAM123456.com.apple.iWork",
            "TEAM123456.com.openai.shared",
            "TEAM123456.com.abandoned.paint"
        ] {
            try FileManager.default.createDirectory(
                at: groups.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(
            at: scripts.appendingPathComponent("TEAM123456.com.abandoned.paint", isDirectory: true),
            withIntermediateDirectories: true
        )
        let openAI = try identity(name: "Chat App", bundleID: "com.openai.chat")
        let report = LeftoverScanner(
            locations: [
                SearchLocation(root: groups, kind: .groupContainer, scope: .user, baseRisk: .high),
                SearchLocation(root: scripts, kind: .applicationScript, scope: .user, baseRisk: .review)
            ],
            homeDirectory: home,
            inspectRuntime: false
        ).scan(installedApplications: [InstalledApplication(application: openAI, scope: .shared)])

        XCTAssertEqual(report.candidates.count, 2)
        XCTAssertTrue(report.candidates.allSatisfy {
            $0.suspectedIdentifier == "TEAM123456.com.abandoned.paint"
        })
        XCTAssertFalse(report.candidates.contains { $0.finding.path.contains("com.apple") })
        XCTAssertFalse(report.candidates.contains { $0.finding.path.contains("com.openai") })
    }

    func testLeftoverPlannerNeverSelectsActiveCandidate() throws {
        let finding = Finding(
            id: "active-service",
            path: "pid:42 /Applications/Missing.app/Contents/MacOS/Missing",
            kind: .process,
            scope: .runtime,
            risk: .high,
            confidence: 95,
            reasons: ["test active process"],
            removable: false,
            byteSize: nil,
            isDirectory: false,
            expectedFileID: nil,
            expectedDeviceID: nil
        )
        let report = LeftoverReport(
            installedApplicationCount: 0,
            candidates: [LeftoverCandidate(finding: finding, suspectedIdentifier: nil, active: true)]
        )

        let plan = LeftoverCleanupPlanner().makePlan(
            from: report,
            selectedIDs: [finding.id]
        )

        XCTAssertTrue(plan.selected.isEmpty)
        XCTAssertEqual(plan.items.first?.decision, "active services and processes are report-only")
    }

    func testLeftoverPlannerRequiresExactSelectionAndSystemOptIn() throws {
        let systemCaches = fixtureRoot.appendingPathComponent("Library/Caches", isDirectory: true)
        let systemLogs = fixtureRoot.appendingPathComponent("Library/Logs", isDirectory: true)
        let item = systemCaches.appendingPathComponent("org.abandoned.paint", isDirectory: true)
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: systemLogs.appendingPathComponent("org.abandoned.paint", isDirectory: true),
            withIntermediateDirectories: true
        )
        let report = LeftoverScanner(
            locations: [
                SearchLocation(root: systemCaches, kind: .cache, scope: .system, baseRisk: .high),
                SearchLocation(root: systemLogs, kind: .log, scope: .system, baseRisk: .high)
            ],
            homeDirectory: home,
            inspectRuntime: false
        ).scan(installedApplications: [])
        let candidate = try XCTUnwrap(report.candidates.first)
        let planner = LeftoverCleanupPlanner()

        XCTAssertTrue(planner.makePlan(from: report, selectedIDs: []).selected.isEmpty)
        XCTAssertTrue(planner.makePlan(
            from: report,
            selectedIDs: [candidate.finding.id]
        ).selected.isEmpty)
        XCTAssertEqual(planner.makePlan(
            from: report,
            selectedIDs: [candidate.finding.id],
            includeSystem: true
        ).selected.map(\.id), [candidate.finding.id])
    }

    func testSelectedLeftoverMovesToVaultAndRestores() throws {
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let logs = home.appendingPathComponent("Library/Logs", isDirectory: true)
        let item = caches.appendingPathComponent("org.abandoned.paint", isDirectory: true)
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: item.appendingPathComponent("entry"))
        try FileManager.default.createDirectory(
            at: logs.appendingPathComponent("org.abandoned.paint", isDirectory: true),
            withIntermediateDirectories: true
        )
        let locations = [
            SearchLocation(root: caches, kind: .cache, scope: .user, baseRisk: .safe),
            SearchLocation(root: logs, kind: .log, scope: .user, baseRisk: .safe)
        ]
        let report = LeftoverScanner(
            locations: locations,
            homeDirectory: home,
            inspectRuntime: false
        ).scan(installedApplications: [])
        let candidate = try XCTUnwrap(report.candidates.first)
        let plan = LeftoverCleanupPlanner().makePlan(
            from: report,
            selectedIDs: [candidate.finding.id]
        )
        let vault = fixtureRoot.appendingPathComponent("leftover-vault", isDirectory: true)
        let uninstallService = UninstallService(
            safetyPolicy: SafetyPolicy(
                locations: locations,
                applicationRoots: [applications],
                homeDirectory: home
            ),
            backupStore: BackupStore(root: vault, homeDirectory: home)
        )

        let result = try LeftoverCleanupService(uninstallService: uninstallService).execute(plan)

        XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))
        XCTAssertEqual(result.moved, [item.path])
        _ = try uninstallService.restore(id: result.backupID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
    }

    func testLocatorAndPolicySupportOneNestedApplicationFolder() throws {
        let suite = applications.appendingPathComponent("Adobe Photoshop 2026", isDirectory: true)
        let appURL = try makeApplication(
            name: "Adobe Photoshop 2026",
            bundleID: "com.adobe.Photoshop",
            directory: suite
        )
        let locator = ApplicationLocator(searchDirectories: [applications], homeDirectory: home)
        let app = try locator.locate("Adobe Photoshop 2026")

        XCTAssertEqual(app.path, appURL.path)
        let report = Scanner(locations: [], applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)
        let appFinding = try XCTUnwrap(report.findings.first { $0.kind == .applicationBundle })
        XCTAssertTrue(appFinding.removable)
        XCTAssertNoThrow(try SafetyPolicy(
            locations: [],
            applicationRoots: [applications],
            homeDirectory: home
        ).validate(appFinding, for: app))
    }

    func testMatcherRequiresProductEvidenceAndAvoidsVendorOnlyFolder() throws {
        let app = try identity(name: "Adobe Photoshop 2026", bundleID: "com.adobe.Photoshop")
        let matcher = Matcher()
        let vendorOnly = URL(fileURLWithPath: "/Library/Application Support/Adobe")
        let exact = URL(fileURLWithPath: "/Library/Caches/com.adobe.Photoshop")

        XCTAssertNil(matcher.evidence(for: vendorOnly, app: app, kind: .applicationSupport))
        XCTAssertEqual(matcher.evidence(for: exact, app: app, kind: .cache)?.confidence, 100)
    }

    func testFuzzyNameMatchIsDiscoveryOnly() throws {
        let app = try identity(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let fuzzy = cacheRoot.appendingPathComponent("Pixel Forge Old Data", isDirectory: true)
        try FileManager.default.createDirectory(at: fuzzy, withIntermediateDirectories: true)
        let location = SearchLocation(root: cacheRoot, kind: .cache, scope: .user, baseRisk: .safe)

        let report = Scanner(locations: [location], applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)
        let finding = try XCTUnwrap(report.findings.first { $0.path == fuzzy.path })

        XCTAssertEqual(finding.confidence, 80)
        XCTAssertEqual(finding.risk, .high)
        XCTAssertFalse(finding.removable)
    }

    func testMatcherRejectsAppleParsecNamespaceForThirdPartyParsec() {
        let app = ApplicationIdentity(
            path: "/Applications/Parsec.app",
            name: "Parsec",
            bundleIdentifier: "tv.parsec.www",
            executableName: "parsecd",
            version: "1"
        )
        let matcher = Matcher()

        XCTAssertNil(matcher.evidence(
            for: URL(fileURLWithPath: "/tmp/com.apple.parsecd"),
            app: app,
            kind: .cache
        ))
        XCTAssertNil(matcher.evidence(
            for: URL(fileURLWithPath: "/tmp/com.apple.siri.parsec.CoreParsec.plist"),
            app: app,
            kind: .preference
        ))
        XCTAssertNotNil(matcher.evidence(
            for: URL(fileURLWithPath: "/tmp/tv.parsec.www.plist"),
            app: app,
            kind: .preference
        ))
    }

    func testScannerReportsBoundedProgressLocations() throws {
        let app = try identity(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let location = SearchLocation(root: cacheRoot, kind: .cache, scope: .user, baseRisk: .safe)
        var messages: [String] = []

        let report = Scanner(
            locations: [location],
            applicationRoots: [applications],
            homeDirectory: home,
            inspectProcesses: false
        ).scan(app) { messages.append($0) }

        XCTAssertTrue(messages.contains { $0.contains("[1/10]") && $0.contains("login-item") })
        XCTAssertTrue(messages.contains { $0.contains("[10/10]") && $0.contains(cacheRoot.path) })
        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertEqual(report.coverage.locations.count, 10)
        XCTAssertEqual(report.coverage.inspectedLocationCount, 1)
        XCTAssertEqual(report.coverage.notPresentLocationCount, 9)
        XCTAssertEqual(report.coverage.supportedKinds.count, 7)
        XCTAssertFalse(report.coverage.unsupportedState.isEmpty)
    }

    func testCommandRunnerDrainsOutputLargerThanPipeBuffer() throws {
        let result = try CommandRunner().run(
            executable: "/usr/bin/jot",
            arguments: ["-b", "0123456789abcdef", "20000"]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertGreaterThan(result.standardOutput.count, 300_000)
    }

    func testCommandRunnerStopsTimedOutInspection() throws {
        let started = Date()

        let result = try CommandRunner().run(
            executable: "/bin/sleep",
            arguments: ["5"],
            timeout: 0.1
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testOptimizationParsersReportMountedImagesMemorySwapAndCPU() throws {
        let inspector = OptimizationInspector(
            fileManager: .default,
            homeDirectory: home,
            commandRunner: TestOptimizationCommandRunner(results: [:])
        )
        let plist: [String: Any] = [
            "images": [[
                "image-path": "/Users/tester/Downloads/Design Tool.dmg",
                "system-entities": [["mount-point": "/Volumes/Design Tool"]]
            ]]
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        XCTAssertEqual(
            inspector.parseMountedDiskImages(plistData: plistData),
            [MountedDiskImage(
                imagePath: "/Users/tester/Downloads/Design Tool.dmg",
                mountPoint: "/Volumes/Design Tool"
            )]
        )
        XCTAssertEqual(
            inspector.parseUsedMemory(
                vmStat: "Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free: 100.\nPages speculative: 20.\n",
                totalMemoryBytes: 10_000_000
            ),
            8_033_920
        )
        XCTAssertEqual(
            inspector.parseSwapUsed("total = 4096.00M  used = 1536.50M  free = 2559.50M"),
            1_611_137_024
        )
        XCTAssertEqual(
            inspector.parseHighCPUProcesses(" 92.5 123 /Applications/Test.app/Test\n 12.0 5 low", threshold: 80),
            ["/Applications/Test.app/Test · pid 123 · 92.5% CPU"]
        )
    }

    func testOptimizationExecutorRunsOnlyExactReviewedAction() throws {
        let key = TestOptimizationCommandRunner.key(
            "/usr/bin/qlmanage",
            ["-r", "cache"]
        )
        let runner = TestOptimizationCommandRunner(results: [
            key: CommandResult(terminationStatus: 0, standardOutput: Data(), timedOut: false)
        ])
        let action = OptimizationAction(
            id: "quicklook-cache",
            kind: .refreshQuickLookCache,
            title: "Refresh Quick Look cache",
            summary: "fixture",
            risk: .low,
            reason: "fixture"
        )

        let outcomes = try OptimizationExecutor(
            fileManager: .default,
            commandRunner: runner
        ).execute([action])

        XCTAssertEqual(outcomes.map(\.status), [.applied])
        XCTAssertEqual(runner.calls, [key])
    }

    func testOptimizationExecutorRevalidatesExactMountedImageBeforeDetach() throws {
        let target = "/Volumes/Design Tool"
        let plist: [String: Any] = [
            "images": [[
                "image-path": "/Users/tester/Downloads/Design Tool.dmg",
                "system-entities": [["mount-point": target]]
            ]]
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        let infoKey = TestOptimizationCommandRunner.key(
            "/usr/bin/hdiutil",
            ["info", "-plist"]
        )
        let detachKey = TestOptimizationCommandRunner.key(
            "/usr/bin/hdiutil",
            ["detach", target]
        )
        let runner = TestOptimizationCommandRunner(results: [
            infoKey: CommandResult(terminationStatus: 0, standardOutput: plistData, timedOut: false),
            detachKey: CommandResult(terminationStatus: 0, standardOutput: Data(), timedOut: false)
        ])
        let action = OptimizationAction(
            id: "detach-\(stableIdentifier(for: target))",
            kind: .detachDiskImage,
            title: "Detach Design Tool",
            summary: "fixture",
            risk: .disruptive,
            target: target,
            reason: "fixture"
        )

        let outcomes = try OptimizationExecutor(
            fileManager: .default,
            commandRunner: runner
        ).execute([action])

        XCTAssertEqual(outcomes.map(\.status), [.applied])
        XCTAssertEqual(runner.calls, [infoKey, detachKey])
    }

    func testOptimizationExecutorRejectsUnapprovedDetachTargetWithoutRunningCommand() throws {
        let target = "/tmp/not-a-volume"
        let runner = TestOptimizationCommandRunner(results: [:])
        let action = OptimizationAction(
            id: "detach-\(stableIdentifier(for: target))",
            kind: .detachDiskImage,
            title: "Unsafe fixture",
            summary: "fixture",
            risk: .disruptive,
            target: target,
            reason: "fixture"
        )

        let outcomes = try OptimizationExecutor(
            fileManager: .default,
            commandRunner: runner
        ).execute([action])

        XCTAssertEqual(outcomes.map(\.status), [.failed])
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testPermissionInspectorReturnsStructuredReadOnlyChecks() throws {
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let report = PermissionInspector(
            homeDirectory: home,
            locations: [SearchLocation(root: cacheRoot, kind: .cache, scope: .user, baseRisk: .safe)]
        ).inspect()

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.checks.count, 4)
        XCTAssertEqual(report.checks.first?.name, "User cleanup locations")
        XCTAssertEqual(report.checks.first?.status, .pass)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheRoot.path))
    }

    func testDefaultPlanKeepsReviewAndSystemItems() throws {
        let app = try identity(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let preferences = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        let plist = preferences.appendingPathComponent("dev.example.pixelforge.plist")
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: plist)
        let location = SearchLocation(root: preferences, kind: .preference, scope: .user, baseRisk: .review)
        let report = Scanner(locations: [location], applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)

        let defaultPlan = UninstallPlanner().makePlan(from: report)
        let expandedPlan = UninstallPlanner().makePlan(
            from: report,
            options: PlanOptions(includeReview: true, includeSystem: false)
        )

        XCTAssertFalse(defaultPlan.items.first { $0.finding.path == plist.path }!.selected)
        XCTAssertTrue(expandedPlan.items.first { $0.finding.path == plist.path }!.selected)
    }

    func testPlistProgramInsideAppProvidesStrongHelperEvidence() throws {
        let app = try identity(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let launchAgents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let helper = launchAgents.appendingPathComponent("org.vendor.background-helper.plist")
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": "org.vendor.background-helper",
            "ProgramArguments": [app.path + "/Contents/MacOS/Pixel Forge", "--background"]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: helper)
        let location = SearchLocation(root: launchAgents, kind: .launchAgent, scope: .user, baseRisk: .high)

        let report = Scanner(locations: [location], applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)
        let finding = try XCTUnwrap(report.findings.first { $0.path == helper.path })

        XCTAssertEqual(finding.confidence, 100)
        XCTAssertEqual(finding.risk, .high)
        XCTAssertTrue(finding.removable)
        XCTAssertFalse(UninstallPlanner().makePlan(from: report).items.first { $0.finding.path == helper.path }!.selected)
    }

    func testEmbeddedLoginAndBackgroundHelpersAreReportedButNotMovedSeparately() throws {
        let appURL = try makeApplication(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let loginItem = appURL.appendingPathComponent("Contents/Library/LoginItems/Pixel Helper.app", isDirectory: true)
        let backgroundHelper = appURL.appendingPathComponent("Contents/Library/LaunchServices/dev.example.helper")
        try FileManager.default.createDirectory(at: loginItem, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: backgroundHelper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("helper".utf8).write(to: backgroundHelper)
        let app = try ApplicationLocator(searchDirectories: [applications], homeDirectory: home).locate(appURL.path)

        let report = Scanner(locations: [], applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)
        let loginFinding = try XCTUnwrap(report.findings.first { $0.path == loginItem.path })
        let helperFinding = try XCTUnwrap(report.findings.first { $0.path == backgroundHelper.path })

        XCTAssertEqual(loginFinding.kind, .loginItem)
        XCTAssertEqual(helperFinding.kind, .backgroundHelper)
        XCTAssertEqual(loginFinding.confidence, 100)
        XCTAssertFalse(loginFinding.removable)
        XCTAssertFalse(helperFinding.removable)
    }

    func testEmbeddedXPCPluginsFrameworksAndStoreReceiptAreReported() throws {
        let appURL = try makeApplication(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let fixtures: [(String, FindingKind)] = [
            ("Contents/XPCServices/dev.example.worker.xpc", .backgroundHelper),
            ("Contents/PlugIns/dev.example.share.appex", .plugin),
            ("Contents/Frameworks/PixelKit.framework", .framework),
            ("Contents/_MASReceipt/receipt", .receipt)
        ]
        for (relativePath, _) in fixtures {
            let item = appURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: item.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("fixture".utf8).write(to: item)
        }
        let app = try ApplicationLocator(
            searchDirectories: [applications],
            homeDirectory: home
        ).locate(appURL.path)

        let report = Scanner(
            locations: [],
            applicationRoots: [applications],
            homeDirectory: home,
            inspectProcesses: false
        ).scan(app)

        for (relativePath, kind) in fixtures {
            let path = appURL.appendingPathComponent(relativePath).path
            let finding = try XCTUnwrap(report.findings.first { $0.path == path })
            XCTAssertEqual(finding.kind, kind)
            XCTAssertEqual(finding.confidence, 100)
            XCTAssertFalse(finding.removable)
        }
    }

    func testExactGroupContainerRemainsHighRiskAndOptIn() throws {
        let app = try identity(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let groups = home.appendingPathComponent("Library/Group Containers", isDirectory: true)
        let group = groups.appendingPathComponent("dev.example.pixelforge", isDirectory: true)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        let location = SearchLocation(root: groups, kind: .groupContainer, scope: .user, baseRisk: .high)
        let report = Scanner(locations: [location], applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)
        let finding = try XCTUnwrap(report.findings.first { $0.path == group.path })

        XCTAssertEqual(finding.risk, .high)
        XCTAssertFalse(UninstallPlanner().makePlan(from: report).items.first { $0.finding.path == group.path }!.selected)
        XCTAssertTrue(UninstallPlanner().makePlan(
            from: report,
            options: PlanOptions(includeReview: true)
        ).items.first { $0.finding.path == group.path }!.selected)
    }

    func testSafetyPolicyRejectsPathOutsideApprovedRoot() throws {
        let app = try identity(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let unrelated = home.appendingPathComponent("Documents/dev.example.pixelforge")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let attributes = try FileManager.default.attributesOfItem(atPath: unrelated.path)
        let finding = Finding(
            id: "manual",
            path: unrelated.path,
            kind: .cache,
            scope: .user,
            risk: .safe,
            confidence: 100,
            reasons: ["test"],
            removable: true,
            byteSize: nil,
            isDirectory: true,
            expectedFileID: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            expectedDeviceID: (attributes[.systemNumber] as? NSNumber)?.uint64Value
        )
        let policy = SafetyPolicy(locations: [
            SearchLocation(root: cacheRoot, kind: .cache, scope: .user, baseRisk: .safe)
        ], applicationRoots: [applications], homeDirectory: home)

        XCTAssertThrowsError(try policy.validate(finding, for: app))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testExecuteMovesToVaultAndRestoreReturnsEveryItem() throws {
        let appURL = try makeApplication(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let app = try ApplicationLocator(searchDirectories: [applications], homeDirectory: home).locate(appURL.path)
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let cache = cacheRoot.appendingPathComponent("dev.example.pixelforge", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cache.appendingPathComponent("entry"))
        let locations = [SearchLocation(root: cacheRoot, kind: .cache, scope: .user, baseRisk: .safe)]
        let report = Scanner(locations: locations, applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)
        let plan = UninstallPlanner().makePlan(from: report)
        let vault = fixtureRoot.appendingPathComponent("vault", isDirectory: true)
        let store = BackupStore(root: vault, homeDirectory: home)
        let service = UninstallService(
            safetyPolicy: SafetyPolicy(locations: locations, applicationRoots: [applications], homeDirectory: home),
            backupStore: store
        )

        let result = try service.execute(plan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(result.moved.count, 2)

        let restored = try service.restore(id: result.backupID)
        XCTAssertEqual(restored.moved.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }

    func testPermanentPurgeDeletesOnlyEligibleLocalItemsWithoutRollbackVault() throws {
        let appURL = try makeApplication(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let app = try ApplicationLocator(
            searchDirectories: [applications],
            homeDirectory: home
        ).locate(appURL.path)
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let preferences = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let groups = home.appendingPathComponent("Library/Group Containers", isDirectory: true)
        let cache = caches.appendingPathComponent("dev.example.pixelforge", isDirectory: true)
        let preference = preferences.appendingPathComponent("dev.example.pixelforge.plist")
        let supportData = support.appendingPathComponent("dev.example.pixelforge", isDirectory: true)
        let sharedGroup = groups.appendingPathComponent("dev.example.pixelforge", isDirectory: true)
        for directory in [cache, supportData, sharedGroup] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        try Data("preference".utf8).write(to: preference)
        let locations = [
            SearchLocation(root: caches, kind: .cache, scope: .user, baseRisk: .safe),
            SearchLocation(root: preferences, kind: .preference, scope: .user, baseRisk: .review),
            SearchLocation(root: support, kind: .applicationSupport, scope: .user, baseRisk: .review),
            SearchLocation(root: groups, kind: .groupContainer, scope: .user, baseRisk: .high)
        ]
        let report = Scanner(
            locations: locations,
            applicationRoots: [applications],
            homeDirectory: home,
            inspectProcesses: false
        ).scan(app)
        let defaultPlan = PermanentPurgePlanner().makePlan(from: report)
        let expandedPlan = PermanentPurgePlanner().makePlan(
            from: report,
            options: PurgeOptions(includeUserData: true)
        )

        XCTAssertEqual(Set(defaultPlan.selected.map(\.path)), Set([appURL.path, cache.path]))
        XCTAssertTrue(expandedPlan.selected.contains { $0.path == preference.path })
        XCTAssertTrue(expandedPlan.selected.contains { $0.path == supportData.path })
        XCTAssertFalse(expandedPlan.selected.contains { $0.path == sharedGroup.path })

        let result = try PermanentPurgeService(
            safetyPolicy: SafetyPolicy(
                locations: locations,
                applicationRoots: [applications],
                homeDirectory: home
            )
        ).execute(expandedPlan)

        XCTAssertEqual(result.deleted.count, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: preference.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportData.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedGroup.path))
    }

    func testPermanentPurgeAuthorizationFailureDeletesNothing() throws {
        let appURL = try makeApplication(name: "Admin App", bundleID: "dev.example.admin")
        let app = try ApplicationLocator(
            searchDirectories: [applications],
            homeDirectory: home
        ).locate(appURL.path)
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let cache = caches.appendingPathComponent("dev.example.admin", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let locations = [
            SearchLocation(root: caches, kind: .cache, scope: .user, baseRisk: .safe)
        ]
        let report = Scanner(
            locations: locations,
            applicationRoots: [applications],
            homeDirectory: home,
            inspectProcesses: false
        ).scan(app)
        let plan = PermanentPurgePlanner().makePlan(from: report)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: appURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: appURL.path)
        }
        let remover = TestPrivilegedApplicationRemover(failAuthorization: true)
        let service = PermanentPurgeService(
            safetyPolicy: SafetyPolicy(
                locations: locations,
                applicationRoots: [applications],
                homeDirectory: home
            ),
            privilegedApplicationRemover: remover,
            privilegedApplicationRoots: [applications]
        )

        let preflight = try service.preflight(plan)
        XCTAssertEqual(preflight.administratorRequiredPaths, [appURL.path])
        XCTAssertTrue(preflight.blockers.isEmpty)
        XCTAssertThrowsError(try service.execute(plan))
        XCTAssertEqual(remover.authorizationCount, 1)
        XCTAssertTrue(remover.removedPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }

    func testPermanentPurgePermissionBlockerDeletesNothing() throws {
        let appURL = try makeApplication(name: "Blocked App", bundleID: "dev.example.blocked")
        let app = try ApplicationLocator(
            searchDirectories: [applications],
            homeDirectory: home
        ).locate(appURL.path)
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let cache = caches.appendingPathComponent("dev.example.blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let locations = [
            SearchLocation(root: caches, kind: .cache, scope: .user, baseRisk: .safe)
        ]
        let report = Scanner(
            locations: locations,
            applicationRoots: [applications],
            homeDirectory: home,
            inspectProcesses: false
        ).scan(app)
        let plan = PermanentPurgePlanner().makePlan(from: report)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: cache.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.path)
        }
        let service = PermanentPurgeService(
            safetyPolicy: SafetyPolicy(
                locations: locations,
                applicationRoots: [applications],
                homeDirectory: home
            ),
            privilegedApplicationRemover: nil,
            privilegedApplicationRoots: [applications]
        )

        let preflight = try service.preflight(plan)
        XCTAssertEqual(preflight.blockers.map(\.path), [cache.path])
        XCTAssertTrue(preflight.administratorRequiredPaths.isEmpty)
        XCTAssertThrowsError(try service.execute(plan))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }

    func testPermanentPurgeUsesAuthorizedRemovalOnlyForApplicationBundle() throws {
        let appURL = try makeApplication(name: "Admin App", bundleID: "dev.example.admin")
        let app = try ApplicationLocator(
            searchDirectories: [applications],
            homeDirectory: home
        ).locate(appURL.path)
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let cache = caches.appendingPathComponent("dev.example.admin", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let locations = [
            SearchLocation(root: caches, kind: .cache, scope: .user, baseRisk: .safe)
        ]
        let report = Scanner(
            locations: locations,
            applicationRoots: [applications],
            homeDirectory: home,
            inspectProcesses: false
        ).scan(app)
        let plan = PermanentPurgePlanner().makePlan(from: report)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: appURL.path)
        let remover = TestPrivilegedApplicationRemover()
        let service = PermanentPurgeService(
            safetyPolicy: SafetyPolicy(
                locations: locations,
                applicationRoots: [applications],
                homeDirectory: home
            ),
            privilegedApplicationRemover: remover,
            privilegedApplicationRoots: [applications]
        )

        let result = try service.execute(plan)

        XCTAssertEqual(result.deleted.count, 2)
        XCTAssertEqual(remover.authorizationCount, 1)
        XCTAssertEqual(remover.removedPaths, [appURL.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    func testPermanentPurgeServiceRejectsCraftedSystemSelection() throws {
        let appURL = try makeApplication(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let app = try ApplicationLocator(
            searchDirectories: [applications],
            homeDirectory: home
        ).locate(appURL.path)
        let systemCaches = fixtureRoot.appendingPathComponent("Library/Caches", isDirectory: true)
        let candidate = systemCaches.appendingPathComponent("dev.example.pixelforge", isDirectory: true)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        let attributes = try FileManager.default.attributesOfItem(atPath: candidate.path)
        let finding = Finding(
            id: "crafted-system-selection",
            path: candidate.path,
            kind: .cache,
            scope: .system,
            risk: .review,
            confidence: 100,
            reasons: ["crafted test plan"],
            removable: true,
            byteSize: nil,
            isDirectory: true,
            expectedFileID: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            expectedDeviceID: (attributes[.systemNumber] as? NSNumber)?.uint64Value
        )
        let plan = UninstallPlan(
            application: app,
            items: [PlannedFinding(finding: finding, selected: true, decision: "crafted")]
        )
        let service = PermanentPurgeService(
            safetyPolicy: SafetyPolicy(
                locations: [
                    SearchLocation(root: systemCaches, kind: .cache, scope: .system, baseRisk: .high)
                ],
                applicationRoots: [applications],
                homeDirectory: home
            )
        )

        XCTAssertThrowsError(try service.execute(plan))
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.path))
    }

    func testPlanningIsDryRunAndDoesNotChangeFiles() throws {
        let appURL = try makeApplication(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let app = try ApplicationLocator(searchDirectories: [applications], homeDirectory: home).locate(appURL.path)
        let report = Scanner(locations: [], applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)

        _ = UninstallPlanner().makePlan(from: report)

        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
    }

    func testRestoreNeverOverwritesExistingOriginalPath() throws {
        let appURL = try makeApplication(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let app = try ApplicationLocator(searchDirectories: [applications], homeDirectory: home).locate(appURL.path)
        let report = Scanner(locations: [], applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)
        let plan = UninstallPlanner().makePlan(from: report)
        let vault = fixtureRoot.appendingPathComponent("vault", isDirectory: true)
        let service = UninstallService(
            safetyPolicy: SafetyPolicy(locations: [], applicationRoots: [applications], homeDirectory: home),
            backupStore: BackupStore(root: vault, homeDirectory: home)
        )
        let result = try service.execute(plan)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let restored = try service.restore(id: result.backupID)

        XCTAssertTrue(restored.moved.isEmpty)
        XCTAssertEqual(restored.skipped, [appURL.path])
        XCTAssertEqual(try service.restorePreview(id: result.backupID).status, .partial)
    }

    func testApplicationOutsideApprovedRootsIsReadOnly() throws {
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let appURL = try makeApplication(
            name: "Detached Copy",
            bundleID: "dev.example.detached",
            directory: downloads
        )
        let app = try ApplicationLocator(searchDirectories: [downloads], homeDirectory: home).locate(appURL.path)
        let report = Scanner(locations: [], applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)
        let finding = try XCTUnwrap(report.findings.first { $0.kind == .applicationBundle })

        XCTAssertEqual(finding.risk, .protected)
        XCTAssertFalse(finding.removable)
        XCTAssertFalse(UninstallPlanner().makePlan(from: report).items[0].selected)
    }

    func testEditedManifestCannotRedirectRestoreOutsideApprovedRoots() throws {
        let appURL = try makeApplication(name: "Pixel Forge", bundleID: "dev.example.pixelforge")
        let app = try ApplicationLocator(searchDirectories: [applications], homeDirectory: home).locate(appURL.path)
        let report = Scanner(locations: [], applicationRoots: [applications], homeDirectory: home, inspectProcesses: false).scan(app)
        let plan = UninstallPlanner().makePlan(from: report)
        let vault = fixtureRoot.appendingPathComponent("vault", isDirectory: true)
        let store = BackupStore(root: vault, homeDirectory: home)
        let service = UninstallService(
            safetyPolicy: SafetyPolicy(locations: [], applicationRoots: [applications], homeDirectory: home),
            backupStore: store
        )
        let result = try service.execute(plan)
        let original = try store.load(id: result.backupID)
        let item = try XCTUnwrap(original.items.first)
        let redirected = BackupItem(
            findingID: item.findingID,
            originalPath: home.appendingPathComponent("Documents/redirected.app").path,
            backupPath: item.backupPath,
            kind: item.kind,
            scope: item.scope,
            status: item.status,
            note: item.note
        )
        var edited = original
        edited.items = [redirected]
        try store.save(edited)

        XCTAssertThrowsError(try service.restore(id: result.backupID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: redirected.originalPath))
    }

    private func identity(name: String, bundleID: String) throws -> ApplicationIdentity {
        let appURL = try makeApplication(name: name, bundleID: bundleID)
        return try ApplicationLocator(searchDirectories: [applications], homeDirectory: home).locate(appURL.path)
    }

    @discardableResult
    private func makeApplication(name: String, bundleID: String, directory: URL? = nil) throws -> URL {
        let appURL = (directory ?? applications).appendingPathComponent("\(name).app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleDisplayName": name,
            "CFBundleName": name,
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": name,
            "CFBundleShortVersionString": "1.2.3"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return appURL
    }
}
