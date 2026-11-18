// Test-only foreign JSON writer. It never opens, creates or modifies the target.
// Compile: xcrun swiftc tools/hold_export_file_coordination.swift -o /tmp/hold-export-coordination
// Run: hold-export-coordination TARGET.json READY_FILE STOP_FILE DEADLINE_SECONDS
// READY is written only inside the acquired claim; STOP or deadline releases it.
import Foundation
import Darwin

private final class ClaimState {
  let lock = NSLock()
  let release = DispatchSemaphore(value: 0)
  var admitted = false
  var reason: String?
  func admit() -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard reason == nil else { return false }
    admitted = true
    return true
  }
  func stop(_ value: String, coordinator: NSFileCoordinator) {
    lock.lock()
    guard reason == nil else { lock.unlock(); return }
    reason = value
    let cancelWait = !admitted
    lock.unlock()
    release.signal()
    if cancelWait { coordinator.cancel() }
  }
  func releaseReason() -> String {
    lock.lock(); defer { lock.unlock() }; return reason ?? "accessor-failure"
  }
}

private func emit(_ event: String, _ fields: [String: Any] = [:]) {
  var value = fields
  value["event"] = event
  value["pid"] = ProcessInfo.processInfo.processIdentifier
  value["utc"] = ISO8601DateFormatter().string(from: Date())
  if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
    FileHandle.standardOutput.write(data + Data([10]))
  }
}

let arguments = CommandLine.arguments
guard arguments.count == 5,
  arguments[1...3].allSatisfy({ $0.hasPrefix("/") }),
  let seconds = Double(arguments[4]), seconds.isFinite, seconds >= 1, seconds <= 120
else {
  fputs("Usage: hold-export-coordination TARGET.json READY_FILE STOP_FILE DEADLINE_SECONDS(1...120)\n", stderr)
  exit(64)
}
let target = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let ready = URL(fileURLWithPath: arguments[2]).standardizedFileURL
let stop = URL(fileURLWithPath: arguments[3]).standardizedFileURL
let fileManager = FileManager.default
guard target.pathExtension.lowercased() == "json", Set([target.path, ready.path, stop.path]).count == 3,
  !fileManager.fileExists(atPath: ready.path), !fileManager.fileExists(atPath: stop.path)
else { fputs("Require distinct JSON target and fresh READY/STOP paths.\n", stderr); exit(64) }

let coordinator = NSFileCoordinator(filePresenter: nil)
private let state = ClaimState()
let control = DispatchQueue(label: "readaloud.test.foreign-json-claim", qos: .utility)
let timer = DispatchSource.makeTimerSource(queue: control)
let deadline = DispatchTime.now() + seconds
timer.schedule(deadline: .now(), repeating: .milliseconds(100))
timer.setEventHandler {
  if fileManager.fileExists(atPath: stop.path) { state.stop("stop-file", coordinator: coordinator) }
  else if DispatchTime.now() >= deadline { state.stop("deadline", coordinator: coordinator) }
}
timer.resume()
var coordinationError: NSError?, markerError: Error?
var acquired = false
emit("waiting", ["target": target.path, "deadlineSeconds": seconds])
coordinator.coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { _ in
  guard state.admit() else { return }
  do {
    let receipt: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
      "target": target.path, "claimAcquired": true,
      "utc": ISO8601DateFormatter().string(from: Date())]
    try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]).write(to: ready, options: .atomic)
    acquired = true
    emit("claim-acquired", ["target": target.path, "ready": ready.path])
    state.release.wait()
  } catch { markerError = error }
}
timer.cancel()
control.sync {} // Join a running cancellation callback before reporting exit.
emit("claim-released", ["target": target.path, "claimAcquired": acquired,
  "reason": state.releaseReason(), "error": String(describing: markerError ?? coordinationError)])
exit(acquired && markerError == nil && coordinationError == nil ? 0 : 1)
