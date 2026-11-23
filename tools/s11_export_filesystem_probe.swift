// Sandbox/SavePanel differential only. No model, playback or acoustic claim.
import Cocoa
import CryptoKit
import Darwin
import UniformTypeIdentifiers

private final class Evidence {
  let root: URL
  private let queue = DispatchQueue(label: "readaloud.export-probe.evidence", qos: .utility)
  private let handle: FileHandle
  private var count = 0
  init(root: URL) throws {
    self.root = root
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let path = root.appendingPathComponent("events.jsonl")
    guard FileManager.default.createFile(atPath: path.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    handle = try FileHandle(forWritingTo: path)
  }
  func record(_ event: String, _ fields: [String: Any] = [:]) {
    let observedMicros = Int64(Date().timeIntervalSince1970 * 1_000_000)
    let observedNanos = DispatchTime.now().uptimeNanoseconds
    queue.async {
      guard self.count < 100 else { return }
      self.count += 1
      var row = fields
      row["event"] = event
      row["observedUnixMicros"] = observedMicros
      row["observedUptimeNanos"] = observedNanos
      row["utc"] = ISO8601DateFormatter().string(from: Date())
      do {
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        try self.handle.write(contentsOf: data + Data([10]))
        print("S11_FILESYSTEM_PROBE \(String(decoding: data, as: UTF8.self))")
        fflush(stdout)
      } catch { fputs("Probe evidence failed: \(error)\n", stderr) }
    }
  }
  func close(_ completion: @escaping () -> Void) {
    queue.async {
      try? self.handle.synchronize()
      try? self.handle.close()
      DispatchQueue.main.async(execute: completion)
    }
  }
  func drainSourceChecks() {
    queue.sync { try? self.handle.synchronize() }
  }
}

private func pathState(_ path: String) -> [String: Any] {
  // Path-only syscalls intentionally avoid populating NSURL resource caches.
  var value = stat()
  let status = path.withCString { lstat($0, &value) }
  let code = errno
  var result: [String: Any] = ["path": path, "exists": status == 0]
  if status == 0 {
    result["bytes"] = value.st_size
    result["inode"] = value.st_ino
    result["device"] = value.st_dev
    result["readable"] = path.withCString { access($0, R_OK) == 0 }
    result["writable"] = path.withCString { access($0, W_OK) == 0 }
  } else { result["errno"] = code }
  return result
}

private final class ComputedPresenter: NSObject, NSFilePresenter {
  let primaryPath: String
  let sidecarPath: String
  var primaryPresentedItemURL: URL? { URL(fileURLWithPath: primaryPath) }
  var presentedItemURL: URL? { URL(fileURLWithPath: sidecarPath) }
  let presentedItemOperationQueue: OperationQueue = {
    let value = OperationQueue(); value.maxConcurrentOperationCount = 1
    value.qualityOfService = .utility; return value
  }()
  init(output: URL, sidecar: URL) { primaryPath = output.path; sidecarPath = sidecar.path }
}

private final class FreshPresenter: NSObject, NSFilePresenter {
  let primaryPresentedItemURL: URL?
  let presentedItemURL: URL?
  let presentedItemOperationQueue: OperationQueue = {
    let value = OperationQueue(); value.maxConcurrentOperationCount = 1
    value.qualityOfService = .utility; return value
  }()
  init(primaryPath: String, sidecarPath: String) {
    primaryPresentedItemURL = URL(fileURLWithPath: primaryPath)
    presentedItemURL = URL(fileURLWithPath: sidecarPath)
  }
}

// Cancels only a coordination WAIT, before filesystem mutation is admitted.
// Already running filesystem calls still drain; this is not a hard I/O timeout.
private final class CoordinationWaitBudget {
  private let lock = NSLock()
  private var expired = false, admitted = false, finished = false
  private let timer: DispatchSourceTimer
  init(_ coordinator: NSFileCoordinator, label: String, evidence: Evidence) {
    timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    timer.schedule(deadline: .now() + 10)
    timer.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      let cancel = !self.admitted && !self.finished
      if cancel { self.expired = true }
      self.lock.unlock()
      if cancel {
        evidence.record("coordinationWaitDeadline", ["scope": label, "seconds": 10])
        coordinator.cancel()
      }
    }
    timer.resume()
  }
  func admit() throws {
    lock.lock(); let cancelled = expired
    if !cancelled { admitted = true }
    lock.unlock(); timer.cancel()
    if cancelled { throw CocoaError(.userCancelled) }
  }
  func finish() -> Bool {
    lock.lock(); finished = true; let value = expired; lock.unlock()
    timer.cancel(); return value
  }
}

