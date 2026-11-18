import CryptoKit
import Foundation

struct RunnerError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Candidate: Codable {
    let appPath: String
    let bundleIdentifier: String
    let sourceRevision: String
    let packageSha256: String
    let packageManifestPath: String
    let binaryPath: String
    let binarySha256: String

    var url: URL { fileURL(appPath) }
    var reportApp: Report.AppIdentity {
        .init(path: appPath, sourceRevision: sourceRevision, packageSha256: packageSha256)
    }

    func verify(deadline: DispatchTime) throws {
        let prefix = "com.kellyjanderson.readAloud.qa."
        guard bundleIdentifier.hasPrefix(prefix), isHex(String(bundleIdentifier.dropFirst(prefix.count)), 32),
              isHex(sourceRevision, 40), absoluteFilePath(appPath), url.pathExtension == "app",
              Bundle(url: url)?.bundleIdentifier == bundleIdentifier else {
            throw RunnerError("The Read Aloud app does not match the QA profile specified by this session.")
        }
        let framework = url.appendingPathComponent("Contents/Frameworks/App.framework")
        let expectedBinary = fileURL(framework.appendingPathComponent("App").path)
        guard fileURL(binaryPath) == expectedBinary, expectedBinary.path.hasPrefix(framework.path + "/") else {
            throw RunnerError("The session points to a binary outside the expected App.framework.")
        }
        try verifyHash(packageManifestPath, packageSha256, label: "Candidate manifest", deadline: deadline)
        try verifyHash(binaryPath, binarySha256, label: "Read Aloud binary", deadline: deadline)
    }
}

struct Fixture: Codable, Equatable {
    let id: String
    let sha256: String
}

struct TestCase: Codable, Identifiable {
    struct File: Codable {
        let label: String
        let path: String
        let sha256: String?
    }
    struct SetupAction: Codable {
        let label: String
        let sourcePath: String
        let targetPath: String
        let sha256: String

        @discardableResult
        func validate(in test: TestCase, sessionURL: URL) throws -> (source: URL, target: URL) {
            let directory = sessionURL.deletingLastPathComponent().appendingPathComponent("fixtures/imports")
            let source = fileURL(sourcePath)
            let target = fileURL(targetPath)
            guard absoluteFilePath(sourcePath), absoluteFilePath(targetPath),
                  source.pathExtension == "docx", source.deletingLastPathComponent().path == directory.path,
                  target.path == directory.appendingPathComponent("recovery-working.docx").path,
                  source != target, isHex(sha256, 64),
                  test.files.contains(where: { $0.path == sourcePath && $0.sha256 == sha256 }),
                  test.files.contains(where: { $0.path == targetPath && $0.sha256 == nil }) else {
                throw RunnerError("The recovery action must copy a provided DOCX to the session's working sample.")
            }
            return (source, target)
        }

        func prepare(in test: TestCase, sessionURL: URL) throws {
            let paths = try validate(in: test, sessionURL: sessionURL)
            try requireRegularFile(paths.source.path)
            try requireRegularFile(paths.target.path)
            let source = try FileHandle(forReadingFrom: paths.source)
            defer { try? source.close() }
            let limit = 16 * 1024 * 1024
            let data = try source.read(upToCount: limit + 1) ?? Data()
            guard data.count <= limit, hexDigest(SHA256.hash(data: data)) == sha256 else {
                throw RunnerError("The supplied DOCX has changed or exceeds the size limit.")
            }
            try data.write(to: paths.target, options: .atomic)
        }
    }
    let id: String
    let title: String
    let issue: Int
    let question: String
    let steps: [String]
    let expected: String
    let arguments: [String]
    let environment: [String: String]
    let files: [File]
    let clipboardText: String?
    let fixtureId: String?
    let fixtureSha256: String?
    let setupActions: [SetupAction]?

    var fixture: Fixture? {
        guard let fixtureId, let fixtureSha256 else { return nil }
        return Fixture(id: fixtureId, sha256: fixtureSha256)
    }

