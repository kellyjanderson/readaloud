import CryptoKit
import Darwin
import Foundation

struct RunnerError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Candidate: Codable {
    struct VerifiedApplication {
        let applicationURL: URL
        let executableURL: URL
    }

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

    @discardableResult
    func verify(deadline: DispatchTime) throws -> VerifiedApplication {
        let prefix = "com.kellyjanderson.readAloud.qa."
        let app = url
        guard bundleIdentifier.hasPrefix(prefix), isHex(String(bundleIdentifier.dropFirst(prefix.count)), 32),
              isHex(sourceRevision, 40), absoluteFilePath(appPath), app.pathExtension == "app" else {
            throw RunnerError("The Read Aloud app does not match the QA profile specified by this session.")
        }
        let framework = app.appendingPathComponent("Contents/Frameworks/App.framework")
        let expectedBinary = fileURL(framework.appendingPathComponent("App").path)
        guard fileURL(binaryPath) == expectedBinary, expectedBinary.path.hasPrefix(framework.path + "/") else {
            throw RunnerError("The session points to a binary outside the expected App.framework.")
        }
        guard DispatchTime.now() < deadline else { throw RunnerError("Candidate verification took too long.") }
        try requireRegularFile(packageManifestPath)
        let manifest = try readSmallFile(fileURL(packageManifestPath))
        guard hexDigest(SHA256.hash(data: manifest)) == packageSha256 else {
            throw RunnerError("Candidate manifest changed. Its SHA-256 differs from this session.")
        }
        let receipt = try JSONDecoder().decode(PackageReceipt.self, from: manifest)
        let bundle = receipt.build.bundle
        guard receipt.schema == 3, receipt.build.inputs.source.commit == sourceRevision,
              bundle.bundleIdentifier == bundleIdentifier else {
            throw RunnerError("The candidate manifest's source revision or QA profile does not match this session.")
        }
        try bundle.verify(in: app, binary: expectedBinary, binarySha256: binarySha256, deadline: deadline)
        return VerifiedApplication(applicationURL: app, executableURL: app.appendingPathComponent(bundle.executable))
    }
}

private struct PackageReceipt: Decodable {
    struct Build: Decodable {
        struct Inputs: Decodable {
            struct Source: Decodable { let commit: String }
            let source: Source
        }
        let inputs: Inputs
        let bundle: AppBundle
    }

    struct AppBundle: Decodable {
        struct Entry: Decodable {
            let path: String
            let symlink: String?
            let sha256: String?
            let size: Int64?
            let mode: Int?

            func verify(_ url: URL, in app: URL, deadline: DispatchTime) throws {
                let failure = RunnerError("Read Aloud package changed at \(path).")
                if let symlink {
                    let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                    let resolved = url.resolvingSymlinksInPath()
                    guard sha256 == nil, size == nil, mode == nil, target == symlink,
                          resolved.path != url.path, resolved.path.hasPrefix(app.path + "/"),
                          FileManager.default.fileExists(atPath: resolved.path) else { throw failure }
                } else {
                    // Read and inspect the same descriptor, with symlink following disabled.
                    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                    guard descriptor >= 0 else { throw failure }
                    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                    defer { try? file.close() }
                    var info = stat()
                    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                          Int(info.st_mode) & 0o777 == mode, info.st_size == size,
                          try streamDigest(file, label: path, deadline: deadline) == sha256 else { throw failure }
                }
            }
        }

        let bundleIdentifier: String
        let executable: String
        let files: [Entry]

        enum CodingKeys: String, CodingKey {
            case bundleIdentifier = "bundle_identifier"
            case executable, files
        }

