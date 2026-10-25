# Reader Interface and Session State

Reconciled: October 24, 2026
Status: Current source architecture; bounded reader accessibility runtime check

## Implemented structure and limitations

The Flutter screen exposes the Reader, transport, voice selection, character voice management, import/export and secondary options. Widgets consume controller state; theme tokens and bundled fonts define presentation. Existing UI guides retain design intent and are not proof of runtime behavior.

Custom transport segments expose button roles, enabled state and action labels: Back 30 seconds, Play/Pause and Forward 30 seconds. Buffering is the primary button's semantic value; its action is disabled while preparation is pending. Decorative transport children are excluded from semantics to avoid duplicate labels. Character Voices exposes a button role with its visible label. InkWell retains tap, keyboard activation and focus behavior; semantics do not introduce a second action callback or alter layout.

Widget tests cover semantic actions, buffering/playing labels, disabled state and Tab/Space activation. A bounded isolated macOS build exposed all four named buttons through native AX; agent actions opened Voice Management and started a short fixture, observed Buffering, then returned to Play with the final word highlighted. This is control/state evidence, not emitted-audio quality or exhaustive accessibility acceptance. Cold background acquisition and stale background observations remain tooling/runtime limitations; foreground launch enabled inspection and was not an application fix. Native Tab traversal showed visible focus on Character Voices and Play; Space opened the dialog and changed Play to Pause. Sustained Pause interaction was not established with the short fixture. See [the accessibility slice](https://github.com/kellyjanderson/readaloud/issues/57) for evidence and remaining acceptance.

Preferences persist voice choices/speeds, appearance, cast assignments, file-access information and resume anchors. The controller manages file-backed restoration, platform intake and watched-file refresh. Watched reload is debounced and guards publication with both a watch-session identity and the current document preparation revision, including checks after asynchronous acquisition and replacement. Preference writes are multi-key asynchronous operations rather than an explicitly serialized snapshot transaction.

Voice preview shares the engine with reader playback and pauses reading when appropriate. Assignment controls display requested choices separately from the controller's effective playback snapshot. Voice Management keeps Current and Pending summaries, preparation/application/failure feedback and recovery outside the scrolling voice list. The explicit Apply and replay current chunk action warns that applying may repeat words; Retry voice change is available after failure. Initial buffering prepares the latest choices automatically and does not require Apply. Ordinary speaker routing is distinct from user assignment intent. Keyboard activation, disabled initial-buffering actions, retry and narrow enlarged-text footer scrolling have focused widget coverage; native P4 behavior remains an acceptance gate.

The reader reserves a fixed status line for current/pending/preparing/applying/failed assignment feedback. Requested voice fields name their narrator or character. Modal Close has a named action. Global reader status feedback belongs to the home route, below modal routes; it cannot cover Voice Management's header or controls. Closing the modal retains the status message for explicit dismissal on the reader. This layering is tested independently from emitted-audio acceptance. A bounded persistent native smoke using the real app/controller and a separately hashed status-only entrypoint verified Character Voices opening, an AX-named Close voice management action returning to the reader, retained status below the modal and an AX-named Dismiss status message action removing it. The footer was visible and the modal header remained unobscured. This smoke used the controller API seam before final P4 assignment wiring; it proves control/layering behavior, not assignment application or audio. Native Escape input returned an unchanged tree and remains unproven. See the P4 issue for build/probe identity and captures.

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
