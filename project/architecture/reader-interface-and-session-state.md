# Reader Interface and Session State

Reconciled: October 26, 2026; RC2 implementation through feature head 2734b47
Status: Current source architecture; bounded reader accessibility runtime check

## macOS task runners

The macOS runner sets `FLTEnableMergedPlatformUIThread=false` for the pinned
Flutter engine. Flutter widget state remains owned by its main Dart isolate on
the engine UI task runner. AppKit and native plugin callbacks remain on the
platform main thread. Existing platform-channel replies return to the owning
Dart isolate, and native utility work retains its explicit main-thread handoff.
The setting prevents native accessibility or panel work from sharing Flutter's
UI event loop.

Native probes record both Dart heartbeat delay and a bounded single-flight
platform-channel round trip. The latter uses the existing native footprint
handler, including its utility query and main-thread reply. Their timing and
actual menu/control interactions have separate evidence. Global heartbeat
failures retain interval phases, including startup and operator waits.

## Implemented structure and limitations

The Flutter screen exposes the Reader, transport, voice selection, character voice management, import/export and secondary options. Widgets consume controller state; theme tokens and bundled fonts define presentation. Existing UI guides retain design intent and are not proof of runtime behavior.

Custom transport segments expose button roles, enabled state and action labels: Back 30 seconds, Play/Pause and Forward 30 seconds. Buffering is the primary button's semantic value; its action is disabled while preparation is pending. Decorative transport children are excluded from semantics to avoid duplicate labels. Character Voices exposes a button role with its visible label. InkWell retains tap, keyboard activation and focus behavior; semantics do not introduce a second action callback or alter layout.

