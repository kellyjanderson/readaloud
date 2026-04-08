import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let documentAccessChannelName = "read_aloud/document_access"
  private var activeSecurityScopedURLs: [String: URL] = [:]
  private var documentAccessChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    configureDocumentAccessChannel()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
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
