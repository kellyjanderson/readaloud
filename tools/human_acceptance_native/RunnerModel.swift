import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RunnerModel: ObservableObject {
    @Published private(set) var session: Session?
    @Published var selectedID: String?
    @Published private(set) var tester = ""
    @Published private(set) var results: [String: CaseResult] = [:]
    @Published private(set) var progress: String?
    @Published private(set) var notice: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var saving = false
    @Published private(set) var saveError: String?
    @Published private(set) var owningApp = false
    @Published private(set) var quittingApp = false
    @Published private(set) var activeID: String?

    private let checks = DispatchQueue(label: "readaloud.runner.checks", qos: .userInitiated)
    private let storage = DispatchQueue(label: "readaloud.runner.results", qos: .utility)
    private var operation: UUID?
    private var sessionURL: URL?
    private var resultsURL: URL?
    private var pendingSave: (Report, URL)?
    private var app: NSRunningApplication?
    private var processObservation: NSKeyValueObservation?
    private var promptOpen = false
    private var shouldExit = false
    private var allowQuitDespiteSaveError = false
    private var startedRunningAt: DispatchTime?
    weak var window: NSWindow?

    var busy: Bool { operation != nil }
    var sessionLocked: Bool { busy || activeID != nil }
    var canManageSession: Bool { !sessionLocked && !saving && !promptOpen }
    var canOpenSession: Bool { canManageSession && saveError == nil }
    var canRevealResults: Bool { resultsURL != nil && !busy && !promptOpen }
    var currentCase: TestCase? { session?.cases.first { $0.id == selectedID } }

    func result(for test: TestCase) -> CaseResult { results[test.id] ?? CaseResult(test) }

    func openSession(_ url: URL) {
        guard canOpenSession else { return }
        run("Verifying session…", work: {
            let sessionURL = fileURL(url.path)
            let session = try Session.read(sessionURL, deadline: .now() + 45)
            let resultsURL = session.resultsURL
            let report = FileManager.default.fileExists(atPath: resultsURL.path)
                ? try Report.read(resultsURL, session: session, nativeOnly: true) : nil
            return (sessionURL, session, resultsURL, report)
        }) { [weak self] sessionURL, session, resultsURL, report in
            guard let self else { return }
            self.sessionURL = sessionURL
            self.session = session
            self.resultsURL = resultsURL
            tester = report?.tester ?? ""
            results = Dictionary(uniqueKeysWithValues: (report?.results ?? []).map { ($0.id, $0) })
            selectedID = session.cases.first { self.result(for: $0).result == .incomplete }?.id
                ?? session.cases.first?.id
            saveError = nil
            notice = nil
        }
    }

    func chooseSession() {
        guard canOpenSession else { return }
        chooseJSON(title: "Open Test Session") { [weak self] url in self?.openSession(url) }
    }

    func begin(_ test: TestCase) {
        guard let session, !sessionLocked, !promptOpen else { return }
        if result(for: test).outcome != .incomplete {
            confirm("Start this test again?", "Starting again clears the recorded judgment for this test and keeps your notes.",
                    action: "Start Again") { [weak self] in self?.start(test, from: session) }
        } else {
            start(test, from: session)
        }
    }

    private func start(_ test: TestCase, from session: Session) {
        do {
            try requireClosed(bundleIdentifier: session.candidate.bundleIdentifier)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        activeID = test.id
        run("Verifying Read Aloud and the prepared files…", work: {
            let deadline: DispatchTime = .now() + 45
            let verified = try session.candidate.verify(deadline: deadline)
            try test.verifyFiles(deadline: deadline)
            return verified
        }, onFailure: { [weak self] in self?.activeID = nil }) { [weak self] verified in
            self?.launch(test, verified: verified, bundleIdentifier: session.candidate.bundleIdentifier)
        }
    }

    private func requireClosed(bundleIdentifier: String) throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard running.allSatisfy(\.isTerminated) else {
            throw RunnerError("A copy of this Read Aloud candidate is already running. Quit it before starting this test.")
        }
    }

    private func launch(_ test: TestCase, verified: Candidate.VerifiedApplication, bundleIdentifier: String) {
        do {
            try requireClosed(bundleIdentifier: bundleIdentifier)
        } catch {
            activeID = nil
            errorMessage = error.localizedDescription
            return
        }
        let request = UUID()
        operation = request
        progress = "Opening Read Aloud…"
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = test.arguments
        configuration.environment = test.environment
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, operation == request else { return }
            errorMessage = "Read Aloud is taking too long to open. The runner is waiting for macOS to report what happened."
        }
        NSWorkspace.shared.openApplication(at: verified.applicationURL, configuration: configuration) { [weak self] launched, error in
            DispatchQueue.main.async {
                guard let self, self.operation == request else { return }
                guard let launched else {
                    self.operation = nil
                    self.progress = nil
                    self.activeID = nil
                    self.errorMessage = error?.localizedDescription ?? "macOS did not open the verified Read Aloud candidate."
                    return
                }
                let bundleURL = launched.bundleURL
                let executableURL = launched.executableURL
                self.checks.async {
                    let sameBundle = bundleURL.map { fileURL($0.path).path } == verified.applicationURL.path
                    let sameExecutable = executableURL.map { fileURL($0.path).path } == verified.executableURL.path
                    DispatchQueue.main.async {
                        guard self.operation == request else { return }
                        self.operation = nil
                        self.progress = nil
                        guard sameBundle || sameExecutable else {
                            self.activeID = nil
                            self.errorMessage = "macOS reported a different application instead of the verified Read Aloud candidate."
                            return
                        }
                        let exactMatch = sameBundle && launched.bundleIdentifier == bundleIdentifier
                            && (executableURL == nil || sameExecutable)
                        let failure = error?.localizedDescription
                            ?? (exactMatch ? nil : "Read Aloud opened with a different identity than the one verified.")
                        self.track(launched, for: test, launchFailure: failure)
                    }
                }
            }
        }
    }

    private func track(_ launched: NSRunningApplication, for test: TestCase, launchFailure: String?) {
        app = launched
        owningApp = true
        errorMessage = launchFailure
        if launchFailure == nil {
            startedRunningAt = .now()
            var entry = result(for: test)
            entry.result = .incomplete
            entry.judgment = nil
            entry.startedAt = timestamp()
            entry.closedAt = nil
            entry.appClosed = false
            entry.origin = .native
            entry.closureEvidence = .pending
            results[test.id] = entry
            save()
        }
        processObservation = launched.observe(\.isTerminated, options: [.initial, .new]) { [weak self] observed, change in
            guard change.newValue == true else { return }
            DispatchQueue.main.async { self?.confirmExit(observed) }
        }
        if launched.isTerminated {
            confirmExit(launched)
        } else if let launchFailure {
            // The callback points to our application even though launch failed
            // verification. Keep ownership until its normal Quit completes.
            quitTestApp()
            errorMessage = [launchFailure, errorMessage].compactMap { $0 }.joined(separator: " ")
        }
    }

    func quitTestApp() {
        guard let app, !quittingApp else { return }
        if app.isTerminated {
            confirmExit(app)
            return
        }
        quittingApp = true
        errorMessage = nil
        let pid = app.processIdentifier
        if !app.terminate() {
            quittingApp = false
            errorMessage = "Could not request Quit. Switch to Read Aloud and use Command-Q."
            shouldExit = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, let app = self.app, app.processIdentifier == pid, quittingApp else { return }
            if app.isTerminated {
                confirmExit(app)
                return
            }
            quittingApp = false
            shouldExit = false
            errorMessage = "Read Aloud is still open. Check its window for a message, then quit it to continue."
        }
    }

    private func confirmExit(_ observed: NSRunningApplication) {
        guard app?.processIdentifier == observed.processIdentifier, observed.isTerminated,
              let activeID else { return }
        let recordedLaunch = startedRunningAt != nil
        let mayHaveExitedEarly = !quittingApp && startedRunningAt.map { $0 + 2 > .now() } == true
        processObservation = nil
        app = nil
        owningApp = false
        quittingApp = false
        self.activeID = nil
        startedRunningAt = nil
        if mayHaveExitedEarly {
            errorMessage = "Read Aloud closed just after opening. You can start this test again or record what happened."
        }
        notice = "Read Aloud is closed."
        if recordedLaunch, var entry = results[activeID] {
            entry.appClosed = true
            entry.closedAt = timestamp()
            entry.closureEvidence = .observedExit
            results[activeID] = entry
            save()
        } else {
            exitIfReady()
        }
    }

    func updateTester(_ value: String) {
        tester = value
        save()
    }

    func update(_ test: TestCase, notes: String? = nil, outcome: Outcome? = nil) {
        var entry = result(for: test)
        if entry.origin == nil { entry.origin = .native }
        if let notes { entry.notes = notes }
        if let outcome {
            entry.result = .incomplete
            entry.judgment = outcome == .incomplete ? nil : outcome
        }
        results[test.id] = entry
        save()
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) { notice = "Passage copied." }
    }

    func reveal(_ file: TestCase.File) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }

    func revealResults() {
        guard let resultsURL, canRevealResults else { return }
        let folder = resultsURL.deletingLastPathComponent()
        run("Opening results folder…", work: {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }) { [weak self] in
            if !NSWorkspace.shared.open(folder) { self?.errorMessage = "Could not open the results folder." }
        }
    }

    func prepare(_ action: TestCase.SetupAction) {
        guard let test = currentCase, let sessionURL, !busy else { return }
        run("Preparing the working sample…", work: {
            try action.prepare(in: test, sessionURL: sessionURL)
        }) { [weak self] in self?.notice = "The working sample is ready." }
    }

    func exportResults() {
        guard let session, let sessionURL, canManageSession else { return }
        let panel = NSSavePanel()
        panel.title = "Export Test Results"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "read-aloud-human-test.json"
        show(panel) { [weak self] url in
            guard let self else { return }
            let report = snapshot(session)
            run("Exporting results…", work: {
                try session.validateDestination(url, manifestURL: sessionURL)
                try report.write(fileURL(url.path))
            }) { [weak self] in self?.notice = "Results exported." }
        }
    }

    func importResults() {
        guard let session, let resultsURL, canManageSession else { return }
        chooseJSON(title: "Import Test Results") { [weak self] url in
            guard let self else { return }
            let current = snapshot(session)
            run("Checking imported results…", work: {
                guard fileURL(url.path) != resultsURL else {
                    throw RunnerError("Choose a separate report to import.")
                }
                return try Report.read(url, session: session, nativeOnly: false)
            }) { [weak self] incoming in self?.merge(incoming, current: current, url: resultsURL) }
        }
    }

    private func merge(_ incoming: Report, current: Report, url: URL) {
        let saved = Dictionary(uniqueKeysWithValues: current.results.map { ($0.id, $0) })
        let conflicts = incoming.results.filter { incomingEntry in
            guard let currentEntry = saved[incomingEntry.id] else { return false }
            return incomingEntry.hasEntry && currentEntry.hasEntry && !currentEntry.sameHumanEntry(as: incomingEntry)
        }
        let testerConflict = !tester.isEmpty && !incoming.tester.isEmpty && tester != incoming.tester
        let apply: (Bool) -> Void = { [weak self] replace in
            self?.applyImport(incoming, current: current, url: url, replace: replace)
        }
        if !conflicts.isEmpty || testerConflict {
            let titles = conflicts.map(\.title) + (testerConflict ? ["Tester name"] : [])
            confirm("Some results already exist", titles.joined(separator: ", "),
                    action: "Use Imported Values", alternative: "Keep Saved Values", choice: apply)
        } else {
            apply(false)
        }
    }

    private func applyImport(_ incoming: Report, current: Report, url: URL, replace: Bool) {
        let backup = url.deletingLastPathComponent().appendingPathComponent("results-before-import-\(UUID().uuidString).json")
        run("Backing up the current results…", work: {
            try current.write(backup)
        }) { [weak self] in
            guard let self else { return }
            for entry in incoming.results where entry.hasEntry {
                if replace || results[entry.id]?.hasEntry != true { results[entry.id] = entry }
            }
            if !incoming.tester.isEmpty && (replace || tester.isEmpty) { tester = incoming.tester }
            save()
            notice = "Imported results. A backup of your previous results is beside your results file."
        }
    }

    func retrySave() { save() }

    private func snapshot(_ session: Session) -> Report {
        Report(tester: tester, session: session, results: results)
    }

    private func save() {
        guard let session, let resultsURL else { return }
        pendingSave = (snapshot(session), resultsURL)
        saveNext()
    }

    private func saveNext() {
        guard !saving, let (report, url) = pendingSave else { return }
        pendingSave = nil
        saving = true
        // Keep one active write and at most one latest snapshot while the user types.
        storage.async { [weak self] in
            let result = Result { try report.write(url) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.saving = false
                switch result {
                case .success: self.saveError = nil
                case .failure(let error): self.saveError = "Could not save your results. \(error.localizedDescription)"
                }
                self.saveNext()
                self.exitIfReady()
            }
        }
    }

    func requestClose() -> Bool {
        if busy || promptOpen {
            if busy { notice = "Wait for the current operation to finish before closing." }
            return false
        }
        if owningApp {
            confirm("Quit Read Aloud and close the runner?",
                    "The runner will close after Read Aloud quits and your results are saved.",
                    action: "Quit Read Aloud") { [weak self] in
                self?.shouldExit = true
                self?.quitTestApp()
            }
            return false
        }
        if saving {
            shouldExit = true
            return false
        }
        if let saveError, !allowQuitDespiteSaveError {
            confirm("Close without saving?", saveError, action: "Close Without Saving") { [weak self] in
                self?.allowQuitDespiteSaveError = true
                NSApp.terminate(nil)
            }
            return false
        }
        return true
    }

    private func exitIfReady() {
        guard shouldExit, !saving, !owningApp else { return }
        shouldExit = false
        NSApp.terminate(nil)
    }

    private func run<Value>(_ label: String, work: @escaping () throws -> Value,
                            onFailure: (() -> Void)? = nil, receive: @escaping (Value) -> Void) {
        let request = UUID()
        operation = request
        errorMessage = nil
        notice = nil
        progress = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            guard let self, self.operation == request else { return }
            self.errorMessage = "The file operation is taking too long. The runner is waiting for it to finish safely."
        }
        checks.async { [weak self] in
            let result = Result(catching: work)
            DispatchQueue.main.async {
                guard let self, self.operation == request else { return }
                self.operation = nil
                self.progress = nil
                switch result {
                case .success(let value):
                    self.errorMessage = nil
                    receive(value)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    onFailure?()
                }
            }
        }
    }

    private func chooseJSON(title: String, chosen: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        show(panel, chosen: chosen)
    }

    private func show(_ panel: NSSavePanel, chosen: @escaping (URL) -> Void) {
        guard let window, canManageSession else { return }
        promptOpen = true
        panel.beginSheetModal(for: window) { [weak self] response in
            self?.promptOpen = false
            if response == .OK, let url = panel.url { chosen(url) }
        }
    }

    private func confirm(_ title: String, _ explanation: String, action: String,
                         alternative: String? = nil, choice: @escaping (Bool) -> Void) {
        guard let window, !promptOpen else { return }
        promptOpen = true
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = explanation
        alert.addButton(withTitle: alternative ?? "Cancel")
        alert.addButton(withTitle: action)
        if alternative != nil { alert.addButton(withTitle: "Cancel") }
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.promptOpen = false
            if response == .alertSecondButtonReturn { choice(true) }
            if response == .alertFirstButtonReturn, alternative != nil { choice(false) }
        }
    }

    private func confirm(_ title: String, _ explanation: String, action: String,
                         confirmed: @escaping () -> Void) {
        confirm(title, explanation, action: action) { proceed in if proceed { confirmed() } }
    }
}
