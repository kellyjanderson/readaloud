import CryptoKit
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RunnerError(message) }
}

private func refused(_ fragment: String, _ action: () throws -> Void) throws {
    do {
        try action()
    } catch {
        try expect(error.localizedDescription.localizedCaseInsensitiveContains(fragment),
                   "Expected refusal containing '\(fragment)', received '\(error.localizedDescription)'")
        return
    }
    throw RunnerError("Expected refusal containing '\(fragment)'")
}

private func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

private func write(_ json: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: json).write(to: url)
}

@main
private struct RunnerTests {
    static func main() throws {
        let directory = fileURL(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("QA Candidate.app")
        let framework = app.appendingPathComponent("Contents/Frameworks/App.framework")
        let binary = framework.appendingPathComponent("Versions/A/App")
        let link = framework.appendingPathComponent("App")
        let launcher = app.appendingPathComponent("Contents/MacOS/read_aloud")
        let resource = app.appendingPathComponent("Contents/Resources/asset")
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        let candidateManifest = directory.appendingPathComponent("candidate.json")
        let sessionURL = directory.appendingPathComponent("native-session.json")
        let reportURL = directory.appendingPathComponent("results/native-results.json")
        let imports = directory.appendingPathComponent("fixtures/imports")
        let doc = imports.appendingPathComponent("Provided document.docx")
        let working = imports.appendingPathComponent("recovery-working.docx")
        let bundleID = "com.kellyjanderson.readAloud.qa." + String(repeating: "1", count: 32)
        let source = String(repeating: "a", count: 40)
        let binaryData = Data("candidate binary".utf8)
        let launcherData = Data("candidate launcher".utf8)
        let resourceData = Data("candidate resource".utf8)
        let docData = Data("supplied document".utf8)
        let changed = Data("changed".utf8)
        let docHash = digest(docData)

        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": bundleID, "CFBundlePackageType": "APPL", "CFBundleExecutable": "read_aloud"]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        func packageFile(_ data: Data, at url: URL, mode: Int) throws -> [String: Any] {
            try data.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
            return ["path": String(url.path.dropFirst(app.path.count + 1)), "mode": mode,
                    "size": data.count, "sha256": digest(data)]
        }
        var packageFiles = try [
            packageFile(plistData, at: plistURL, mode: 0o644),
            packageFile(binaryData, at: binary, mode: 0o755),
            packageFile(launcherData, at: launcher, mode: 0o755),
            packageFile(resourceData, at: resource, mode: 0o644),
        ]
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "Versions/A/App")
        packageFiles.append(["path": "Contents/Frameworks/App.framework/App", "symlink": "Versions/A/App"])
        let bundle: [String: Any] = [
            "bundle_identifier": bundleID, "files": packageFiles, "executable": "Contents/MacOS/read_aloud",
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: [
            "schema": 3,
            "build": ["inputs": ["source": ["commit": source]], "bundle": bundle],
        ])
        let manifestHash = digest(manifestData)
        try manifestData.write(to: candidateManifest)
        try docData.write(to: doc)
        try changed.write(to: working)

        var candidate: [String: Any] = [
            "appPath": app.path, "bundleIdentifier": bundleID, "sourceRevision": source,
            "packageSha256": manifestHash, "packageManifestPath": candidateManifest.path,
            "binaryPath": binary.path, "binarySha256": digest(binaryData),
        ]
        let goodEnvironment = ["READALOUD_TTS_ENGINE": "fish_drama3_8bit", "HF_HUB_OFFLINE": "1"]
        let goodArguments = ["--", doc.path]
        let files: [[String: Any]] = [
            ["label": "Provided document", "path": doc.path, "sha256": docHash],
            ["label": "Working sample", "path": working.path],
        ]
        let setup: [String: String] = [
            "label": "Prepare working sample", "sourcePath": doc.path, "targetPath": working.path, "sha256": docHash,
        ]
        var test: [String: Any] = [
            "id": "example", "title": "Example", "issue": 155, "question": "Test question",
            "steps": ["Open the document"], "expected": "Document opens.",
            "arguments": goodArguments, "environment": goodEnvironment, "files": files,
            "fixtureId": "doc", "fixtureSha256": docHash, "setupActions": [setup],
        ]