        func verify(in app: URL, binary: URL, binarySha256: String, deadline: DispatchTime) throws {
            var expected: [String: Entry] = [:]
            for file in files {
                guard expected.updateValue(file, forKey: file.path) == nil else {
                    throw RunnerError("The candidate manifest contains duplicate package files.")
                }
            }
            let binaryRelativePath = String(binary.path.dropFirst(app.path.count + 1))
            let executableName = String(executable.dropFirst("Contents/MacOS/".count))
            guard let binaryEntry = expected[binaryRelativePath], binaryEntry.symlink == nil,
                  isHex(binarySha256, 64), binaryEntry.sha256 == binarySha256,
                  executable.hasPrefix("Contents/MacOS/"), !executableName.isEmpty, !executableName.contains("/"),
                  let launcher = expected[executable], launcher.symlink == nil,
                  let infoEntry = expected["Contents/Info.plist"], infoEntry.symlink == nil else {
                throw RunnerError("The candidate manifest does not match the session's Read Aloud binaries.")
            }

            let traversalKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
            var directories = [""]
            while let directory = directories.popLast() {
                let url = directory.isEmpty ? app : app.appendingPathComponent(directory)
                for item in try FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: Array(traversalKeys)
                ) {
                    guard DispatchTime.now() < deadline else { throw RunnerError("Candidate verification took too long.") }
                    let path = directory.isEmpty ? item.lastPathComponent : directory + "/" + item.lastPathComponent
                    let values = try item.resourceValues(forKeys: traversalKeys)
                    if values.isDirectory == true, values.isSymbolicLink != true {
                        directories.append(path)
                        continue
                    }
                    guard let entry = expected.removeValue(forKey: path) else {
                        throw RunnerError("Read Aloud package contains an unexpected file at \(path).")
                    }
                    try entry.verify(app.appendingPathComponent(path), in: app, deadline: deadline)
                }
            }
            if let missing = expected.keys.sorted().first {
                throw RunnerError("Read Aloud package is missing \(missing).")
            }

            let plist = try readSmallFile(app.appendingPathComponent("Contents/Info.plist"))
            let info = try PropertyListSerialization.propertyList(from: plist, options: [], format: nil) as? [String: Any]
            guard info?["CFBundleIdentifier"] as? String == bundleIdentifier,
                  info?["CFBundleExecutable"] as? String == executableName else {
                throw RunnerError("Read Aloud's launch metadata differs from the candidate manifest.")
            }
        }
    }

    let schema: Int
    let build: Build
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
        let session = try JSONDecoder().decode(Self.self, from: readSmallFile(url))
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
    enum Origin: String, Codable {
        case native, browser
    }

    enum ClosureEvidence: String, Codable {
        case pending
        case observedExit = "observed-exit"
        case testerAttestation = "tester-attestation"
    }

    let id: String
    let title: String
    let issue: Int
    let fixture: Fixture?
    var result: Outcome
    var notes: String
    var appClosed: Bool
    var startedAt: String?
    var closedAt: String?
    var origin: Origin?
    var closureEvidence: ClosureEvidence?
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
        entry.origin = origin
        entry.closureEvidence = closureEvidence
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
        var report = try JSONDecoder().decode(Self.self, from: readSmallFile(url))
        let candidate = session.candidate
        guard report.schema == 3, report.app.sourceRevision == candidate.sourceRevision,
              report.app.packageSha256 == candidate.packageSha256 else {
            throw RunnerError("These results belong to a different Read Aloud candidate.")
        }
        let nativeReport = report.runner == "readaloud-native"
        guard !nativeOnly || nativeReport else {
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
            var result = entry.canonical(for: test)
            if !nativeReport, result.hasEntry {
                result.origin = .browser
                result.closureEvidence = result.appClosed ? .testerAttestation : nil
            }
            return result
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

private func readSmallFile(_ url: URL) throws -> Data {
    try requireRegularFile(url.path)
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let data = try file.read(upToCount: maxJSONSize + 1) ?? Data()
    guard data.count <= maxJSONSize else { throw RunnerError("\(url.lastPathComponent) exceeds 4 MB.") }
    return data
}

func verifyHash(_ path: String, _ sha256: String, label: String, deadline: DispatchTime) throws {
    guard isHex(sha256, 64) else { throw RunnerError("\(label) has an invalid SHA-256.") }
    try requireRegularFile(path)
    let file = try FileHandle(forReadingFrom: fileURL(path))
    defer { try? file.close() }
    let actual = try streamDigest(file, label: label, deadline: deadline)
    guard actual == sha256 else { throw RunnerError("\(label) changed. Its SHA-256 differs from this session.") }
}

private func streamDigest(_ file: FileHandle, label: String, deadline: DispatchTime) throws -> String {
    var digest = SHA256()
    while true {
        guard DispatchTime.now() < deadline else {
            throw RunnerError("Verification took too long while reading \(label).")
        }
        guard let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
        digest.update(data: chunk)
    }
    return hexDigest(digest.finalize())
}

private func hexDigest(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
}
