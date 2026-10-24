# Reader Interface and Session State

Reconciled: October 24, 2026
Status: Current source architecture; runtime validation not refreshed

## Implemented structure and limitations

The Flutter screen exposes the Reader, transport, voice selection, character voice management, import/export and secondary options. Widgets consume controller state; theme tokens and bundled fonts define presentation. Existing UI guides retain design intent and are not proof of runtime behavior.

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

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use an ACD and plan.

- [desktop native menu and mobile overflow navigation](../specifications/desktop-native-menu-and-mobile-overflow-navigation.md)
- [desktop reader title chrome minimization](../specifications/desktop-reader-title-chrome-minimization.md)
- [mobile overflow menu domain grouping](../specifications/mobile-overflow-menu-domain-grouping.md)
- [studio workspace entry and reader isolation](../specifications/studio-workspace-entry-and-reader-isolation.md)
