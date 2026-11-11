import Cocoa
import FlutterMacOS
import Darwin

@main
class AppDelegate: FlutterAppDelegate {
  private let documentAccessChannelName = "read_aloud/document_access"
  private let mlxLifecycleChannelName = "read_aloud/mlx_tts_lifecycle"
  private var activeSecurityScopedURLs: [String: URL] = [:]
  private var documentAccessChannel: FlutterMethodChannel?
  private var mlxLifecycleChannel: FlutterMethodChannel?
  private var bookNlpLifecycleChannel: FlutterMethodChannel?
  // Main-thread owned; a request may end only its own activity.
  private var speechWorkActivities: [String: NSObjectProtocol] = [:]
  private var speechWorkStarted = 0
  private var speechWorkEnded = 0
  private var speechWorkPeak = 0
  private var terminationCleanupStarted = false
  private var terminationReplySent = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // A failed inference child must surface a pipe error, not kill the GUI.
    signal(SIGPIPE, SIG_IGN)
    // FlutterAppDelegate implements will-finish-launching, but not this optional
    // NSApplicationDelegate callback. Dispatching it to super raises an exception.
    configureDocumentAccessChannel()
    if ProcessInfo.processInfo.environment["READALOUD_TRACE_STARTUP"] == "1" {
      NSLog("[read_aloud.startup] Did finish launching; document access channel configured: \(documentAccessChannel != nil)")
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let mlxLifecycleChannel else { return .terminateNow }
    guard !terminationCleanupStarted else { return .terminateLater }
    terminationCleanupStarted = true

    let finishTermination = { [weak self] in
      DispatchQueue.main.async {
        guard let self, !self.terminationReplySent else { return }
        for activity in self.speechWorkActivities.values {
          ProcessInfo.processInfo.endActivity(activity)
          self.speechWorkEnded += 1
        }
        self.speechWorkActivities.removeAll()
        self.terminationReplySent = true
        sender.reply(toApplicationShouldTerminate: true)
      }
    }
    let cleanup = DispatchGroup()
    for channel in [mlxLifecycleChannel, bookNlpLifecycleChannel].compactMap({ $0 }) {
      cleanup.enter()
      channel.invokeMethod("shutdown", arguments: nil) { _ in cleanup.leave() }
    }
    cleanup.notify(queue: .main) { finishTermination() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
      finishTermination()
    }
    return .terminateLater
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func configureDocumentAccessChannel(
    using flutterViewController: FlutterViewController? = nil
  ) {
    if documentAccessChannel != nil {
      return
    }

    guard
      let resolvedFlutterViewController = flutterViewController
        ?? NSApplication.shared.windows
          .compactMap({ $0.contentViewController as? FlutterViewController })
          .first
    else {
      NSLog("[read_aloud.document_access] Flutter view controller not ready yet; channel registration deferred.")
      return
    }

    let channel = FlutterMethodChannel(
      name: documentAccessChannelName,
      binaryMessenger: resolvedFlutterViewController.engine.binaryMessenger
    )
    mlxLifecycleChannel = FlutterMethodChannel(
      name: mlxLifecycleChannelName,
      binaryMessenger: resolvedFlutterViewController.engine.binaryMessenger
    )
    bookNlpLifecycleChannel = FlutterMethodChannel(
      name: "read_aloud/booknlp_lifecycle",
      binaryMessenger: resolvedFlutterViewController.engine.binaryMessenger
    )
    // Each process samples itself: sandbox policy denies cross-process libproc
    // queries. Dart combines this value with its current child's telemetry.
    mlxLifecycleChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      if call.method == "speechWorkActivityCount" {
        result(self.speechWorkActivities.count)
        return
      }
      if call.method == "speechWorkActivitySnapshot" {
        result([
          "active": self.speechWorkActivities.count,
          "started": self.speechWorkStarted,
          "ended": self.speechWorkEnded,
          "peak": self.speechWorkPeak
        ])
        return
      }
      if call.method == "beginSpeechWork" || call.method == "endSpeechWork" {
        guard let arguments = call.arguments as? [String: Any],
              let owner = arguments["owner"] as? String,
              !owner.isEmpty, owner.utf8.count <= 128 else {
          result(FlutterError(code: "invalid_speech_activity",
            message: "Speech activity requires a bounded owner.", details: nil))
          return
        }
        if call.method == "endSpeechWork" {
          if let activity = self.speechWorkActivities.removeValue(forKey: owner) {
            ProcessInfo.processInfo.endActivity(activity)
            self.speechWorkEnded += 1
          }
        } else if self.speechWorkActivities[owner] == nil {
          guard !self.terminationCleanupStarted,
                self.speechWorkActivities.count < 8 else {
            result(FlutterError(code: "speech_activity_unavailable",
              message: "Speech activity owner is closing or full.", details: nil))
            return
          }
          self.speechWorkActivities[owner] = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Preparing requested speech"
          )
          self.speechWorkStarted += 1
          self.speechWorkPeak = max(self.speechWorkPeak, self.speechWorkActivities.count)
        }
        result(nil)
        return
      }
      guard call.method == "runtimeFootprint" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let owner = getpid()
      DispatchQueue.global(qos: .utility).async {
        func footprint(_ pid: pid_t) -> UInt64? {
          var info = rusage_info_v2()
          let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
              proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
          }
          return status == 0 ? info.ri_phys_footprint : nil
        }
        let appBytes = footprint(owner)
        DispatchQueue.main.async {
          guard let appBytes else {
            result(FlutterError(code: "memory_sample_unavailable",
              message: "Could not sample the application footprint.", details: nil))
            return
          }
          result(appBytes)
        }
      }
    }
    documentAccessChannel = channel
    NSLog("[read_aloud.document_access] Document access channel registered.")

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "document_access_unavailable",
            message: "Document access service is no longer available.",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "createRadocExportStage":
        self.handleCreateRadocExportStage(call: call, result: result)
      case "createPersistentRestoreToken":
        self.handleCreatePersistentRestoreToken(call: call, result: result)
      case "openPersistentRestoreToken":
        self.handleOpenPersistentRestoreToken(call: call, result: result)
      case "requestPersistentRestoreAccess":
        self.handleRequestPersistentRestoreAccess(call: call, result: result)
      case "requestPersistentDirectoryAccess":
        self.handleRequestPersistentDirectoryAccess(call: call, result: result)
      case "closePersistentRestoreToken":
        self.handleClosePersistentRestoreToken(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleCreateRadocExportStage(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      path.hasPrefix("/"), !path.hasSuffix("/")
    else {
      result(FlutterError(code: "radoc_stage_invalid_destination",
        message: "Choose an audio-book destination before saving.", details: nil))
      return
    }

    // NSSavePanel grants the selected file, not its parent directory. Foundation
    // chooses an accessible replacement directory on that file's volume. Do not
    // substitute temporaryDirectory: rename must never become a copying save.
    // One RadocAudioPackage request owns this allocation and its eventual cleanup;
    // no app/UI state crosses the utility worker, and replies return on main.
    DispatchQueue.global(qos: .utility).async {
      do {
        let stage = try FileManager.default.url(
          for: .itemReplacementDirectory,
          in: .userDomainMask,
          appropriateFor: URL(fileURLWithPath: path),
          create: true
        )
        DispatchQueue.main.async { result(stage.path) }
      } catch {
        let failure = error as NSError
        NSLog("[read_aloud.radoc_export] Replacement-directory allocation failed: \(failure)")
        DispatchQueue.main.async {
          result(FlutterError(code: "radoc_stage_failed",
            message: "Could not prepare a safe audio-book save at the selected location.",
            details: ["domain": failure.domain, "code": failure.code,
              "description": failure.localizedDescription]))
        }
      }
    }
  }

  private func handleCreatePersistentRestoreToken(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      result(nil)
      return
    }

    let url = URL(fileURLWithPath: path)

    do {
      let bookmarkData = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      NSLog("[read_aloud.document_access] Created restore token for path: \(path)")
      result(bookmarkData.base64EncodedString())
    } catch {
      NSLog("[read_aloud.document_access] Failed to create restore token for path: \(path) error: \(error.localizedDescription)")
      result(
        FlutterError(
          code: "document_access_create_failed",
          message: "Could not create persistent restore access for the file.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func handleOpenPersistentRestoreToken(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let token = arguments["token"] as? String,
      let bookmarkData = Data(base64Encoded: token)
    else {
      result(nil)
      return
    }

    var isStale = false

    do {
      let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      guard url.startAccessingSecurityScopedResource() else {
        result(
          FlutterError(
            code: "document_access_scope_failed",
            message: "Could not access the remembered file.",
            details: nil
          )
        )
        return
      }

      var returnedToken = token
      if isStale {
        let refreshedBookmarkData = try url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        returnedToken = refreshedBookmarkData.base64EncodedString()
      }

      activeSecurityScopedURLs[returnedToken] = url
      if returnedToken != token {
        activeSecurityScopedURLs[token] = nil
      }
      NSLog("[read_aloud.document_access] Opened restore token for path: \(url.path) stale: \(isStale)")

      result([
        "path": url.path,
        "token": returnedToken,
      ])
    } catch {
      NSLog("[read_aloud.document_access] Failed to reopen restore token. error: \(error.localizedDescription)")
      result(
        FlutterError(
          code: "document_access_open_failed",
          message: "Could not reopen the remembered file.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func handleRequestPersistentRestoreAccess(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      result(nil)
      return
    }

    let requestedURL = URL(fileURLWithPath: path)
    let panel = NSOpenPanel()
    panel.title = "Allow Read Aloud To Reopen Your Last Document"
    panel.message =
      "Read Aloud needs access to this file once so it can restore it automatically next time."
    panel.prompt = "Allow Access"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.directoryURL = requestedURL.deletingLastPathComponent()
    panel.nameFieldStringValue = requestedURL.lastPathComponent

    if panel.runModal() != .OK || panel.url == nil {
      NSLog("[read_aloud.document_access] User cancelled restore access request for path: \(path)")
      result(nil)
      return
    }

    let grantedURL = panel.url!
    guard grantedURL.startAccessingSecurityScopedResource() else {
      NSLog("[read_aloud.document_access] Failed to start scoped access from open panel for path: \(grantedURL.path)")
      result(
        FlutterError(
          code: "document_access_scope_failed",
          message: "Could not access the selected file.",
          details: nil
        )
      )
      return
    }

    do {
      let bookmarkData = try grantedURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      let token = bookmarkData.base64EncodedString()
      activeSecurityScopedURLs[token] = grantedURL
      NSLog("[read_aloud.document_access] User granted restore access for path: \(grantedURL.path)")
      result([
        "path": grantedURL.path,
        "token": token,
      ])
    } catch {
      grantedURL.stopAccessingSecurityScopedResource()
      NSLog("[read_aloud.document_access] Failed to create bookmark after access request for path: \(grantedURL.path) error: \(error.localizedDescription)")
      result(
        FlutterError(
          code: "document_access_create_failed",
          message: "Could not create restore access for the selected file.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func handleRequestPersistentDirectoryAccess(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      result(nil)
      return
    }

    let requestedURL = URL(fileURLWithPath: path)
    let panel = NSOpenPanel()
    panel.title = "Allow Read Aloud To Reopen Documents From This Folder"
    panel.message =
      "Choose this folder once so Read Aloud can reopen documents from it on future launches."
    panel.prompt = "Allow Folder"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.directoryURL = requestedURL

    if panel.runModal() != .OK || panel.url == nil {
      NSLog("[read_aloud.document_access] User cancelled directory access request for path: \(path)")
      result(nil)
      return
    }

    let grantedURL = panel.url!
    guard grantedURL.startAccessingSecurityScopedResource() else {
      NSLog("[read_aloud.document_access] Failed to start scoped directory access from open panel for path: \(grantedURL.path)")
      result(
        FlutterError(
          code: "document_access_scope_failed",
          message: "Could not access the selected folder.",
          details: nil
        )
      )
      return
    }

    do {
      let bookmarkData = try grantedURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      let token = bookmarkData.base64EncodedString()
      activeSecurityScopedURLs[token] = grantedURL
      NSLog("[read_aloud.document_access] User granted directory restore access for path: \(grantedURL.path)")
      result([
        "path": grantedURL.path,
        "token": token,
      ])
    } catch {
      grantedURL.stopAccessingSecurityScopedResource()
      NSLog("[read_aloud.document_access] Failed to create directory bookmark after access request for path: \(grantedURL.path) error: \(error.localizedDescription)")
      result(
        FlutterError(
          code: "document_access_create_failed",
          message: "Could not create restore access for the selected folder.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func handleClosePersistentRestoreToken(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let token = arguments["token"] as? String
    else {
      result(nil)
      return
    }

    if let url = activeSecurityScopedURLs.removeValue(forKey: token) {
      url.stopAccessingSecurityScopedResource()
      NSLog("[read_aloud.document_access] Closed restore token for path: \(url.path)")
    }

    result(nil)
  }
}
