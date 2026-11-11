# Native response timing and trace interpretation

Observed November 11, 2026 on Apple M5 Max / 128 GiB, macOS 27.0.1.
Owning design: [S7 #112](https://github.com/kellyjanderson/readaloud/issues/112).
Native responsiveness investigation: [#144](https://github.com/kellyjanderson/readaloud/issues/144).
The observations below use production source `ffd6d64`; they are not a general
platform benchmark or a claim of M3 qualification.

## What the measurements establish

The QA probe admits one main-thread method-channel request at a time. A passing
Dart UI-isolate heartbeat does not prove native-main responsiveness. In v13,
715.024 ms elapsed before native handler entry and 0.117 ms after entry. A
separate actual Settings Cancel/Retry and A/B/A run, v16, passed at 35 ms native
maximum and 3 ms UI heartbeat. A later passing case does not erase an earlier
intermittent failure.

Instruments v20 records an actual main-thread Hang from trace-relative
10.173002916 to 11.013622708 seconds, duration 840.619792 ms. The corresponding
request-to-entry window maps nominally to 10.177493–11.018868 seconds, overlapping
836.129708 ms of that Hang. The native handler returned 77 microseconds after
entry. The displayed trace start has millisecond resolution; no finer same-instant
wall/Mach clock bridge was exported. Treat the alignment conservatively as
approximately ±1 ms, independently of any unassessed wall-clock adjustment.

Six CPU samples during the Hang show main-dispatch MediaToolbox/Core Animation
transaction commits and AVPlayerItem track/availability notifications. Default
Time Profiler recording excluded waiting threads and context switches. These
samples identify work present in the interval, not the dominant blocking owner.
Run-loop `waiting_for_events` intervals do not include waits inside framework
calls. The sanitized audit is retained with
[native evidence](../test-artifacts/s7-m5-r3-20261111/README.md).

The earlier 200 ms pending marker plus runner polling and sampler attachment
started v17 samples after the delayed handlers had already entered. Idle stacks
from those samples cannot explain the preceding delay. Profiled runs remain
diagnostic; they do not replace unprofiled 250 ms acceptance checks.

## Maintained platform and library boundaries

The pinned Flutter run-loop implementation rearms a CF timer for positive-delay
tasks and explicitly signals/wakes for immediate tasks. That distinction alone
does not establish a lost wakeup: Apple's published CF implementation explicitly
wakes the target loop when resetting a timer from another thread. The published
CF implementation is historical and does not prove macOS 27 internals. No
Flutter scheduling patch follows from this observation.

The application and original QA player explicitly requested eager preparation.
The maintained `just_audio` lazy-preparation option is already implemented by
the vendored native queue and bounds its treadmill to current plus next item.
This is an available application policy, not a custom scheduler. Whether it
resolves a specific hang or preserves complete packet continuity requires the
same native/acoustic evidence; the source setting alone proves neither.

The QA-only lazy-preparation experiment v23 still recorded a 690 ms active-app
native delay. It therefore does not justify changing the production setting.
Independent ScreenCaptureKit and CoreAudio recordings contain identical PCM
over their common acoustic interval. Both replace audible source material with
199.3125 ms of exact zeros in v23, and 21.0625 ms in v17. Global waveform searches
do not recover those full references at the unchanged 0.98 threshold. Adjacent
anchors retain their original timing; these observations are not explained by
an analysis-window placement error or a gain-only change. The v23 hole overlaps
the native delay, while v17's hole does not overlap a logged delayed request.
This establishes a shared recorded-output defect in those cases, not its cause
or what a physical listener heard. Sanitized measurements accompany the native
evidence; the historical v5 losses remain independently unresolved.

## References

- [Pinned FlutterRunLoop source](https://raw.githubusercontent.com/flutter/flutter/052f31d115eceda8cbff1b3481fcde4330c4ae12/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterRunLoop.swift).
- [Apple published CFRunLoop implementation](https://raw.githubusercontent.com/apple-oss-distributions/CF/main/CFRunLoop.c).
- [Apple: Understanding hangs in your app](https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app).
- [Maintained player option](../../third_party/just_audio/lib/just_audio.dart) and
  [native treadmill](../../third_party/just_audio/darwin/just_audio/Sources/just_audio/AudioPlayer.m).

Earlier missing-audio ScreenCaptureKit captures are tracked separately in
[#142](https://github.com/kellyjanderson/readaloud/issues/142). A timed main hang,
a player position, and an emitted-waveform match answer different questions.
Do not infer a shared cause without comparable evidence.
