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
  private static let memoryDiagnosticsLock = NSLock()
  private static var memoryDiagnosticsLogged = false

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
    // Sampling is utility-queue owned. Dart admits at most one in-flight sample
    // and fences completions by child identity; the main thread only replies.
    mlxLifecycleChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      if call.method == "runtimeDeviceIdentity" {
        DispatchQueue.global(qos: .utility).async {
          var length = 0
          let sized = sysctlbyname("machdep.cpu.brand_string", nil, &length, nil, 0)
          var value = [CChar](repeating: 0, count: max(1, min(length, 1024)))
          let read = sized == 0 && length > 0 && length <= 1024
            ? sysctlbyname("machdep.cpu.brand_string", &value, &length, nil, 0) : -1
          let chip = read == 0 ? String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines) : ""
          DispatchQueue.main.async {
            if chip.isEmpty {
              result(FlutterError(code: "device_identity_unavailable", message: "Could not identify this Mac for model qualification.", details: nil))
            } else {
              result("\(chip)/\(ProcessInfo.processInfo.physicalMemory)")
            }
          }
        }
        return
      }
      if call.method == "timingClockSnapshot" {
        var raw = timespec()
        guard clock_gettime(CLOCK_MONOTONIC_RAW, &raw) == 0 else {
          result(FlutterError(code: "timing_clock_unavailable",
            message: "Could not sample CLOCK_MONOTONIC_RAW.", details: nil))
          return
        }
        result([
          "clockDomain": "CLOCK_MONOTONIC_RAW",
          "monotonicRawNanos": Int64(raw.tv_sec) * 1_000_000_000 + Int64(raw.tv_nsec),
          "unixMicros": Int64(Date().timeIntervalSince1970 * 1_000_000)
        ])
        return
      }
      if call.method == "speechWorkActivityCount" {
        result(self.speechWorkActivities.count)
        return
      }
      if call.method == "speechWorkActivityProbe" {
        // Diagnostic wall-clock entry distinguishes channel delivery from work
        // inside this immediate handler. The QA roundtrip gate stays monotonic.
        let entered = Int64(Date().timeIntervalSince1970 * 1_000_000)
        result([
          "owners": self.speechWorkActivities.count,
          "nativeEntryUnixMicros": entered,
          "applicationActive": NSApp.isActive
        ])
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
      if call.method == "runtimeMemorySnapshot" {
        let owner = getpid()
        DispatchQueue.global(qos: .utility).async {
          let snapshot = Self.sampleRuntimeMemory(owner: owner)
          DispatchQueue.main.async { result(snapshot) }
        }
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

  /// Supported libproc/Mach counters, no shell or process-name matching. A
  /// denied child query, changing tree or bounded traversal reports incomplete;
  /// it must never masquerade as a complete app-only measurement. phys_footprint
  /// includes charged native/Metal pages: MLX allocator counters are not added.
  private static func sampleRuntimeMemory(owner: pid_t) -> [String: Any] {
    var complete = true
    var diagnostics: [String: Any] = [:]
    // KERN_PROC is a maintained BSD process table facility. It can have a
    // different sandbox policy from libproc; validate both calls and root
    // membership rather than treating a denied/empty table as no children.
    func sysctlDescendants() -> Set<pid_t>? {
      var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
      var size = 0
      errno = 0
      let sizing = sysctl(&mib, 3, nil, &size, nil, 0)
      diagnostics["sysctlSizingStatus"] = sizing
      diagnostics["sysctlSizingErrno"] = errno
      diagnostics["sysctlSizingBytes"] = size
      guard sizing == 0, size > 0, size < 64 * 1024 * 1024 else { return nil }
      var records = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
      var bytes = records.count * MemoryLayout<kinfo_proc>.stride
      errno = 0
      let status = records.withUnsafeMutableBytes {
        sysctl(&mib, 3, $0.baseAddress, &bytes, nil, 0)
      }
      diagnostics["sysctlReadStatus"] = status
      diagnostics["sysctlReadErrno"] = errno
      diagnostics["sysctlReadBytes"] = bytes
      guard status == 0, bytes % MemoryLayout<kinfo_proc>.stride == 0,
            bytes <= records.count * MemoryLayout<kinfo_proc>.stride else { return nil }
      let table = records.prefix(bytes / MemoryLayout<kinfo_proc>.stride)
      guard table.contains(where: { $0.kp_proc.p_pid == owner }) else { return nil }
      var seen: Set<pid_t> = [owner]
      var changed = true
      while changed {
        changed = false
        for process in table where seen.contains(process.kp_eproc.e_ppid) && process.kp_proc.p_pid > 0 {
          if seen.insert(process.kp_proc.p_pid).inserted { changed = true }
          if seen.count > 512 { return nil }
        }
      }
      return seen
    }
    func descendants() -> Set<pid_t> {
      var seen: Set<pid_t> = [owner]
      var pending: [pid_t] = [owner]
      while let parent = pending.popLast() {
        var children = [pid_t](repeating: 0, count: 128)
        errno = 0
        let count = children.withUnsafeMutableBytes {
          proc_listchildpids(parent, $0.baseAddress, Int32($0.count))
        }
        let queryErrno = errno
        if parent == owner {
          diagnostics["listChildCount"] = count
          diagnostics["listChildErrno"] = queryErrno
        }
        guard count >= 0, queryErrno == 0, count < children.count else {
          if let table = sysctlDescendants() {
            diagnostics["enumerationBasis"] = "sysctl-kern-proc"
            return table
          }
          complete = false
          return seen
        }
        for child in children.prefix(Int(count)) where child > 0 {
          if seen.insert(child).inserted {
            guard seen.count <= 512 else {
              complete = false
              return seen
            }
            pending.append(child)
          }
        }
      }
      return seen
    }
    let processIds = descendants()
    var enumerationComplete = complete
    var total: UInt64 = 0
    var samples: [[String: Any]] = []
    var unavailable: [pid_t] = []
    for pid in processIds.sorted() {
      var info = rusage_info_v2()
      let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
          proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
        }
      }
      if status == 0 {
        total += info.ri_phys_footprint
        samples.append(["pid": pid, "footprintBytes": info.ri_phys_footprint])
      } else {
        complete = false
        unavailable.append(pid)
      }
    }
    // Footprint denial may be reconciled with supervisor-owned child self
    // telemetry. Enumeration denial or a changing tree cannot be reconciled.
    let footprintComplete = complete
    complete = enumerationComplete
    if descendants() != processIds { complete = false }
    enumerationComplete = complete
    complete = footprintComplete && enumerationComplete
    var statistics = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let host = mach_host_self()
    defer { mach_port_deallocate(mach_task_self_, host) }
    let status = withUnsafeMutablePointer(to: &statistics) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(host, HOST_VM_INFO64, $0, &count)
      }
    }
    var pageSize: vm_size_t = 0
    let pageStatus = host_page_size(host, &pageSize)
    if status != KERN_SUCCESS || pageStatus != KERN_SUCCESS { complete = false }
    // Chromium's maintained Apple GetAvailablePhysicalMemory recipe: free
    // excluding speculative (already included by XNU), plus file-backed cache
    // reclaimable without swap. This is an admission estimate, not a promise.
    // https://chromium.googlesource.com/chromium/src/+/refs/heads/main/base/process/process_metrics_apple.mm
    let nonSpeculativeFree = statistics.free_count > statistics.speculative_count
      ? statistics.free_count - statistics.speculative_count : 0
    let available = min(ProcessInfo.processInfo.physicalMemory,
      (UInt64(nonSpeculativeFree) + UInt64(statistics.external_page_count)) * UInt64(pageSize))
    var pressure: Int32 = 0
    var pressureSize = MemoryLayout<Int32>.size
    let pressureStatus = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0)
    let pressureName: String
    switch pressureStatus == 0 ? pressure : 0 {
    case 1: pressureName = "normal"
    case 2: pressureName = "warning"
    case 4: pressureName = "critical"
    default: pressureName = "unknown"
    }
    memoryDiagnosticsLock.lock()
    let shouldLog = !memoryDiagnosticsLogged
    memoryDiagnosticsLogged = true
    memoryDiagnosticsLock.unlock()
    if shouldLog {
      errno = 0
      diagnostics["listAllCount"] = proc_listallpids(nil, 0)
      diagnostics["listAllErrno"] = errno
      var bsd = proc_bsdinfo()
      errno = 0
      diagnostics["ownBsdStatus"] = proc_pidinfo(owner, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size))
      diagnostics["ownBsdErrno"] = errno
      diagnostics["ownerPid"] = owner
      diagnostics["enumerationComplete"] = enumerationComplete
      if let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: [.sortedKeys]),
         let json = String(data: data, encoding: .utf8) {
        NSLog("[readaloud-memory] %@", json)
      }
    }
    return [
      "totalFootprintBytes": total,
      "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
      "availableMemoryBytes": available,
      "availableMemoryBasis": "host-nonspeculative-free-plus-file-backed-pages",
      "pressure": pressureName,
      "complete": complete,
      "enumerationComplete": enumerationComplete && status == KERN_SUCCESS && pageStatus == KERN_SUCCESS,
      "processIds": processIds.sorted(),
      "processes": samples,
      "unavailableProcessIds": unavailable.sorted(),
      "sampledUnixMicros": Int64(Date().timeIntervalSince1970 * 1_000_000)
    ]
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
