# Reader Interface and Session State

Reconciled: October 24, 2026
Status: Current source architecture; bounded reader accessibility runtime check

## Implemented structure and limitations

The Flutter screen exposes the Reader, transport, voice selection, character voice management, import/export and secondary options. Widgets consume controller state; theme tokens and bundled fonts define presentation. Existing UI guides retain design intent and are not proof of runtime behavior.

Custom transport segments expose button roles, enabled state and action labels: Back 30 seconds, Play/Pause and Forward 30 seconds. Buffering is the primary button's semantic value; its action is disabled while preparation is pending. Decorative transport children are excluded from semantics to avoid duplicate labels. Character Voices exposes a button role with its visible label. InkWell retains tap, keyboard activation and focus behavior; semantics do not introduce a second action callback or alter layout.

Widget tests cover semantic actions, buffering/playing labels, disabled state and Tab/Space activation. A bounded isolated macOS build exposed all four named buttons through native AX; agent actions opened Voice Management and started a short fixture, observed Buffering, then returned to Play with the final word highlighted. This is control/state evidence, not emitted-audio quality or exhaustive accessibility acceptance. Cold background acquisition and stale background observations remain tooling/runtime limitations; foreground launch enabled inspection and was not an application fix. Native Tab traversal showed visible focus on Character Voices and Play; Space opened the dialog and changed Play to Pause. Sustained Pause interaction was not established with the short fixture. See [the accessibility slice](https://github.com/kellyjanderson/readaloud/issues/57) for evidence and remaining acceptance.

Preferences persist voice choices/speeds, appearance, cast assignments, file-access information and resume anchors. The controller manages file-backed restoration, platform intake and watched-file refresh. Watched reload is debounced but does not guard publication with a document request generation. Preference writes are multi-key asynchronous operations rather than an explicitly serialized snapshot transaction.

Voice preview shares the engine with reader playback and pauses reading when appropriate. A selected voice change clears planning state and restarts if already playing; the buffering-time case and rapid changes need dedicated validation. These are source-review risks, not reproduced bugs in an installed build.

The ACD defines prepared document revision ownership and render-ahead assignment commits. UI changes should keep ordinary speaker transitions distinct from explicit user reassignment, and report pending versus effective choices when that behavior is implemented.

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
