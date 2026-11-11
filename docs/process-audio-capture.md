# Independent CoreAudio process capture

`tools/capture_macos_process_audio.swift` is a local QA recorder for
[#142](https://github.com/kellyjanderson/readaloud/issues/142), under
[#112](https://github.com/kellyjanderson/readaloud/issues/112). It independently
captures the outgoing stereo mix of one explicitly selected CoreAudio process.
It uses no ScreenCaptureKit, microphone, virtual audio driver, playback source
changes, or physical subdevices. A private tap uses `.unmuted`; a private
tap-only aggregate consumes its input. The tool never sets a default device,
device volume or audio routing.

This observes a CoreAudio process tap, not the physical speaker. Comparing it
with ScreenCaptureKit and the exact queued source WAVs can help distinguish
capture-content loss from process-output loss. Agreement between two software
capture paths still does not establish physical speaker output or human
listening acceptance. Continuous callback timestamps alone do not establish
expected speech content. Never fill missing intervals with synthetic silence.

## Build and invoke

The implementation uses Apple-maintained CoreAudio, AVFoundation and Dispatch.
It requires macOS 14.2 or later and a supporting Apple SDK; no package install is
needed. On an Apple Silicon host, from the repository root:

```sh
mkdir -p tmp/coreaudio-capture-build
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.2 \
  tools/capture_macos_process_audio.swift \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
  -Xlinker tools/capture_macos_process_audio.Info.plist \
  -o tmp/coreaudio-capture-build/capture-process-audio
```

The embedded Info.plist supplies `NSAudioCaptureUsageDescription` and a stable
QA bundle identifier. Build validation must remain separate from runtime
permission and audio qualification. The coordinator owns any signing, prompts,
capture runs, app launches and normal Quit verification.

```sh
tmp/coreaudio-capture-build/capture-process-audio \
  APP_PID NEW_OUTPUT.wav SECONDS [STOP_FILE]
```

`SECONDS` must be finite, greater than zero and at most 300. It bounds the
session including process registration and setup, rather than starting a new
clock after initialization. The parent directory must already exist. The WAV
and all three sidecars must be new. The tool refuses to overwrite them. It
waits at most 15 seconds within that deadline for the exact PID to register with
CoreAudio, and never substitutes a different process, bundle or system mix.
Child/helper-process audio is not implicitly included.

Creating `STOP_FILE`, SIGINT or SIGTERM requests a stop. The supervisor checks
these at 100 ms intervals after native calls return. Apple's HAL functions are
synchronous. In particular, the SDK documents tap auto-start as waiting for
the first tapped audio; a native start/stop or file-system call can delay the
cooperative deadline. There is no invented promise of a hard interruption of
an in-progress HAL or kernel I/O call. A runner should retain its own bounded
process supervision and record a blocked native call as failed evidence.
The recorder does not launch or fork any process.

## Setup, callback readiness and timing

Three distinct sidecars are written beside the WAV:

- `NEW_OUTPUT.wav.armed.json` means the tap, aggregate, buffers, listeners and
  IOProc have been installed, immediately before calling `AudioDeviceStart`.
  It asserts no callback, permission, audio or interval coverage. Tap auto-start
  can wait for the target's first audio, so requiring a real-buffer readiness
  file before allowing that target to Play can deadlock a warm test.
- `NEW_OUTPUT.wav.ready.json` is published only after the first real callback
  buffer has passed finite-sample checks and been written to the WAV. It may be
  silent. It does not prove permission or intended speech. A WAV header or file
  size is not this handshake. An early readiness file cannot qualify a later
  failed final capture.
- `NEW_OUTPUT.wav.timing.json` is the final verdict, including failures, cleanup
  errors and diagnostics. The WAV remains available for diagnosis on failure;
  the process exits nonzero. Failed or absent final timing is unusable as
  successful acoustic evidence.

For a side-by-side warm test, arm the secondary CoreAudio recorder, then use
the existing ScreenCaptureKit recorder's real-frame handshake to allow Play.
Retain both captures and exact source artifacts. This setup gate is not an
opening-to-audio acceptance measurement. A primary CoreAudio setup gate can use
`armed`, but the full expected waveform still must match; `armed` cannot waive
an unobserved opening interval or qualify a quiet interval before callbacks.

The final timing uses `readaloud-app-capture-timing-v1`, preserving `appPid`,
`frames`, `sampleRate`, `signalThreshold`, `maxPacketGapSeconds`,
`firstPacketReceivedUnixMicros`, `firstSignalReceivedUnixMicros`,
`firstSignalFrame` and `firstSignalMonotonicRawNanos`. Signal means an absolute
Float32 sample exceeding 0.01; match the waveform before interpreting it as the
intended speech. Absent signal fields mean no such signal was captured, not a
permission verdict or proof the target emitted silence.

Unix and `CLOCK_MONOTONIC_RAW` timestamps are sampled on callback receipt.
First-signal timestamps name the receipt of the buffer containing that signal,
so they provide a callback receipt upper bound rather than hardware
presentation or physical speaker onset. `firstPacketSampleTime` and
`firstPacketHostTime` preserve the original CoreAudio input timestamp; host time
is in Mach host-clock ticks and is not `CLOCK_MONOTONIC_RAW` nanoseconds. The
file's frame zero is its first submitted callback, with no padded leading
interval. `maxPacketGapSeconds` is derived from callback sample times, not
receipt scheduling or the writer's execution time.

## Buffer ownership and strict failure

One session owns its process object, private tap/aggregate, IOProc, property
listeners, WAV writer and sidecars. Each run has a UUID. No shared/global tap,
writer, completion bus or alternate session can supply its results.

The HAL synchronously dispatches callbacks onto a dedicated serial callback
queue. That queue owns callback statistics, timestamp continuity and the buffer
pool cursor. It validates input layout and copies into one of 64 preallocated
`AVAudioPCMBuffer` slots. Each slot has a Dispatch semaphore taken with an
immediate deadline; the callback never waits for disk, the writer, or a free
slot. Each slot holds at most `max(4096, 4 * deviceBufferFrames)` stereo frames,
with the declared device size limited to 16384. A FIFO serial Dispatch writer
owns AVAudioFile, finite-sample scanning, signal detection and JSON readiness.
It releases a slot only after reading/writing it. Thus no more than 64 audio
buffers can be in flight and input memory cannot be reused before the copy.
These maintained platform primitives satisfy the handoff; there is no custom
unbounded scheduler or silent-drop policy.

Pool exhaustion, malformed/oversized/empty data, any non-finite sample, writer
error, device processor overload, a format change, missing timestamp flags or
a discontinuity of at least half a sample makes the capture fail. The
half-sample timestamp tolerance admits floating-point rounding; any missing or
repeated whole frame fails. Once callbacks have begun, more than one second
without a callback also fails as an unobserved interval. This watchdog does
not substitute receipt scheduling for sample-time continuity or relax any
waveform threshold. First/last host/sample/receipt timestamps and receipt gaps
remain in the final diagnostics. `droppedBuffers`, `poolOverflows`,
`deviceOverloads`, `timestampDiscontinuities`, `formatChanges`, received,
submitted and written frame/buffer counts, peak amplitude and maximum writer
lag remain inspectable. Every submitted buffer must be written. No threshold
or expected-waveform acceptance check is relaxed by this recorder.

The capture task owns cancellation and teardown. On stop, failure or deadline
it attempts `AudioDeviceStop`, destroys the IOProc, removes all listeners,
drains callback delivery and the fixed writer backlog, finalizes the WAV,
destroys the aggregate, and destroys the tap. Cleanup errors are failures.
Stale callbacks cannot write a later session; a stopped/failed callback owner
refuses new submissions and final publication waits for its owned writer.
Successful finalization reopens the Float32 PCM WAV and verifies its sample
rate, channel count and exact saved frame count. Abrupt termination such as
SIGKILL cannot run this cleanup and must never be treated as success.

## Privacy and qualification boundary

Apple's sample requires `NSAudioCaptureUsageDescription` and states that the
first recording from an aggregate containing a tap prompts for system audio
recording permission. This is separate from ScreenCaptureKit screen-recording
permission. Running the recorder can therefore prompt even on a host where
ScreenCaptureKit already works. The tool neither changes TCC state nor invokes
an unsupported permission API. A silent stream does not distinguish denied
permission from silent output. CLI identity, signing, TCC attribution, callback
availability, auto-start behavior and side-by-side content fidelity require
native qualification by the coordinator. Compilation cannot prove these.

Required native proof scenarios include exact-PID source selection with an
unrelated audible app; side-by-side expected-waveform matching through the
reported 5–10 second losses; real-buffer vs armed readiness; idle-start timeout;
STOP_FILE and SIGTERM teardown; and deliberate writer saturation proving that
a loss yields a nonzero result and a failed timing record. These are acceptance
scenarios, not claims that they were run.

Apple sources used in selecting the maintained API:

- [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
  describes private taps, aggregate input, usage description and the permission
  prompt. Its current sample-page metadata targets newer Xcode/macOS; the
  individual C tap APIs and local SDK declare macOS 14.2 availability.
- [AudioHardwareCreateProcessTap](https://developer.apple.com/documentation/coreaudio/audiohardwarecreateprocesstap(_:_:))
  specifies the API's macOS 14.2 availability.
- [AudioDeviceCreateIOProcIDWithBlock](https://developer.apple.com/documentation/coreaudio/audiodevicecreateioprocidwithblock(_:_:_:_:))
  documents synchronous callback dispatch and lifetime through IOProc destruction.
- Local Apple SDK headers `AudioHardware.h`, `AudioHardwareTapping.h` and
  `CATapDescription.h` define the process-PID qualifier, tap-only composition,
  auto-start behavior, private objects and unmuted playback semantics.