    func validate(sessionURL: URL) throws {
        // Restrict this tool to ordinary GUI document intake and the coordinator's
        // supported runtime settings. The candidate chooses its own QA container.
        let positional = arguments.first == "--" ? arguments.dropFirst() : arguments[...]
        guard positional.allSatisfy({ path in files.contains { $0.path == path } }),
              files.allSatisfy({ absoluteFilePath($0.path) && ($0.sha256.map { isHex($0, 64) } ?? true) }) else {
            throw RunnerError("\(title) must use declared local files as launch arguments.")
        }
        let launchKeys = Set(["READALOUD_TTS_ENGINE", "HF_HUB_OFFLINE"])
        for (key, value) in environment {
            guard launchKeys.contains(key), !value.contains("\0") else {
                throw RunnerError("\(title) contains an unsupported launch setting (\(key)).")
            }
        }
        guard (fixtureId == nil) == (fixtureSha256 == nil),
              fixture.map({ identity in !identity.id.isEmpty && files.contains { $0.sha256 == identity.sha256 } }) ?? true else {
            throw RunnerError("\(title) has inconsistent fixture identity.")
        }
        let actions = setupActions ?? []
        guard Set(actions.map(\.label)).count == actions.count else {
            throw RunnerError("\(title) has duplicate preparation actions.")
        }
        for action in actions { try action.validate(in: self, sessionURL: sessionURL) }
    }

    func verifyFiles(deadline: DispatchTime) throws {
        for file in files {
            do {
                if let sha256 = file.sha256 {
                    try verifyHash(file.path, sha256, label: file.label, deadline: deadline)
                } else {
                    try requireRegularFile(file.path)
                }
            } catch {
                throw RunnerError("\(title) • \(file.label): \(error.localizedDescription)")
            }
        }
    }
}

struct Session: Codable {
    let schema: Int
    let title: String
    let resultsPath: String
    let candidate: Candidate
    let cases: [TestCase]

    var resultsURL: URL { fileURL(resultsPath) }

    static func read(_ url: URL, deadline: DispatchTime) throws -> Session {
        let session = try JSONDecoder().decode(Self.self, from: readJSON(url))
        guard session.schema == 1, !session.cases.isEmpty,
              session.cases.allSatisfy({ !$0.id.isEmpty }),
              Set(session.cases.map(\.id)).count == session.cases.count else {
            throw RunnerError("This file does not describe a supported test session with unique case IDs.")
        }
        try session.validateDestination(session.resultsURL, manifestURL: url)
        for test in session.cases { try test.validate(sessionURL: fileURL(url.path)) }
        try session.candidate.verify(deadline: deadline)
        return session
    }

    func validateDestination(_ url: URL, manifestURL: URL) throws {
        let protected = [manifestURL.path, candidate.packageManifestPath, candidate.binaryPath] + cases.flatMap {
            $0.files.map(\.path)
        }
        let destination = fileURL(url.path)
        guard absoluteFilePath(resultsPath), destination.pathExtension == "json",
              !protected.map(fileURL).contains(destination),
              !destination.path.hasPrefix(candidate.url.path + "/") else {
            throw RunnerError("Choose a separate JSON file for results.")
        }
    }
}

enum Outcome: String, Codable, CaseIterable, Identifiable {
    case incomplete, worked, problem, skip
    var id: Self { self }

    var label: String {
        switch self {
        case .incomplete: return "Incomplete"
        case .worked: return "It worked for me"
        case .problem: return "I noticed a problem"
        case .skip: return "Skip this test"
        }
    }

    var status: String {
        switch self {
        case .incomplete: return "Incomplete"
        case .worked: return "Worked"
        case .problem: return "Problem noted"
        case .skip: return "Skipped"
        }
    }
}

struct CaseResult: Codable, Equatable {
    let id: String
    let title: String
    let issue: Int
    let fixture: Fixture?
    var result: Outcome
    var notes: String
    var appClosed: Bool
    var startedAt: String?
    var closedAt: String?
    // Keep a tester's judgment through relaunch or interrupted cleanup. Export
    // the outcome as incomplete until the launch's process has really exited.
    var judgment: Outcome?

    init(_ test: TestCase) {
        id = test.id
        title = test.title
        issue = test.issue
        fixture = test.fixture
        result = .incomplete
        notes = ""
        appClosed = false
    }

