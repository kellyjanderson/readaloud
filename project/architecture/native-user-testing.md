# Native user-testing session

The native macOS session runner is scoped by [issue #155](https://github.com/kellyjanderson/readaloud/issues/155), under [S11](https://github.com/kellyjanderson/readaloud/issues/152). It provides process and file setup for human acceptance without rebuilding the qualified application. Human judgments, source checks, emitted-audio evidence and release clearance remain separate.

## Session boundary

`tools/prepare_native_user_tests.js` combines the existing eleven case IDs with a local qualified handoff. The generated `native-session.json` names the candidate source, package manifest digest, application binary digest, QA bundle identifier, per-case arguments and environment, and supplied files. Private books, recordings, local paths and generated session data stay outside Git. The application retains its own normal sandbox container and preferences. Profile selection is by the already qualified QA bundle identifier, not a replacement `HOME` or a claim that all applications honor a profile variable.

The standalone Swift/AppKit/SwiftUI host in `tools/human_acceptance_native/` uses `NSWorkspace` launch configuration to pass document paths to the existing ordinary `lib/main.dart` argument parser. It does not rely on browser file links or assume that LaunchServices document-open AppleEvents reach Flutter. No automatic Play or listening verdict is injected. Paste-specific passages can also be copied without hunting for their source files. Supporting files are revealed with the native file viewer.

Only coordinator-declared, validated launch environment is supported. One shared test profile retains prepared models between cases; it is never silently reset. Tests requiring another profile need a separately prepared and qualified candidate/session. A changed runner does not change the product app's source identity or convert earlier native evidence into new-build evidence.

Positional arguments do not grant sandbox access. The coordinator generator
requires an existing OS-created QA container and stages verified launch-input
copies inside its dedicated qualification directory. It refuses to fabricate a
container. Originals remain in the handoff, with supporting files available for
explicit native File Open tests. Launch plans set the selected Fish engine and
offline mode; they do not refresh models or download missing assets. Before a
launch the host checks the package manifest's source/bundle identity and its
complete file inventory, including the native executable, resources, modes and
symlinks, rather than checking only the Dart framework.

## Concurrency and lifetime

The host owns one application launch/quit lane. Native UI state belongs to the main actor; file validation, hashing and persistence run off it. A request identity guards against stale launch/validation results. Existing app instances are not silently reused with different arguments or environment, and unrelated processes are never terminated. Normal Quit is requested through the application's native process handle, with observed termination before the next case. A timeout is a visible unresolved state, not permission to force-kill or claim closure. Runner shutdown must account for its owned app.

The recovery case explicitly exposes two small setup actions. They copy a digest-verified supplied invalid or valid DOCX to the same disposable `recovery-working.docx`, allowing the user to test error → repair → Retry without manipulating files by hand. Originals remain unchanged. The intentionally mutable working file has no fixed content digest; immutable sources retain theirs. Setup work is bounded and owned independently of the active app process so repair is possible while Read Aloud displays the error.

## Results and evidence

Native notes/results are saved separately from browser storage and carry the exact candidate source/package and case IDs. Browser JSON can be explicitly imported only after matching identity; a browser's private local storage is never read or cleared by the host. Exported reports do not contain manuscript text. Starting a test, launching an app, obtaining a PID or observing process exit cannot set a human pass result.

Imported browser closure is recorded as a tester attestation, separately from
native observed process exit. Export preserves that provenance. Results-folder
access stays available while the app is running so save/export cases do not
require quitting before choosing their output location.

The browser remains a manual fallback; it cannot reliably launch `.app` bundles. Its original results remain available. Native runner acceptance requires real launch with arguments/environment, visible input intake, ordinary Quit and process exit, as well as refusal and persistence checks. That evidence does not establish M3 support, startup limits, acoustic quality or distribution clearance.
