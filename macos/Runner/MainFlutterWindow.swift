import Cocoa
import FlutterMacOS

private func traceStartup(_ stage: String) {
  guard ProcessInfo.processInfo.environment["READALOUD_TRACE_STARTUP"] == "1" else { return }
  NSLog("[read_aloud.startup] %@ unixMicros=%lld uptime=%.6f", stage,
    Int64(Date().timeIntervalSince1970 * 1_000_000), ProcessInfo.processInfo.systemUptime)
}

// Forward the maintained generated registration unchanged. The interval between
// registrar calls brackets the preceding plugin's synchronous registration.
private final class StartupTracingRegistry: NSObject, FlutterPluginRegistry {
  let registry: FlutterPluginRegistry
  init(_ registry: FlutterPluginRegistry) { self.registry = registry }
  func registrar(forPlugin key: String) -> FlutterPluginRegistrar {
    traceStartup("registrar \(key)")
    return registry.registrar(forPlugin: key)
  }
  func valuePublished(byPlugin key: String) -> NSObject? {
    return registry.valuePublished(byPlugin: key)
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    traceStartup("awake enter")
    let flutterViewController = FlutterViewController()
    traceStartup("FlutterViewController created")
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    traceStartup("view attached")

    if ProcessInfo.processInfo.environment["READALOUD_TRACE_STARTUP"] == "1" {
      RegisterGeneratedPlugins(registry: StartupTracingRegistry(flutterViewController))
    } else {
      RegisterGeneratedPlugins(registry: flutterViewController)
    }
    traceStartup("plugins registered")
    (NSApp.delegate as? AppDelegate)?.configureDocumentAccessChannel(
      using: flutterViewController
    )
    traceStartup("document channel configured")

    super.awakeFromNib()
    traceStartup("awake complete")
  }
}
