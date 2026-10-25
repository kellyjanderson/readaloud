# Reader Interface and Session State

Reconciled: October 25, 2026; P4 production lineage 295677e
Status: Current source architecture; bounded reader accessibility runtime check

## Implemented structure and limitations

The Flutter screen exposes the Reader, transport, voice selection, character voice management, import/export and secondary options. Widgets consume controller state; theme tokens and bundled fonts define presentation. Existing UI guides retain design intent and are not proof of runtime behavior.

Custom transport segments expose button roles, enabled state and action labels: Back 30 seconds, Play/Pause and Forward 30 seconds. Buffering is the primary button's semantic value; its action is disabled while preparation is pending. Decorative transport children are excluded from semantics to avoid duplicate labels. Character Voices exposes a button role with its visible label. InkWell retains tap, keyboard activation and focus behavior; semantics do not introduce a second action callback or alter layout.

Widget tests cover semantic actions, buffering/playing labels, disabled state and Tab/Space activation. A bounded isolated macOS build exposed all four named buttons through native AX; agent actions opened Voice Management and started a short fixture, observed Buffering, then returned to Play with the final word highlighted. This is control/state evidence, not emitted-audio quality or exhaustive accessibility acceptance. Cold background acquisition and stale background observations remain tooling/runtime limitations; foreground launch enabled inspection and was not an application fix. Native Tab traversal showed visible focus on Character Voices and Play; Space opened the dialog and changed Play to Pause. Sustained Pause interaction was not established with the short fixture. See [the accessibility slice](https://github.com/kellyjanderson/readaloud/issues/57) for evidence and remaining acceptance.

Preferences persist voice choices/speeds, appearance, cast assignments, file-access information and resume anchors. The controller manages file-backed restoration, platform intake and watched-file refresh. Watched reload is debounced and guards publication with both a watch-session identity and the current document preparation revision, including checks after asynchronous acquisition and replacement. The controller serializes immutable preference snapshots through one active save and a coalesced latest pending snapshot. Older save failures cannot replace the latest status; underlying storage still uses multiple keys rather than a transactional database.

Voice preview shares the engine with reader playback and pauses reading when appropriate. Assignment controls display requested choices separately from the controller's effective playback snapshot. Voice Management keeps Current and Pending summaries, preparation/application/failure feedback and recovery outside the scrolling voice list. The explicit Apply and replay current chunk action warns that applying may repeat words; Retry voice change is available after failure. Initial buffering prepares the latest choices automatically and does not require Apply. During active playback an edit retains current audio; explicit Apply restarts from the current audible chunk start and may repeat part of it. While paused, Play with pending choices uses the retained chunk-start anchor; plain pause/resume without edits preserves ordinary resume behavior. A newer jump or document navigation clears a retained assignment replay anchor so explicit newer navigation wins. New audio export is refused until pending choices are applied. Failed changes expose Retry without presenting requested choices as effective. Ordinary speaker routing is distinct from user assignment intent. Keyboard activation, disabled initial-buffering actions, retry and narrow enlarged-text footer scrolling have focused widget coverage; native P4 behavior remains an acceptance gate.

The reader reserves a fixed status line for current/pending/preparing/applying/failed assignment feedback. Requested voice fields name their narrator or character. Modal Close has a named action. Global reader status feedback belongs to the home route, below modal routes; it cannot cover Voice Management's header or controls. Closing the modal retains the status message for explicit dismissal on the reader. This layering is tested independently from emitted-audio acceptance. A bounded persistent native smoke using the real app/controller and a separately hashed status-only entrypoint verified Character Voices opening, an AX-named Close voice management action returning to the reader, retained status below the modal and an AX-named Dismiss status message action removing it. The footer was visible and the modal header remained unobscured. This smoke used the controller API seam before final P4 assignment wiring; it proves control/layering behavior, not assignment application or audio. Native Escape input returned an unchanged tree and remains unproven. See the [P4 smoke checkpoint](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395513249) for build/probe identity and captures. Integrated P4 assignment/audio/frame behavior remains unqualified by that earlier UI smoke.

## Bounded integrated P4 observations

The immutable `295677e` probe recorded requested Heart/effective Bella during full-buffer playback while the current source/hash remained unchanged. Explicit Apply captured `chunk_s_2` start word 8 and acknowledged the replacement from that anchor; held initial A/B/C startup acknowledged only the latest C. Pause retained pins/native sources, then stop cleared sources and pins. These are automated phase observations, not a terminal run acceptance: the app was kept alive at the human listening fixture, with supplemental failure, export-input and frame analysis pending. No listening outcome is inferred from PCM or transport state.

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
