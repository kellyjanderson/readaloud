import AppKit
import SwiftUI

@MainActor
private struct RunnerView: View {
    @ObservedObject var model: RunnerModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 200, idealWidth: 226, maxWidth: 300)
                detail.frame(minWidth: 375, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            status
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Text(model.session?.title ?? "Read Aloud User Tests")
                .font(.headline).lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            Button("Open Session…", action: model.chooseSession)
                .disabled(!model.canOpenSession)
            Menu("Results") {
                Button("Import Results…", action: model.importResults)
                    .disabled(!model.canManageSession)
                Button("Export Results…", action: model.exportResults)
                    .disabled(!model.canManageSession)
                Button("Show Results Folder", action: model.revealResults)
                    .disabled(!model.canRevealResults)
            }
            .disabled(model.session == nil)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session = model.session {
                let finished = session.cases.filter { model.result(for: $0).canonical(for: $0).result != .incomplete }.count
                Text("\(finished) of \(session.cases.count) results recorded")
                    .font(.subheadline.weight(.medium)).padding(12)
                List(selection: $model.selectedID) {
                    ForEach(session.cases) { test in
                        let entry = model.result(for: test)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(test.title).fixedSize(horizontal: false, vertical: true)
                            Text(model.activeID == test.id ? "In progress" : entry.canonical(for: test).result.status)
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(test.id)
                    }
                }
                .listStyle(.sidebar)
                .disabled(model.sessionLocked)
                Divider()
                TextField("Tester name (optional)", text: Binding(get: { model.tester }, set: { model.updateTester($0) }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Tester name (optional)")
                    .disabled(model.busy)
                    .padding(12)
            } else {
                Text("Tests").font(.headline).padding(12)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let test = model.currentCase {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button("Start Test") { model.begin(test) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.sessionLocked)
                    Button("Quit Read Aloud", action: model.quitTestApp)
                        .disabled(!model.owningApp || model.quittingApp)
                    if let passage = test.clipboardText {
                        Button("Copy Passage") { model.copy(passage) }
                    }
                    Spacer()
                }
                .padding(.horizontal, 22).padding(.vertical, 12)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(test.title).font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Text(test.question).font(.title3)
                        section("What to do") {
                            ForEach(Array(test.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(index + 1).").monospacedDigit()
                                    Text(step).fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        let files = test.files.filter { $0.label != "Coordinator reference (no action needed)" }
                        let actions = test.setupActions ?? []
                        if !files.isEmpty || !actions.isEmpty {
                            section("Test files") {
                                ForEach(actions, id: \.label) { action in
                                    Button(action.label) { model.prepare(action) }
                                        .disabled(model.busy)
                                }
                                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                                    HStack {
                                        Text(file.label).fixedSize(horizontal: false, vertical: true)
                                        Spacer()
                                        Button("Show in Finder") { model.reveal(file) }
                                            .accessibilityLabel("Show \(file.label) in Finder")
                                    }
                                }
                            }
                        }
                        section("What to look for") {
                            Text(test.expected)
                        }
                        Divider()
                        section("Your judgment") {
                            Picker("How did it go?", selection: Binding(
                                get: { model.result(for: test).outcome },
                                set: { model.update(test, outcome: $0) }
                            )) {
                                ForEach(Outcome.allCases) { outcome in
                                    Text(outcome.label).tag(outcome)
                                }
                            }
                            Text("Notes (optional)").font(.subheadline)
                            TextEditor(text: Binding(get: { model.result(for: test).notes },
                                                     set: { model.update(test, notes: $0) }))
                                .font(.body)
                                .frame(minHeight: 84)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.35)))
                                .accessibilityLabel("Test notes")
                        }
                        .disabled(model.busy)
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(test.id)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose a test session").font(.title)
                    .accessibilityAddTraits(.isHeader)
                Text("Open the native-session.json file supplied with your test app.")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(22)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if model.progress != nil || model.quittingApp {
                    ProgressView().controlSize(.small).padding(.trailing, 2)
                }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundColor(.primary)
                } else {
                    Text(model.progress ?? (model.quittingApp ? "Waiting for Read Aloud to quit…" : model.notice)
                         ?? (model.owningApp ? "Read Aloud is open." : "Ready."))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 12)
                if model.saving { Text("Saving…").foregroundColor(.secondary) }
            }
            if let saveError = model.saveError {
                HStack {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("Retry Save", action: model.retrySave)
                }
            }
        }
        .font(.callout)
        .frame(minHeight: 24, alignment: .center)
        .padding(.horizontal, 18).padding(.vertical, 7)
    }
}

@MainActor
private final class RunnerApplication: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = RunnerModel()
    let sessionURL: URL?
    private var window: NSWindow?

    init(sessionURL: URL?) { self.sessionURL = sessionURL }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenus()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Read Aloud User Tests"
        window.contentMinSize = NSSize(width: 620, height: 460)
        window.contentView = NSHostingView(rootView: RunnerView(model: model))
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        model.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let bundleURL = Bundle.main.bundleURL
        if let sessionURL {
            model.openSession(sessionURL)
        } else if bundleURL.pathExtension == "app" {
            model.openSession(bundleURL.deletingLastPathComponent().appendingPathComponent("native-session.json"))
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { model.requestClose() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.requestClose() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func installMenus() {
        let menuBar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Read Aloud User Tests", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menuBar.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menuBar.addItem(editItem)
        NSApp.mainMenu = menuBar
    }
}

@main
struct RunnerMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.first == "--validate" {
            guard arguments.count == 2, let path = arguments.last else {
                fputs("Usage: ReadAloudUserTests --validate SESSION.json\n", stderr)
                exit(2)
            }
            do {
                let deadline: DispatchTime = .now() + 60
                let session = try Session.read(URL(fileURLWithPath: path), deadline: deadline)
                for test in session.cases { try test.verifyFiles(deadline: deadline) }
                print("Verified candidate and \(session.cases.count) test cases.")
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        var sessionURL: URL?
        if arguments.first == "--session" {
            guard arguments.count == 2, let path = arguments.last, absoluteFilePath(path) else {
                fputs("Usage: ReadAloudUserTests --session /absolute/SESSION.json\n", stderr)
                exit(2)
            }
            sessionURL = URL(fileURLWithPath: path)
        }
        let delegate = RunnerApplication(sessionURL: sessionURL)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
