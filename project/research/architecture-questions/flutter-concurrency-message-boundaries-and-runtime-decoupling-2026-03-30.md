# Flutter Concurrency, Message Boundaries, and Runtime Decoupling — 2026-03-30

Last updated: March 30, 2026
Status: Active research notes

## Topic

This document answers the architecture question that arose during Kokoro integration:

- what concurrency model `Read Aloud` should use for repeated speech work in Flutter
- whether the app needs an official message boundary for the speech subsystem
- how Dart isolates, Flutter platform channels, and native plugin queues interact
- what “fully decoupled” should mean in a Flutter desktop/mobile app

## Findings

### 1. Dart isolates are already an actor-style system

Dart concurrency is isolate-based rather than shared-memory-thread-based.

Important properties:

- each isolate has its own memory
- each isolate runs its own event loop
- isolates communicate only through message passing
- there is no direct shared mutable state between isolates

The official Dart concurrency model explicitly frames isolates as message-passing units rather than ordinary threads.

Inference for `Read Aloud`:

- if we want the speech subsystem to be truly decoupled, the clean model is actor-like
- that means commands and events, not cross-isolate object ownership

### 2. Repeated `Isolate.run` or `compute` calls are the wrong default for the speech path

Flutter’s isolate guidance distinguishes:

- short-lived isolates via `Isolate.run`
- stateful, longer-lived isolates for repeated or multi-message work

Flutter explicitly notes that repeatedly using `Isolate.run` incurs overhead from:

- spawning isolates
- copying objects across isolates

It recommends long-lived background workers when the same process runs repeatedly or yields multiple values over time.

Inference for `Read Aloud`:

- chunk-by-chunk speech preparation is not a “one isolated calculation” problem
- it is a repeated, stateful workflow
- the speech runtime should therefore use a long-lived worker boundary, not many ad hoc short-lived isolate jobs

### 3. Message boundaries must use explicit, sendable DTOs only

The Dart `SendPort.send` rules matter here.

The official docs say:

- messages can contain almost any object when isolates share code, but there are important exceptions
- sending may have linear cost over the transitive object graph
- closures can capture more state than they need

This is exactly the failure mode we hit while trying to offload boundary correction with closure-based isolate helpers.

Inference for `Read Aloud`:

- closures are not a safe architectural boundary
- worker calls should use top-level entrypoints plus plain payloads
- payloads should be ids, paths, small immutable maps, and typed DTOs
- we should avoid sending large object graphs or engine-owned objects across isolates

### 4. `compute` is useful, but it is not the architectural boundary we need

Flutter’s `compute` docs are clear:

- on native platforms, it uses a separate isolate
- on web platforms, it runs on the current event loop
- callback, message, and result all need to be sendable across isolates

That makes `compute` a utility, not a subsystem architecture.

Inference for `Read Aloud`:

- `compute` is fine for narrow helper work
- it is not a substitute for a formal runtime boundary
- it is not a reliable decoupling story for web

### 5. Plugin access in background isolates is allowed, but it has sharp limits

Flutter’s isolate documentation now explicitly supports using platform plugins in background isolates through `BackgroundIsolateBinaryMessenger`, initialized with a `RootIsolateToken`.

But the same docs also say:

- spawned isolates cannot use `rootBundle`
- spawned isolates cannot do `dart:ui` or widget work
- background-isolate platform channels cannot receive unsolicited host messages

Inference for `Read Aloud`:

- asset-backed tokenizer setup and any UI-coupled behavior must stay out of worker isolates unless we make them file-based first
- background workers can make request/response plugin calls
- the speech runtime should not depend on host-pushed streaming updates into a background isolate

### 6. Dart-side workerization alone does not guarantee a responsive app

The native Flutter embedder APIs for iOS and macOS matter here.

The official Apple embedder docs expose:

- `makeBackgroundTaskQueue` on `FlutterBinaryMessenger`
- `initWithName:binaryMessenger:codec:taskQueue:` on `FlutterMethodChannel`

That means plugin method handlers can be assigned to background task queues instead of implicitly running on the default handler thread.

Inference for `Read Aloud`:

- if a speech plugin performs heavy synchronous native work inside its method handler, a Dart isolate alone does not guarantee responsiveness
- the runtime boundary must include native queue policy, not just Dart isolate policy
- “off the UI isolate” is necessary but not sufficient

### 7. The right boundary is subsystem-local, not app-global

The research supports a formal command/event protocol around the speech subsystem.

It does not support turning the whole app into a generic message bus.

Inference for `Read Aloud`:

- the controller and reader UI can stay ordinary Flutter state owners
- the speech subsystem should become a runtime service with a strict async boundary
- this should be local to the speech runtime, not a global application event architecture

## Working Answer

The best fit for `Read Aloud` is:

### A long-lived speech runtime worker

Responsibilities:

- own repeated generation activity
- receive commands
- emit progress and completion events
- preserve runtime-local state needed for chunk generation

### A strict command/event boundary

The speech subsystem should communicate through:

- explicit commands from the controller/facade into the runtime
- explicit events from the runtime back to the controller/facade

No closures, controller references, engine instances, or UI state should cross that boundary.

### Native queue policy as part of the runtime design

The runtime boundary must include:

- background isolate setup for request/response plugin calls
- background task queues on iOS/macOS plugin handlers where supported
- explicit native async or background dispatch for heavy ONNX or file work

### File-path and id oriented exchange

Cross-boundary payloads should prefer:

- session ids
- generation ids
- chunk ids
- document ids
- file paths
- durations
- small annotation and status payloads

They should avoid:

- closures
- live controller objects
- audio buffers unless absolutely necessary
- engine-owned state

### A platform-aware interpretation

The architecture should assume:

- native Flutter platforms support true isolate offload
- Flutter web cannot rely on true isolate offload through `compute`

So the runtime façade should be stable across platforms, while implementations can differ underneath.

## Implications

### Architecture Implications

- `Read Aloud` needs an explicit speech-runtime messaging boundary as a first-class architectural layer
- the boundary should be actor-like and subsystem-local
- native plugin queue policy belongs in architecture, not as an implementation afterthought

### Specification Implications

The next specification round should include:

- speech runtime command protocol
- speech runtime event protocol
- sendable DTO contract
- runtime ownership and lifecycle
- native engine queue policy
- web fallback and capability policy

### Implementation Implications

- repeated speech work should move away from ad hoc `Isolate.run` helpers
- the runtime should become long-lived and message-driven
- boundary correction, chunk preparation, cache ownership, and native inference should live on the runtime side
- the controller should consume events and derive UI state rather than orchestrating low-level background jobs directly

## References

- Flutter Concurrency and Isolates: https://docs.flutter.dev/perf/isolates
- Dart Concurrency: https://dart.dev/language/concurrency
- `SendPort.send` documentation: https://api.dart.dev/dart-isolate/SendPort/send.html
- Flutter `compute` API: https://api.flutter.dev/flutter/foundation/compute.html
- `BackgroundIsolateBinaryMessenger`: https://api.flutter.dev/flutter/services/BackgroundIsolateBinaryMessenger-class.html
- iOS `FlutterBinaryMessenger`: https://api.flutter.dev/ios-embedder/protocol_flutter_binary_messenger-p.html
- iOS `FlutterMethodChannel`: https://api.flutter.dev/ios-embedder/interface_flutter_method_channel.html
- macOS `FlutterBinaryMessenger`: https://api.flutter.dev/macos-embedder/protocol_flutter_binary_messenger-p.html
- macOS `FlutterMethodChannel`: https://api.flutter.dev/macos-embedder/interface_flutter_method_channel.html