    var outcome: Outcome { judgment ?? result }
    var hasEntry: Bool { outcome != .incomplete || !notes.isEmpty || startedAt != nil || appClosed }

    func canonical(for test: TestCase) -> Self {
        var entry = CaseResult(test)
        entry.notes = notes
        entry.startedAt = startedAt
        entry.closedAt = closedAt
        entry.appClosed = appClosed
        entry.judgment = outcome == .incomplete ? nil : outcome
        if appClosed || (outcome == .skip && startedAt == nil) { entry.result = outcome }
        return entry
    }

    func sameHumanEntry(as other: Self) -> Bool {
        outcome == other.outcome && notes == other.notes && appClosed == other.appClosed
    }
}

struct Report: Codable {
    struct AppIdentity: Codable {
        let path: String
        let sourceRevision: String
        let packageSha256: String
    }
    let schema: Int
    let exportedAt: String
    var tester: String
    let app: AppIdentity
    var results: [CaseResult]
    let runner: String?

    init(tester: String, session: Session, results: [String: CaseResult]) {
        schema = 3
        exportedAt = timestamp()
        self.tester = tester
        app = session.candidate.reportApp
        self.results = session.cases.map { (results[$0.id] ?? CaseResult($0)).canonical(for: $0) }
        runner = "readaloud-native"
    }

    static func read(_ url: URL, session: Session, nativeOnly: Bool) throws -> Report {
        var report = try JSONDecoder().decode(Self.self, from: readJSON(url))
        let candidate = session.candidate
        guard report.schema == 3, report.app.sourceRevision == candidate.sourceRevision,
              report.app.packageSha256 == candidate.packageSha256 else {
            throw RunnerError("These results belong to a different Read Aloud candidate.")
        }
        guard !nativeOnly || report.runner == "readaloud-native" else {
            throw RunnerError("The session's results file already exists. Move it aside or use a separate native results path before importing it.")
        }
        let cases = Dictionary(uniqueKeysWithValues: session.cases.map { ($0.id, $0) })
        guard Set(report.results.map(\.id)).count == report.results.count else {
            throw RunnerError("These results contain duplicate test IDs.")
        }
        report.results = try report.results.map { entry in
            guard let test = cases[entry.id], test.issue == entry.issue, test.fixture == entry.fixture else {
                throw RunnerError("The saved result for \(entry.id) does not match this session's test and fixture.")
            }
            return entry.canonical(for: test)
        }
        return report
    }

    func write(_ url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(self)
        guard data.count <= maxJSONSize else { throw RunnerError("The results exceed 4 MB.") }
        try data.write(to: url, options: .atomic)
    }
}

func timestamp() -> String { ISO8601DateFormatter().string(from: .now) }

func absoluteFilePath(_ path: String) -> Bool { path.hasPrefix("/") && !path.contains("\0") }

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
}

func isHex(_ value: String, _ count: Int) -> Bool {
    value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}

func requireRegularFile(_ path: String) throws {
    guard absoluteFilePath(path),
          try fileURL(path).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
          FileManager.default.isReadableFile(atPath: path) else {
        throw RunnerError("Missing or unreadable file at \(path)")
    }
}

private let maxJSONSize = 4 * 1024 * 1024

func readJSON(_ url: URL) throws -> Data {
    try requireRegularFile(url.path)
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let data = try file.read(upToCount: maxJSONSize + 1) ?? Data()
    guard data.count <= maxJSONSize else { throw RunnerError("The JSON file exceeds 4 MB.") }
    return data
}

func verifyHash(_ path: String, _ sha256: String, label: String, deadline: DispatchTime) throws {
    guard isHex(sha256, 64) else { throw RunnerError("\(label) has an invalid SHA-256.") }
    try requireRegularFile(path)
    let file = try FileHandle(forReadingFrom: fileURL(path))
    defer { try? file.close() }
    var digest = SHA256()
    while true {
        guard DispatchTime.now() < deadline else {
            throw RunnerError("Verification took too long while reading \(label).")
        }
        guard let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
        digest.update(data: chunk)
    }
    let actual = hexDigest(digest.finalize())
    guard actual == sha256 else { throw RunnerError("\(label) changed. Its SHA-256 differs from this session.") }
}

private func hexDigest(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
}