        func load(results: URL? = nil) throws -> Session {
            try write([
                "schema": 1, "title": "Read Aloud User Tests", "resultsPath": (results ?? reportURL).path,
                "candidate": candidate, "cases": [test],
            ], to: sessionURL)
            return try Session.read(sessionURL, deadline: .now() + 5)
        }

        let session = try load()
        let example = session.cases[0]
        let verified = try session.candidate.verify(deadline: .now() + 5)
        try expect(verified.applicationURL == fileURL(app.path) && verified.executableURL.path == fileURL(launcher.path).path,
                   "Verified launch plan must use the manifest's bundle and native executable")
        try expect(example.arguments == goodArguments && example.environment == goodEnvironment,
                   "Launch plan must preserve positional paths and approved environment values")
        try example.verifyFiles(deadline: .now() + 5)
        try refused("too long") { try session.candidate.verify(deadline: .now() - 1) }

        try changed.write(to: candidateManifest)
        try refused("candidate manifest changed") { _ = try load() }
        try manifestData.write(to: candidateManifest)
        try changed.write(to: binary)
        try refused("package changed at Contents/Frameworks/App.framework/Versions/A/App") { _ = try load() }
        try binaryData.write(to: binary)
        try Data(repeating: 0, count: launcherData.count).write(to: launcher)
        try refused("package changed at Contents/MacOS/read_aloud") { _ = try load() }
        try launcherData.write(to: launcher)
        try Data(repeating: 0, count: resourceData.count).write(to: resource)
        try refused("package changed at Contents/Resources/asset") { _ = try load() }
        try resourceData.write(to: resource)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: resource.path)
        try refused("package changed at Contents/Resources/asset") { _ = try load() }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: resource.path)
        try FileManager.default.removeItem(at: resource)
        try refused("package is missing Contents/Resources/asset") { _ = try load() }
        _ = try packageFile(resourceData, at: resource, mode: 0o644)
        let extra = app.appendingPathComponent("Contents/Resources/.unexpected")
        try changed.write(to: extra)
        try refused("unexpected file at Contents/Resources/.unexpected") { _ = try load() }
        try FileManager.default.removeItem(at: extra)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "./Versions/A/App")
        try refused("package changed at Contents/Frameworks/App.framework/App") { _ = try load() }
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "Versions/A/App")
        candidate["sourceRevision"] = String(repeating: "b", count: 40)
        try refused("manifest's source revision") { _ = try load() }
        candidate["sourceRevision"] = source
        candidate["bundleIdentifier"] = "com.kellyjanderson.readAloud.qa." + String(repeating: "2", count: 32)
        try refused("manifest's source revision or QA profile") { _ = try load() }
        candidate["bundleIdentifier"] = "com.kellyjanderson.readAloud"
        try refused("QA profile") { _ = try load() }
        candidate["bundleIdentifier"] = bundleID
        candidate["binaryPath"] = doc.path
        try refused("outside the expected App.framework") { _ = try load() }
        candidate["binaryPath"] = binary.path
        candidate["binarySha256"] = docHash
        try refused("does not match the session's Read Aloud binaries") { _ = try load() }
        candidate["binarySha256"] = digest(binaryData)
        try refused("separate JSON file") { _ = try load(results: candidateManifest) }
        try refused("separate JSON file") { _ = try load(results: sessionURL) }

        for key in ["HOME", "CODEX_HOME", "PATH", "DYLD_INSERT_LIBRARIES", "PYTHONPATH", "BASH_ENV"] {
            test["environment"] = [key: "/tmp/example"]
            try refused("unsupported launch setting") { _ = try load() }
        }
        test["environment"] = goodEnvironment
        test["arguments"] = ["--headless", doc.path]
        try refused("declared local files") { _ = try load() }
        test["arguments"] = goodArguments
        test["fixtureSha256"] = manifestHash
        try refused("inconsistent fixture identity") { _ = try load() }
        test["fixtureSha256"] = docHash

        let action = try expectSetup(example)
        try action.prepare(in: example, sessionURL: sessionURL)
        let prepared = try Data(contentsOf: working)
        try expect(prepared == docData, "Recovery action did not copy the declared source")
        try changed.write(to: doc)
        try refused("SHA-256 differs") { try example.verifyFiles(deadline: .now() + 5) }
        try refused("supplied DOCX has changed") { try action.prepare(in: example, sessionURL: sessionURL) }
        let retained = try Data(contentsOf: working)
        try expect(retained == docData, "A refused recovery action changed the working copy")
        try docData.write(to: doc)
        var outside = setup
        outside["targetPath"] = directory.appendingPathComponent("external.docx").path
        test["setupActions"] = [outside]
        try refused("session's working sample") { _ = try load() }
        test["setupActions"] = [setup]
        _ = try load()

        var entry = CaseResult(example)
        entry.startedAt = timestamp()
        entry.origin = .native
        entry.closureEvidence = .pending
        entry.judgment = .worked
        entry.notes = "A note typed by the tester."
        let incomplete = Report(tester: "Tester", session: session, results: [example.id: entry])
        try incomplete.write(reportURL)
        let reloaded = try Report.read(reportURL, session: session, nativeOnly: true)
        try expect(reloaded.results[0].result == .incomplete && reloaded.results[0].outcome == .worked,
                   "An unclosed case must retain the human judgment without asserting a completed result")
        entry.appClosed = true
        entry.closureEvidence = .observedExit
        let closed = Report(tester: "Tester", session: session, results: [example.id: entry])
        try closed.write(reportURL)
        let persisted = try Report.read(reportURL, session: session, nativeOnly: true)
        try expect(persisted.results[0].result == .worked && persisted.results[0].notes == entry.notes
                    && persisted.results[0].origin == .native && persisted.results[0].closureEvidence == .observedExit,
                   "Completed outcome and notes did not round trip")
        var skipped = CaseResult(example)
        skipped.judgment = .skip
        try expect(skipped.canonical(for: example).result == .skip && !skipped.appClosed,
                   "A skipped test must not assert a process was observed to exit")

        let browserURL = directory.appendingPathComponent("browser.json")
        var browserEntry: [String: Any] = [
            "id": example.id, "title": example.title, "issue": example.issue,
            "fixture": ["id": "doc", "sha256": docHash], "result": "problem", "notes": "Browser notes", "appClosed": true,
        ]
        func browser(source: String = source, hash: String = manifestHash) throws -> Report {
            try write([
                "schema": 3, "exportedAt": timestamp(), "tester": "Browser tester",
                "app": ["path": "/old-handoff/read_aloud.app", "sourceRevision": source, "packageSha256": hash],
                "results": [browserEntry],
            ], to: browserURL)
            return try Report.read(browserURL, session: session, nativeOnly: false)
        }
        let imported = try browser()
        try expect(imported.results[0].notes == "Browser notes" && imported.results[0].origin == .browser
                    && imported.results[0].closureEvidence == .testerAttestation,
                   "Same-package browser report did not preserve browser closure provenance")
        try Report(tester: imported.tester, session: session, results: [example.id: imported.results[0]]).write(reportURL)
        let reexported = try Report.read(reportURL, session: session, nativeOnly: true)
        try expect(reexported.results[0].origin == .browser && reexported.results[0].closureEvidence == .testerAttestation,
                   "Native re-export must not restamp imported browser closure as observed")
        try refused("already exists") { _ = try Report.read(browserURL, session: session, nativeOnly: true) }
        try refused("different Read Aloud candidate") { _ = try browser(hash: docHash) }
        try refused("different Read Aloud candidate") { _ = try browser(source: String(repeating: "b", count: 40)) }
        browserEntry["fixture"] = ["id": "doc", "sha256": manifestHash]
        try refused("does not match") { _ = try browser() }
        browserEntry["id"] = "unknown"
        try refused("does not match") { _ = try browser() }
        print("Passed candidate identity, launch plan, fixture setup, and results provenance checks.")
    }

    private static func expectSetup(_ example: TestCase) throws -> TestCase.SetupAction {
        guard let action = example.setupActions?.first else { throw RunnerError("Missing recovery action") }
        return action
    }
}