Widget tests cover semantic actions, buffering/playing labels, disabled state and Tab/Space activation. A bounded isolated macOS build exposed all four named buttons through native AX; agent actions opened Voice Management and started a short fixture, observed Buffering, then returned to Play with the final word highlighted. This is control/state evidence, not emitted-audio quality or exhaustive accessibility acceptance. Cold background acquisition and stale background observations remain tooling/runtime limitations; foreground launch enabled inspection and was not an application fix. Native Tab traversal showed visible focus on Character Voices and Play; Space opened the dialog and changed Play to Pause. Sustained Pause interaction was not established with the short fixture. See [the accessibility slice](https://github.com/kellyjanderson/readaloud/issues/57) for evidence and remaining acceptance.

Global preferences persist default voice/speeds, appearance, file-access information and resume anchors. Per-work character records and selected voices live in Application Support through `WorkCharacterRepository`; see [character persistence](character-dialogue-attribution-and-voice-casting.md#character-owner-and-persistence). The controller manages file-backed restoration, platform intake and watched-file refresh. Watched reload is debounced and guards publication with both a watch-session identity and the current document preparation revision, including checks after asynchronous acquisition and replacement. The controller serializes immutable preference snapshots through one active save and a coalesced latest pending snapshot. Older save failures cannot replace the latest status; global settings still use multiple preference keys; character files commit independently by atomic replacement, not a cross-work database transaction.

Each work file also persists its exact-source-revision associations. Temporary graph IDs can change when an unfinished source is reopened without losing its preference owner; prepared-cache loss does not remove this mapping. Canonical document reconciliation migrates choices from that owner and updates the mapping. Existing pre-mapping preferences can be recovered from one validated cached range of the same source revision, guarded by the current document revision after the worker read. Missing/corrupt evidence cannot authorize a guessed match. This reuses existing source-revision probes and the preference save pump, adds no whole-book acquisition, and does not promote partial graphs to complete content identities. Tests cover file/pasted sources, interrupted preparation, legacy recovery, cache loss, Reset, completion/replay and changed-source isolation. Native restart verification remains open under [#120](https://github.com/kellyjanderson/readaloud/issues/120).

A terminal playback error invalidates the current playback intent, clears pending Play and transport activity, and exposes the failed state while retaining the current reading word. The next Play starts a fresh attempt; stale buffering cannot consume it as Pause, and old ready callbacks cannot authorize speech. Controller regressions cover failures during buffering and playback followed by the first Play press. Native retry and listening remain separate acceptance checks.

The controller's document-preparation surface exposes stage progress and cancel/retry actions. Incremental imports publish a first prepared range while later ranges remain pending, bounded by downstream consumption; this does not itself establish time-to-first-speech. Normal Open Document accepts `.radoc` v1/v2 without ordinary source-import analysis. Optional v2 explicit cast choices are validated together with the graph, restored into a fresh preference store and kept below existing local user choices; malformed data changes neither the active document nor its stored choices. A complete checkpoint with a matching content revision or local macOS file-generation receipt can replay without source acquisition/analysis. The [pipeline](document-speech-pipeline.md) defines canonical symlink/metadata identity, nanosecond timestamp precision, bounded probe ownership and trust limits. Callback-acquired bytes still miss conservatively; captured-source hashing still reads the full input before lookup. Partial/corrupt generations rebuild from the untouched source on retry. A completed multi-range checkpoint qualifies for whole-document export: explicit controller/repository APIs merge every committed range off the main isolate into ordinary v2 `.radoc` or the audio planning graph. No save-document UI is added here. Cancellation/replacement suppresses staged publication; an export cannot use a partial graph or silently export only the active fragment. Instrumented `.radoc-v2` artifact decoding remains separate. None of these paths restore native engine resources. Native app/timing/audio acceptance remains under [#83](https://github.com/kellyjanderson/readaloud/issues/83), [#90](https://github.com/kellyjanderson/readaloud/issues/90), and [#101](https://github.com/kellyjanderson/readaloud/issues/101).

Voice preview shares the engine with reader playback and pauses reading when appropriate. Assignment controls display requested choices separately from the controller's effective playback snapshot. Voice Management keeps Current and Pending summaries, preparation/application/failure feedback and recovery outside the scrolling voice list. Selections apply automatically, with a warning that replacement may repeat words; Retry voice change is available after failure. Initial buffering prepares the latest choices automatically and does not require Apply. During active playback an edit automatically restarts from the current audible chunk start and may repeat part of it. While paused, Play with pending choices uses the retained chunk-start anchor; plain Play without edits rebuilds playback from the saved reading word, without promising exact paused-sample continuation. A newer jump or document navigation clears a retained assignment replay anchor so explicit newer navigation wins. New audio export prepares selected voices without requiring playback first. Failed changes expose Retry without presenting requested choices as effective. Ordinary speaker routing is distinct from user assignment intent. Keyboard activation, absence of a manual Apply action, retry and narrow enlarged-text footer scrolling have focused widget coverage; native P4 behavior remains an acceptance gate.

The reader reserves a fixed status line for current/pending/preparing/applying/failed assignment feedback. Requested voice fields name their narrator or character. Modal Close has a named action. Global reader status feedback belongs to the home route, below modal routes; it cannot cover Voice Management's header or controls. Closing the modal retains the status message for explicit dismissal on the reader. This layering is tested independently from emitted-audio acceptance. A bounded persistent native smoke using the real app/controller and a separately hashed status-only entrypoint verified Character Voices opening, an AX-named Close voice management action returning to the reader, retained status below the modal and an AX-named Dismiss status message action removing it. The footer was visible and the modal header remained unobscured. This smoke used the controller API seam before final P4 assignment wiring; it proves control/layering behavior, not assignment application or audio. Native Escape input returned an unchanged tree and remains unproven. See the [P4 smoke checkpoint](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395513249) for build/probe identity and captures. Integrated P4 assignment/audio/frame behavior remains unqualified by that earlier UI smoke.

## Inline preparation feedback

The output region uses Flutter `SelectionArea`; its Copy action sends the untruncated current message and all current stage counters/errors/wait reasons to the platform clipboard, independently of scrolling or Activity disclosure. Settings startup messages use `SelectableText`. The action follows existing cancel/retry/activity controls so it does not displace recovery actions. Narrow-layout, keyboard cancellation and full diagnostic copying have widget coverage under [#120](https://github.com/kellyjanderson/readaloud/issues/120); a bounded isolated native app check visibly selected error text and its full Copy result was observed in a native paste field. The user was concurrently using the desktop, so keyboard and resize interactions in that run are inconclusive. Native Command-C, synthesis retry and the user's original runtime failure remain separate verification gates; future interactive checks need a coordinated desktop window.

The default reader status region shows one current summary and the measured progress of that same operation. A current failure takes precedence over unrelated resource work or completion. Routine document/model preparation and startup errors use this region instead of a duplicate global toast. Activity is an explicit disclosure, remembered through the existing preference save owner; only opening/closing it changes the reserved region height. Its bounded history presents active work before terminal attempts, with separate identities for retries and scoped passes. Successful entries remain for six seconds, fade over 600 ms, then leave the view; current errors and active work never expire on a presentation timer. Timers are main-isolate widget state, cancelled on removal and disposal. Reduced motion removes the fade and its extra delay. None of these timers declares producer completion.

`MeasuredProgress` is shared by reader, Settings and voice-download feedback. It renders a bar only for valid completed work and a known positive denominator. Unknown, invalid or missing counters show text; a fully counted but nonterminal operation says Finishing rather than presenting premature 100%. A typed idle-demand state represents a full read-ahead window. Document cancellation does not retire an unrelated model operation.

The existing controller admits immutable [`ReaderOperation`](../../lib/src/models/reader_operation.dart) projections with producer identity, owner epoch, attempt ordinal, scope, stage, real counts, timestamp, terminal state, error and recovery information. Terminal attempts cannot revive; retries and later package-member work receive new attempts. Owner retirement removes obsolete lane metadata while retaining a bounded recent history and current terminal latches. Document supervisor, reading-stage, MLX resource and book open/save/member callbacks enter this admission boundary. Model producers publish explicit success, failure or cancellation; a nullable clear is not proof of success. The projection is application state, not a task scheduler, second event bus or persistent task database.

The summary names its selected operation while work is active, waiting on a real dependency or finalizing; completed document input cannot replace that heading with Ready. Unstarted downstream stages do not create placeholder operations. Failed reading-stage work exposes identity-guarded Clear error: its diagnostic and failed terminal latch remain in Activity, and an old control cannot dismiss a newer failure. A Save failure owns its inline status so it cannot also produce a duplicate toast. Retrying Save retires only that predecessor's owned status; unrelated messages, including identical text, retain their own visibility.

Source tests establish independent pass scopes and stale/terminal ownership, not an upstream deep-analysis producer or its actual coverage. The [S8 native evidence](../test-artifacts/s8-feedback-20261111/README.md) verifies keyboard Activity disclosure, visible focus, resize with local 2x text, unknown/known/finalizing counters from actual controlled file writes, and Copy/Clear/Save retry through the real controller. The local reduced-motion override is separate from OS-setting qualification. LaunchServices enabled native attachment after failed direct-execution controls. All functional gates completed, but a 434ms native-main response exceeded the unchanged 250ms limit; S8 acceptance remains open with [#144](https://github.com/kellyjanderson/readaloud/issues/144). The app quit normally, owners drained and no owned processes remained. Human usability cases are collected for S11.

## Validated engine sessions

The main-isolate controller publishes an immutable
[`EngineSession`](../../lib/src/models/engine_session.dart): selected identity,
validated active identity, last-working reload identity, transition epoch and
phase. The existing single replacement future retains one latest desired
selection. Its phases are stopping, unloading, acquiring, loading, validating,
active, cancelled and failed. Active is cleared before retirement and published
only after model and voice validation; last-working does not imply residency.
Settings distinguishes these identities and offers retry after failure. A failed
same-choice request can retry without pretending its released model stayed loaded.

Every replacement invalidates captured callbacks before the first retirement
await. Preview captures its engine/epoch and checks each asynchronous continuation;
an obsolete preview cannot speak through the replacement or restore old voice
state. Export and voice-library installation/refresh success and failure have
the same ownership fence. Existing resource shutdown remains the out-of-band
model/export cancellation owner and drains before constructing the next engine.
No second switch queue or scheduler is introduced.

Preferences retain narrator intent by engine identity alongside the readable
legacy selected-voice field. An incompatible saved narrator remains unresolved
instead of being silently replaced and persisted; returning to its engine restores
that choice. Fish precision remains in its saved variant ID; the scalar runtime
quantization option belongs to Voxtral. Document, reading anchor and Character
intent survive replacement. Public settings replacement cancels pending Play;
only an existing audio book's checked session/revision/intent may preserve its
original Play through its private published-engine handoff.

Barrier-controlled controller, preference, widget and book tests cover stale
success/failure, retirement callbacks, preview/export, retry, narrator intent and
book cancellation. These are source evidence, not native audio/overlap, memory
or M3 certification. M3 hardware is currently unavailable. Worker diagnostics
remain in the local app log; ordinary worker startup failures expose the actionable
message, without appending the Python traceback to the reader's status text.

## Bounded integrated P4 observations

The [assignment295 prefix audit](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395976458) observed pending Heart/effective Bella without changing current audio, Apply from word 8 and latest-only startup. The run later failed its listening timeout; cleanup reached zero resources, but the whole run is not a pass. Modal open overlapped one owned producer, Close transitioned to zero, and scroll/Recenter ran with zero. All actual actions had export inactive; menu dismissal remains unproved. Debug frame timing includes stalls and cannot establish input latency or CPU-planning acceptance.

The [e18c81d supplement](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396165816) passed automated paused pending Play, failure/retry, stale startup failure and export cancellation/drain. CUA bundle/path binding timed out: actual UI action count was zero, and `input-blocked.json` preceded diagnostic release. Readiness/finished signals do not prove input. Active-export input remains blocked and human listening remains unverified; muted PCM/transport evidence does not answer either gate.

Actual input snapshots bound the UI evidence: modal-opening endpoint snapshots at 82.7 and 108.4 seconds showed playback active and one owned preparation/refill producer; Close returned to the reader by 122.1 seconds with playback active and zero producers. Scroll and Recenter completed between 122.1 and 146.0 seconds with playback active and zero producers. Producer count does not establish CPU-heavy planning. File-menu inspection ended at 192.3 seconds after end-of-document; its dismissal remained unverified after stale CUA action IDs/unchanged state. Every actual input snapshot had export inactive, so these actions do not prove responsiveness during export. Capture intervals include automation/observation overhead and are not application latency or frame-time bounds. Exact action snapshots and images remain in the P4 probe evidence; no P4/FINAL completion follows from them.

## Source and tests

- [read_aloud_screen.dart](../../lib/src/screens/read_aloud_screen.dart)
- [reader_controller.dart](../../lib/src/controllers/reader_controller.dart)
- [reader_preferences_service.dart](../../lib/src/services/reader_preferences_service.dart)
- [document_access_service.dart](../../lib/src/services/document_access_service.dart)
- [read_aloud_theme.dart](../../lib/src/theme/read_aloud_theme.dart)
- [reader_preferences_service_test.dart](../../test/reader_preferences_service_test.dart)
- [reader_controller_playback_test.dart](../../test/reader_controller_playback_test.dart)
- [voice_management_dialog_test.dart](../../test/voice_management_dialog_test.dart)
- [widget_test.dart](../../test/widget_test.dart)

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [desktop native menu and mobile overflow navigation](../specifications/desktop-native-menu-and-mobile-overflow-navigation.md)
- [desktop reader title chrome minimization](../specifications/desktop-reader-title-chrome-minimization.md)
- [mobile overflow menu domain grouping](../specifications/mobile-overflow-menu-domain-grouping.md)
- [studio workspace entry and reader isolation](../specifications/studio-workspace-entry-and-reader-isolation.md)

## Model setup cancellation and capacity

Settings exposes complete manifest file totals and a fresh timestamped volume
measurement through [model_disk_capacity.dart](../../lib/src/widgets/model_disk_capacity.dart).
Unavailable queries retain an explicit unknown/failure state. Each opening or
manual refresh owns one bounded request; no polling queue exists.

Model Cancel immediately invalidates engine/startup/preview/playback ownership,
clears active identity and publishes cancelled while native retirement drains.
The selected and last-working identities remain intent. Double Cancel shares the
same drain. Retry rebuilds the closed owner; a later selection supersedes the
cancelled target. A cancelled owner is disposed once at replacement or final
controller disposal. No old success, error or progress can restore it, and Retry
does not request speech. Barrier and Settings tests cover these boundaries;
current running-app evidence and its limits are indexed by issue #112.

The open Settings dialog observes the controller's current selection, so its
model label, capacity descriptor and session status remain aligned when startup
or another selection path changes the engine. Native menu objects remain stable
through ordinary speech/download notifications. Only platform, export state,
complete-document availability, audio-export eligibility or live-input state
changes rebuild the native menu representation; actions and shortcuts retain
their existing semantics. This avoids repeatedly rebuilding AppKit menus during
background progress. It is not evidence that every native-main delay is fixed;
[the timing research](../research/s7-native-response-timing.md) separates that
measurement from Dart UI heartbeat and emitted audio.