private func writeScope(_ output: URL, second: URL? = nil, presenter: NSFilePresenter? = nil,
  label: String, evidence: Evidence, body: (NSFileCoordinator) throws -> Void) throws {
  let coordinator = NSFileCoordinator(filePresenter: presenter)
  let budget = CoordinationWaitBudget(coordinator, label: label, evidence: evidence)
  var coordinationError: NSError?, actionError: Error?
  var entered = false
  func perform() {
    do {
      try budget.admit(); entered = true
      evidence.record("coordinationEntered", ["scope": label])
      try body(coordinator)
    } catch { actionError = error }
  }
  if let second = second {
    coordinator.coordinate(writingItemAt: output, options: .forReplacing,
      writingItemAt: second, options: .forReplacing, error: &coordinationError) { _, _ in perform() }
  } else {
    coordinator.coordinate(writingItemAt: output, options: .forReplacing,
      error: &coordinationError) { _ in perform() }
  }
  let expired = budget.finish()
  evidence.record("coordinationReturned", ["scope": label, "entered": entered, "waitExpired": expired])
  if let error = actionError { throw error }
  if let error = coordinationError { throw error }
  if expired || !entered { throw CocoaError(.userCancelled) }
}

private struct FileIdentity: Equatable {
  let device: Int64, inode: UInt64
  static func read(_ url: URL) -> FileIdentity? {
    var value = stat()
    guard url.path.withCString({ lstat($0, &value) }) == 0 else { return nil }
    return FileIdentity(device: Int64(value.st_dev), inode: UInt64(value.st_ino))
  }
}

