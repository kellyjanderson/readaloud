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
  private var nativeEditMenu: NativeEditMenu?
  // Main-thread owned; a request may end only its own activity.
  private var speechWorkActivities: [String: NSObjectProtocol] = [:]
  private var speechWorkStarted = 0
  private var speechWorkEnded = 0
  private var speechWorkPeak = 0
  private var terminationCleanupStarted = false
  private var terminationReplySent = false
  // Main-thread owned, one allocating/staged/publishing/cleaning export lane.
  private var audioExportStage: AudioExportNativeStage?
  private var finishTerminationAfterAudioExport: (() -> Void)?
  private static let memoryDiagnosticsLock = NSLock()
  private static var memoryDiagnosticsLogged = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // A failed inference child must surface a pipe error, not kill the GUI.
    signal(SIGPIPE, SIG_IGN)
    // FlutterAppDelegate implements will-finish-launching, but not this optional
    // NSApplicationDelegate callback. Dispatching it to super raises an exception.
    let nativeEditMenu = NativeEditMenu()
    nativeEditMenu.start()
    self.nativeEditMenu = nativeEditMenu
    configureDocumentAccessChannel()
    if ProcessInfo.processInfo.environment["READALOUD_TRACE_STARTUP"] == "1" {
      NSLog("[read_aloud.startup] Did finish launching; document access channel configured: \(documentAccessChannel != nil)")
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    nativeEditMenu?.stop()
    guard mlxLifecycleChannel != nil || audioExportStage != nil else { return .terminateNow }
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
    if let owner = audioExportStage {
      // Keep Flutter alive until its assembly worker exits and its finally
      // releases this exact native stage. An admitted publisher may finish;
      // later publication is rejected below and still follows the same drain.
      cleanup.enter()
      owner.onReleased = { cleanup.leave() }
      owner.coordinationCancellation.cancelPending()
    }
    for channel in [mlxLifecycleChannel, bookNlpLifecycleChannel].compactMap({ $0 }) {
      cleanup.enter()
      channel.invokeMethod("shutdown", arguments: nil) { _ in cleanup.leave() }
    }
    cleanup.notify(queue: .main) { finishTermination() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
      if let self, let owner = self.audioExportStage {
        // Never end Flutter while the export owner is rolling back or retaining
        // recovery files. The safety fallback resumes after its exact release.
        self.finishTerminationAfterAudioExport = finishTermination
        NSLog("[read_aloud.audio_export] Termination deadline deferred owner=\(owner.id) stage=\(owner.directory?.path ?? "allocating")")
        return
      }
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
      if call.method == "modelDiskSpace" {
        // Fixed application-owned persistent-store volume; no caller path or
        // model directory traversal. Only the platform filesystem query runs
        // on the utility queue, and channel completion returns on main.
        DispatchQueue.global(qos: .utility).async {
          do {
            guard let support = FileManager.default.urls(
              for: .applicationSupportDirectory, in: .userDomainMask
            ).first else {
              throw CocoaError(.fileNoSuchFile)
            }
            let attributes = try FileManager.default.attributesOfFileSystem(
              forPath: support.path
            )
            guard let available = attributes[.systemFreeSize] as? NSNumber else {
              throw CocoaError(.fileReadUnknown)
            }
            let snapshot: [String: Any] = [
              "availableBytes": available.int64Value,
              "checkedAtUnixMicros": Int64(Date().timeIntervalSince1970 * 1_000_000)
            ]
            DispatchQueue.main.async { result(snapshot) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "model_disk_space_unavailable",
                message: "Could not query available space on the model-store volume.", details: nil))
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
      case "createAudioExportStage":
        self.handleCreateAudioExportStage(call: call, result: result)
      case "publishAudioExportPair":
        self.handlePublishAudioExportPair(call: call, result: result)
      case "releaseAudioExportStage":
        self.handleReleaseAudioExportStage(call: call, result: result)
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

  private func handleCreateAudioExportStage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !terminationCleanupStarted, audioExportStage == nil,
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String, path.hasPrefix("/"), !path.hasSuffix("/"),
      URL(fileURLWithPath: path).pathExtension.lowercased() == "wav"
    else {
      result(FlutterError(code: "audio_export_unavailable",
        message: "Choose an available WAV destination before saving audio.", details: nil))
      return
    }
    let owner = AudioExportNativeStage(destination: URL(fileURLWithPath: path).standardizedFileURL)
    audioExportStage = owner
    DispatchQueue.global(qos: .utility).async {
      do {
        // Same Foundation facility as .radoc export; no parent-directory write
        // grant, direct-write fallback or cross-volume copy is required.
        let stage = try FileManager.default.url(for: .itemReplacementDirectory,
          in: .userDomainMask, appropriateFor: owner.destination, create: true)
        DispatchQueue.main.async {
          owner.directory = stage
          NSLog("[read_aloud.audio_export] Allocated owner=\(owner.id) stage=\(stage.path)")
          result(["ownerId": owner.id, "path": stage.path])
        }
      } catch {
        DispatchQueue.main.async {
          self.finishAudioExportOwner(owner)
          result(FlutterError(code: "audio_export_stage_failed",
            message: "Could not prepare audio at the selected location. Choose another location and try again.",
            details: String(describing: error)))
        }
      }
    }
  }

  private func audioExportOwner(_ call: FlutterMethodCall) -> AudioExportNativeStage? {
    guard let arguments = call.arguments as? [String: Any],
      let id = arguments["ownerId"] as? String,
      let owner = audioExportStage, owner.id == id,
      owner.directory != nil, !owner.busy else { return nil }
    return owner
  }

  private func handlePublishAudioExportPair(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !terminationCleanupStarted,
      let owner = audioExportOwner(call), let directory = owner.directory else {
      result(FlutterError(code: "audio_export_stale_owner",
        message: "Audio export is no longer available. Try saving again.", details: nil))
      return
    }
    owner.busy = true
    DispatchQueue.global(qos: .utility).async {
      do {
        try AudioExportPairPublication.coordinateAndPublish(stage: directory, output: owner.destination,
          cancellation: owner.coordinationCancellation)
        DispatchQueue.main.async {
          owner.busy = false
          NSLog("[read_aloud.audio_export] Published WAV/JSON owner=\(owner.id)")
          result(nil)
        }
      } catch {
        let preserve = (error as? AudioExportPairPublication.Failure)?.preservesStage == true
        DispatchQueue.main.async {
          owner.busy = false
          owner.preserveRecovery = preserve
          result(FlutterError(code: preserve ? "audio_export_rollback_failed" : "audio_export_publication_failed",
            message: preserve
              ? "Could not restore the previous export. Recovery files remain at \(directory.path)."
              : "Could not save the audio and its metadata at this location. Choose another location and try again.",
            details: String(describing: error)))
        }
      }
    }
  }

  private func handleReleaseAudioExportStage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let owner = audioExportOwner(call), let directory = owner.directory else {
      result(FlutterError(code: "audio_export_stale_owner",
        message: "Audio export cleanup no longer owns this stage.", details: nil))
      return
    }
    owner.busy = true
    let preserve = owner.preserveRecovery
    DispatchQueue.global(qos: .utility).async {
      do {
        if !preserve { try FileManager.default.removeItem(at: directory) }
        DispatchQueue.main.async {
          NSLog("[read_aloud.audio_export] Released owner=\(owner.id) recoveryPreserved=\(preserve)")
          self.finishAudioExportOwner(owner)
          result(nil)
        }
      } catch {
        DispatchQueue.main.async {
          self.finishAudioExportOwner(owner)
          result(FlutterError(code: "audio_export_cleanup_failed",
            message: "Audio export recovery files remain at \(directory.path).",
            details: String(describing: error)))
        }
      }
    }
  }

  private func finishAudioExportOwner(_ owner: AudioExportNativeStage) {
    guard audioExportStage === owner else { return }
    audioExportStage = nil
    owner.onReleased?()
    owner.onReleased = nil
    let deferred = finishTerminationAfterAudioExport
    finishTerminationAfterAudioExport = nil
    deferred?()
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

@MainActor
private final class NativeEditMenu {
  private var observation: NSKeyValueObservation?
  private var refreshPending = false

  func start() {
    let application = NSApplication.shared
    // Flutter's menu plugin assigns a new main menu on the AppKit thread.
    observation = application.observe(\.mainMenu) { [weak self] application, _ in
      MainActor.assumeIsolated {
        self?.scheduleRefresh(for: application)
      }
    }
    install(in: application.mainMenu)
  }

  func stop() {
    observation?.invalidate()
    observation = nil
  }

  private func scheduleRefresh(for application: NSApplication) {
    guard !refreshPending else { return }
    refreshPending = true
    // Wait until AppKit finishes the replacement. Rapid assignments share one
    // refresh of the current menu, and stopping makes queued work a no-op.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.refreshPending = false
      guard self.observation != nil else { return }
      self.install(in: application.mainMenu)
    }
  }

  private func install(in menu: NSMenu?) {
    guard let menu, menu.numberOfItems > 0, menu.item(withTitle: "Edit") == nil else { return }

    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
    let redo = edit.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    // Nil targets let AppKit choose and validate the focused editor's responder.
    let item = NSMenuItem(title: edit.title, action: nil, keyEquivalent: "")
    item.submenu = edit
    let fileIndex = menu.indexOfItem(withTitle: "File")
    menu.insertItem(item, at: fileIndex >= 0 ? fileIndex + 1 : 1)
  }
}

private final class AudioExportNativeStage {
  let id = UUID().uuidString
  let destination: URL
  var directory: URL?
  var busy = false
  var preserveRecovery = false
  var onReleased: (() -> Void)?
  let coordinationCancellation = AudioExportPairPublication.Cancellation()
  init(destination: URL) { self.destination = destination }
}

// Foundation-only audio-pair transaction, also exercised by the local Swift
// source test. No Flutter/app state is captured by a coordinated utility block.
final class AudioExportPairPublication {
  struct Failure: Error {
    let publication: Error
    let rollback: Error
    var preservesStage: Bool { true }
  }

  private final class SidecarPresenter: NSObject, NSFilePresenter {
    let primaryPresentedItemURL: URL?
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
      let queue = OperationQueue()
      queue.maxConcurrentOperationCount = 1
      queue.qualityOfService = .utility
      return queue
    }()
    init(output: URL, sidecar: URL) {
      primaryPresentedItemURL = output
      presentedItemURL = sidecar
    }
  }

  static func sidecar(for output: URL) throws -> URL {
    guard output.isFileURL, !output.hasDirectoryPath, output.path.hasPrefix("/"),
      output.pathExtension.lowercased() == "wav" else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    return output.deletingPathExtension().appendingPathExtension("json")
  }

  static func validatePair(output: URL, sidecar: URL) throws {
    guard try self.sidecar(for: output).standardizedFileURL == sidecar.standardizedFileURL else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
  }

  static func coordinateAndPublish(stage: URL, output: URL,
    move: @escaping (URL, URL) throws -> Void = AudioExportPairPublication.renameFile,
    cancellation: Cancellation? = nil,
    registerPresenter: (NSFilePresenter) throws -> Void = { NSFileCoordinator.addFilePresenter($0) }) throws {
    let sidecar = try self.sidecar(for: output)
    try cancellation?.requireCurrent()
    let transaction = try Transaction(stage: stage, output: output, sidecar: sidecar, move: move)
    func recover(_ publication: Error, inCurrentScope: Bool) throws {
      do {
        if inCurrentScope { try transaction.rollbackAudio() }
        else { try writeScope(output, label: "primary-rollback") { try transaction.rollbackAudio() } }
      } catch { throw Failure(publication: publication, rollback: error) }
      throw publication
    }
    do {
      try writeScope(output, cancellation: cancellation, label: "primary") {
        do { try transaction.installAudio() }
        catch { try recover(error, inCurrentScope: true) }
      }
    } catch {
      if error is Failure { throw error }
      if transaction.audioMutated { try recover(error, inCurrentScope: false) }
      throw error
    }
    // Finish primary coordination before constructing/registering the related
    // presenter. Registering inside the original future-file claim was denied
    // for new SavePanel paths even after a complete WAV existed on disk.
    do {
      try cancellation?.requireCurrent()
      let presenter = SidecarPresenter(output: URL(fileURLWithPath: output.path),
        sidecar: URL(fileURLWithPath: sidecar.path))
      try registerPresenter(presenter)
      defer { NSFileCoordinator.removeFilePresenter(presenter) }
      try writeScope(URL(fileURLWithPath: sidecar.path), presenter: presenter,
        cancellation: cancellation, label: "related-json") {
        try transaction.requireOwnedAudio()
        try transaction.publishMetadata()
      }
    } catch {
      // Foundation normally reports preparation errors before entering the
      // accessor. If it reports one after the pair committed, retain backups;
      // never undo only the WAV after related-file access has been relinquished.
      if transaction.metadataCommitted {
        throw Failure(publication: error, rollback: CocoaError(.fileWriteUnknown))
      }
      try recover(error, inCurrentScope: false)
    }
  }

  private struct Identity: Equatable {
    let device: Int64, inode: UInt64
    static func read(_ url: URL) -> Identity? {
      var value = stat()
      guard url.path.withCString({ lstat($0, &value) }) == 0 else { return nil }
      return Identity(device: Int64(value.st_dev), inode: UInt64(value.st_ino))
    }
  }

  private final class Transaction {
    let output: URL, sidecar: URL, audio: URL, json: URL, oldAudio: URL, oldJson: URL
    let move: (URL, URL) throws -> Void
    let fileManager = FileManager.default
    var audioBackedUp = false, audioPublished = false, metadataCommitted = false
    var installed: Identity?
    var audioMutated: Bool { audioBackedUp || audioPublished }
    init(stage: URL, output: URL, sidecar: URL, move: @escaping (URL, URL) throws -> Void) throws {
      try validatePair(output: output, sidecar: sidecar)
      guard stage.isFileURL, stage.standardizedFileURL != output.deletingLastPathComponent().standardizedFileURL else {
        throw CocoaError(.fileWriteInvalidFileName)
      }
      self.output = output; self.sidecar = sidecar; self.move = move
      audio = stage.appendingPathComponent("audio.wav"); json = stage.appendingPathComponent("metadata.json")
      oldAudio = stage.appendingPathComponent("previous.wav"); oldJson = stage.appendingPathComponent("previous.json")
      for url in [audio, json] {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
          throw CocoaError(.fileReadInvalidFileName)
        }
      }
    }
    func validateExisting(_ url: URL) throws {
      guard fileManager.fileExists(atPath: url.path) else { return }
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory != true, values.isSymbolicLink != true else { throw CocoaError(.fileWriteInvalidFileName) }
    }
    func installAudio() throws {
      try validateExisting(output)
      if fileManager.fileExists(atPath: output.path) {
        try move(output, oldAudio); audioBackedUp = true
      }
      try move(audio, output); audioPublished = true
      installed = Identity.read(output)
      guard installed != nil else { throw CocoaError(.fileReadNoSuchFile) }
    }
    func requireOwnedAudio() throws {
      guard installed != nil && installed == Identity.read(output) else { throw CocoaError(.fileWriteFileExists) }
    }
    func rollbackAudio() throws {
      guard audioMutated else { return }
      if audioPublished {
        try requireOwnedAudio()
        try fileManager.removeItem(at: output); audioPublished = false
      } else if fileManager.fileExists(atPath: output.path) { throw CocoaError(.fileWriteFileExists) }
      if audioBackedUp {
        try move(oldAudio, output); audioBackedUp = false
      }
    }
    func publishMetadata() throws {
      var jsonBackedUp = false
      do {
        try validateExisting(sidecar)
        if fileManager.fileExists(atPath: sidecar.path) {
          try move(sidecar, oldJson); jsonBackedUp = true
        }
        try move(json, sidecar); metadataCommitted = true
      } catch {
        let publication = error
        do { if jsonBackedUp { try move(oldJson, sidecar) } }
        catch { throw Failure(publication: publication, rollback: error) }
        throw publication
      }
    }
  }

  final class Cancellation {
    private let lock = NSLock()
    private var requested = false
    private var pending: CoordinationWait?
    func cancelPending() {
      lock.lock(); requested = true; let wait = pending; lock.unlock()
      wait?.cancelPending()
    }
    func requireCurrent() throws {
      lock.lock(); let cancelled = requested; lock.unlock()
      if cancelled { throw CocoaError(.userCancelled) }
    }
    fileprivate func track(_ wait: CoordinationWait) {
      lock.lock(); pending = wait; let cancelled = requested; lock.unlock()
      if cancelled { wait.cancelPending() }
    }
    fileprivate func untrack(_ wait: CoordinationWait) {
      lock.lock(); if pending === wait { pending = nil }; lock.unlock()
    }
  }

  fileprivate final class CoordinationWait {
    let lock = NSLock()
    var cancelled = false, admitted = false, finished = false
    let timer: DispatchSourceTimer
    let coordinator: NSFileCoordinator
    let cancelWork = DispatchGroup()
    init(_ coordinator: NSFileCoordinator, label: String) {
      self.coordinator = coordinator
      timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
      timer.schedule(deadline: .now() + 10)
      timer.setEventHandler { [weak self] in
        guard let self = self else { return }
        if self.cancelPending() {
          NSLog("[read_aloud.audio_export] Coordination wait cancelled scope=\(label)")
        }
      }
      timer.resume()
    }
    @discardableResult func cancelPending() -> Bool {
      lock.lock()
      let stop = !admitted && !finished && !cancelled
      if stop { cancelled = true; cancelWork.enter() }
      lock.unlock()
      if stop {
        DispatchQueue.global(qos: .utility).async { [coordinator, cancelWork] in
          coordinator.cancel(); cancelWork.leave()
        }
      }
      return stop
    }
    func admit() throws {
      lock.lock(); let stopped = cancelled
      if !stopped { admitted = true }
      lock.unlock(); timer.cancel()
      if stopped { throw CocoaError(.userCancelled) }
    }
    func finish() -> Bool {
      lock.lock(); finished = true; let value = cancelled; lock.unlock()
      timer.cancel(); cancelWork.wait(); return value
    }
  }

  private static func writeScope(_ url: URL, presenter: NSFilePresenter? = nil,
    cancellation: Cancellation? = nil,
    label: String, body: () throws -> Void) throws {
    let coordinator = NSFileCoordinator(filePresenter: presenter)
    let budget = CoordinationWait(coordinator, label: label)
    cancellation?.track(budget)
    defer { cancellation?.untrack(budget) }
    var coordinationError: NSError?, actionError: Error?
    var entered = false
    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { _ in
      do { try budget.admit(); entered = true; try body() }
      catch { actionError = error }
    }
    let expired = budget.finish()
    if let error = actionError { throw error }
    if let error = coordinationError { throw error }
    if expired || !entered { throw CocoaError(.userCancelled) }
  }

  static func renameFile(_ source: URL, _ destination: URL) throws {
    // FileManager.moveItem may copy across volumes. POSIX rename either commits
    // an atomic same-volume move or fails (including EXDEV), with no fallback.
    let (status, code) = source.path.withCString { sourcePath in
      destination.path.withCString { destinationPath in
        (rename(sourcePath, destinationPath), errno)
      }
    }
    if status != 0 {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
        userInfo: [NSFilePathErrorKey: destination.path])
    }
  }
}