// Diagnostic transaction for explicit related-only write scopes. Per-file
// renames/ordinary rollback only; the two-phase mode claims no external pair
// atomicity. An inode fence prevents rollback from deleting another writer's WAV.
private func scopedTransaction(mode: String, stage: URL, output: URL, evidence: Evidence,
  register: (NSFilePresenter) throws -> Void) throws {
  let fm = FileManager.default
  let sidecar = try AudioExportPairPublication.sidecar(for: output)
  try AudioExportPairPublication.validatePair(output: output, sidecar: sidecar)
  let audio = stage.appendingPathComponent("audio.wav"), json = stage.appendingPathComponent("metadata.json")
  let oldAudio = stage.appendingPathComponent("previous.wav"), oldJson = stage.appendingPathComponent("previous.json")
  var audioBackedUp = false, audioPublished = false
  var installed: FileIdentity?
  func installPrimary() throws {
    if fm.fileExists(atPath: output.path) {
      try AudioExportPairPublication.renameFile(output, oldAudio); audioBackedUp = true
    }
    try AudioExportPairPublication.renameFile(audio, output); audioPublished = true
    installed = FileIdentity.read(output)
    guard installed != nil else { throw CocoaError(.fileReadNoSuchFile) }
    evidence.record("primaryInstalled", ["primary": pathState(output.path)])
  }
  func rollbackPrimary() throws {
    if audioPublished {
      guard installed != nil && installed == FileIdentity.read(output) else {
        throw CocoaError(.fileWriteFileExists)
      }
      try fm.removeItem(at: output); audioPublished = false
    } else if fm.fileExists(atPath: output.path) {
      throw CocoaError(.fileWriteFileExists)
    }
    if audioBackedUp {
      try AudioExportPairPublication.renameFile(oldAudio, output); audioBackedUp = false
    }
  }
  func publishMetadata() throws {
    var backedUp = false
    do {
      if fm.fileExists(atPath: sidecar.path) {
        let values = try sidecar.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory != true && values.isSymbolicLink != true else { throw CocoaError(.fileWriteInvalidFileName) }
        try AudioExportPairPublication.renameFile(sidecar, oldJson); backedUp = true
      }
      try AudioExportPairPublication.renameFile(json, sidecar)
    } catch {
      let publication = error
      do { if backedUp { try AudioExportPairPublication.renameFile(oldJson, sidecar) } }
      catch { throw AudioExportPairPublication.Failure(publication: publication, rollback: error) }
      throw publication
    }
  }
  func relatedWrite() throws {
    let presenter = FreshPresenter(primaryPath: output.path, sidecarPath: sidecar.path)
    try register(presenter)
    defer { NSFileCoordinator.removeFilePresenter(presenter) }
    try writeScope(URL(fileURLWithPath: sidecar.path), presenter: presenter,
      label: "related-json", evidence: evidence) { _ in
      guard installed == FileIdentity.read(output) else { throw CocoaError(.fileWriteFileExists) }
      try publishMetadata()
    }
  }
  func recover(_ publication: Error, coordinated: Bool) throws {
    do {
      if coordinated {
        try writeScope(output, label: "primary-rollback", evidence: evidence) { _ in try rollbackPrimary() }
      } else { try rollbackPrimary() }
    } catch { throw AudioExportPairPublication.Failure(publication: publication, rollback: error) }
    throw publication
  }
  if mode == "nested-related" {
    try writeScope(output, second: sidecar, label: "outer-pair", evidence: evidence) { _ in
      do { try installPrimary(); try relatedWrite() }
      catch { try recover(error, coordinated: false) }
    }
  } else {
    try writeScope(output, label: "primary-phase", evidence: evidence) { _ in
      do { try installPrimary() }
      catch { try recover(error, coordinated: false) }
    }
    evidence.record("primaryPhaseComplete", ["primary": pathState(output.path)])
    do { try relatedWrite() }
    catch { try recover(error, coordinated: true) }
  }
}

private func notifiedTransaction(stage: URL, output: URL, evidence: Evidence,
  register: (NSFilePresenter) throws -> Void) throws {
  let sidecar = try AudioExportPairPublication.sidecar(for: output)
  var registered: NSFilePresenter?
  defer { if let value = registered { NSFileCoordinator.removeFilePresenter(value) } }
  try writeScope(output, second: sidecar, label: "move-notified-pair", evidence: evidence) { coordinator in
    try AudioExportPairPublication.publishFiles(stage: stage, output: output, sidecar: sidecar,
      move: { source, destination in
        let installs = source.lastPathComponent == "audio.wav" && destination == output
        if installs { coordinator.item(at: source, willMoveTo: destination) }
        try AudioExportPairPublication.renameFile(source, destination)
        if installs {
          coordinator.item(at: source, didMoveTo: destination)
          evidence.record("primaryMoveNotified", ["primary": pathState(output.path)])
        }
      }, prepareRelatedAccess: {
        let presenter = FreshPresenter(primaryPath: output.path, sidecarPath: sidecar.path)
        try register(presenter); registered = presenter
      })
  }
}

private func performExport(mode: String, path: String, retainedURL: URL?, evidence: Evidence) -> String {
  var phase = "staging"
  var stage: URL?
  var preserve = false
  let output = retainedURL ?? URL(fileURLWithPath: path).standardizedFileURL
  func register(_ presenter: NSFilePresenter) throws {
    phase = "related-registration"
    let primary = presenter.primaryPresentedItemURL ?? nil
    let secondary = presenter.presentedItemURL
    var state: [String: Any] = ["mode": mode, "primary": pathState(path),
      "primaryURL": primary?.absoluteString ?? "nil", "sidecarURL": secondary?.absoluteString ?? "nil"]
    if let handle = FileHandle(forReadingAtPath: path) {
      defer { try? handle.close() }
      let bytes = try handle.readToEnd() ?? Data()
      state["primaryReadBytes"] = bytes.count
      state["primaryReadSHA256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    evidence.record("beforeRelatedRegistration", state)
    NSFileCoordinator.addFilePresenter(presenter)
    evidence.record("afterRelatedRegistration", ["primary": pathState(path)])
    phase = "json-publication"
  }
  do {
    stage = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
      appropriateFor: output, create: true)
    evidence.record("stageAllocated", ["stage": stage!.path, "primary": pathState(path)])
    for (resource, target) in [("fixture.wav", "audio.wav"), ("fixture.json", "metadata.json")] {
      guard let source = Bundle.main.resourceURL?.appendingPathComponent(resource) else {
        throw CocoaError(.fileReadNoSuchFile)
      }
      try FileManager.default.copyItem(at: source, to: stage!.appendingPathComponent(target))
    }
    phase = "publication"
    if mode == "baseline29" || mode == "direct-url" {
      try AudioExportPairPublication.coordinateAndPublish(stage: stage!, output: output,
        registerPresenter: register)
    } else if mode == "nested-related" || mode == "two-phase" {
      try scopedTransaction(mode: mode, stage: stage!, output: output, evidence: evidence, register: register)
    } else if mode == "move-notification" {
      try notifiedTransaction(stage: stage!, output: output, evidence: evidence, register: register)
    } else {
      let sidecar = try AudioExportPairPublication.sidecar(for: output)
      let early: NSFilePresenter? = mode == "computed-urls"
        ? ComputedPresenter(output: output, sidecar: sidecar) : nil
      let coordinator = NSFileCoordinator(filePresenter: early)
      var registered: NSFilePresenter?
      defer { if let value = registered { NSFileCoordinator.removeFilePresenter(value) } }
      var coordinationError: NSError?
      var publicationError: Error?
      coordinator.coordinate(writingItemAt: output, options: .forReplacing,
        writingItemAt: sidecar, options: .forReplacing, error: &coordinationError) { audioURL, jsonURL in
        do {
          try AudioExportPairPublication.publishFiles(stage: stage!, output: audioURL, sidecar: jsonURL,
            prepareRelatedAccess: {
              let presenter = early ?? FreshPresenter(primaryPath: audioURL.path, sidecarPath: jsonURL.path)
              try register(presenter)
              registered = presenter
            })
        } catch { publicationError = error }
      }
      if let error = publicationError { throw error }
      if let error = coordinationError { throw error }
    }
    evidence.record("published", ["primary": pathState(path),
      "sidecar": pathState(try AudioExportPairPublication.sidecar(for: output).path)])
    phase = "cleanup"
    try FileManager.default.removeItem(at: stage!)
    evidence.record("complete", ["succeeded": true, "stageExists": FileManager.default.fileExists(atPath: stage!.path)])
    return "Saved WAV and JSON. Normal Quit is ready."
  } catch {
    preserve = (error as? AudioExportPairPublication.Failure)?.preservesStage == true
    evidence.record("failure", ["phase": phase, "error": String(describing: error),
      "primary": pathState(path), "preserveRecovery": preserve])
    if let stage = stage, !preserve {
      do { try FileManager.default.removeItem(at: stage) }
      catch { evidence.record("cleanupFailure", ["error": String(describing: error), "stage": stage.path]) }
    }
    evidence.record("complete", ["succeeded": false,
      "stageExists": stage.map { FileManager.default.fileExists(atPath: $0.path) } ?? false])
    return "Export failed during \(phase). Normal Quit is ready."
  }
}

private final class ProbeDelegate: NSObject, NSApplicationDelegate {
  let mode: String
  let evidence: Evidence
  var window: NSWindow!
  var button: NSButton!
  var status: NSTextField!
  var working = false
  var quitPending = false
  var closing = false
  init(mode: String, evidence: Evidence) { self.mode = mode; self.evidence = evidence }
  func applicationDidFinishLaunching(_ notification: Notification) {
    let menu = NSMenu()
    let appItem = NSMenuItem(); menu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit Filesystem Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu; NSApp.mainMenu = menu
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 220),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "S11 Filesystem Probe — \(mode)"
    let title = NSTextField(labelWithString: "Filesystem diagnostic: \(mode)")
    title.frame = NSRect(x: 24, y: 164, width: 572, height: 24)
    status = NSTextField(wrappingLabelWithString: "One native SavePanel export of the bundled WAV/JSON fixture. No playback or model inference.")
    status.frame = NSRect(x: 24, y: 80, width: 572, height: 68)
    button = NSButton(title: "Save Filesystem Fixture…", target: self, action: #selector(saveFixture))
    button.frame = NSRect(x: 24, y: 24, width: 280, height: 36)
    window.contentView?.addSubview(title); window.contentView?.addSubview(status); window.contentView?.addSubview(button)
    window.center(); window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    evidence.record("ready", ["mode": mode, "pid": getpid(), "bundle": Bundle.main.bundleIdentifier ?? "unknown",
      "manifest": (try? String(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("manifest.json"), encoding: .utf8)) ?? "missing"])
  }
  @objc func saveFixture() {
    guard !working else { return }
    button.isEnabled = false
    let panel = NSSavePanel()
    panel.title = "S11 Filesystem Fixture"
    panel.showsTagField = false; panel.showsHiddenFiles = false; panel.canCreateDirectories = true
    panel.allowedContentTypes = [.wav]
    panel.nameFieldStringValue = "fs-\(mode).wav"
    evidence.record("beforeSavePanel", ["mode": mode])
    panel.beginSheetModal(for: window) { response in
      guard response == .OK, let selected = panel.url else {
        self.button.isEnabled = true; return
      }
      guard !self.quitPending else { return }
      self.working = true
      let path = selected.path
      let retained: URL? = self.mode == "direct-url" ? selected : nil
      // Match FilePicker: path-only result, return from sheet completion before
      // constructing the production owner/URLs and dispatching utility work.
      DispatchQueue.main.async {
        self.status.stringValue = "Publishing filesystem fixture…"
        let mode = self.mode, evidence = self.evidence
        evidence.record("afterSavePanel", ["mode": mode, "primary": pathState(path),
          "retainsPanelURL": retained != nil])
        DispatchQueue.global(qos: .utility).async {
          let outcome = performExport(mode: mode, path: path, retainedURL: retained, evidence: evidence)
          DispatchQueue.main.async {
            self.working = false; self.status.stringValue = outcome
            if self.quitPending { self.finishQuit() }
          }
        }
      }
    }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    quitPending = true
    if !working { finishQuit() }
    return .terminateLater
  }
  func finishQuit() {
    guard !closing else { return }; closing = true
    evidence.record("normalQuitDrained", ["working": working])
    evidence.close { NSApp.reply(toApplicationShouldTerminate: true) }
  }
}

@main private struct FilesystemProbe {
  static func main() throws {
    let args = CommandLine.arguments
    guard args.count == 3, ["baseline29", "computed-urls", "fresh-presenter", "direct-url",
      "nested-related", "two-phase", "move-notification"].contains(args[1]) else {
      throw CocoaError(.coderInvalidValue)
    }
    let root = URL(fileURLWithPath: args[2])
    guard !FileManager.default.fileExists(atPath: root.path) else { throw CocoaError(.fileWriteFileExists) }
    let evidence = try Evidence(root: root)
    let app = NSApplication.shared
    let delegate = ProbeDelegate(mode: args[1], evidence: evidence)
    app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
    _ = delegate
  }
}
