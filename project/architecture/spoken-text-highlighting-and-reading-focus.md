# Spoken Text Highlighting and Reading Focus

Reconciled: October 24, 2026
Status: Current source architecture; runtime validation not refreshed

## Implemented structure and limitations

Player progress is mapped to spoken selections and display positions. The reading surface renders highlights and follow-along state; user scrolling can suspend following and the recenter control restores it.

The controller already coalesces follower updates. Healthy/low/critical buffer-pressure policies use 100/180/250 ms intervals and soft word-drift thresholds of 2/3/4; a ten-word drift triggers hard resynchronization. Pending updates are flushed at relevant transport boundaries. The claim that follower coalescing remained wholly unimplemented was stale.

Follower updates should remain subordinate to audio; the presence of these policies does not prove smooth playback under every document/rendering load. Long-session UI/audio integration measurements remain pending. Windowing expensive display preparation and keeping bounded UI updates are part of the execution-placement review.

## Source and tests

- [reader_controller.dart](../../lib/src/controllers/reader_controller.dart)
- [spoken_selection_mapper_service.dart](../../lib/src/services/spoken_selection_mapper_service.dart)
- [document_surface.dart](../../lib/src/widgets/document_surface.dart)
- [reading_focus_state.dart](../../lib/src/models/reading_focus_state.dart)
- [spoken_selection_mapper_service_test.dart](../../test/spoken_selection_mapper_service_test.dart)
- [document_surface_test.dart](../../test/document_surface_test.dart)
- [reading_focus_recenter_button_test.dart](../../test/reading_focus_recenter_button_test.dart)

Tests listed here are evidence locations, not a claim that every case was rerun for this page. The pinned native arm64 Flutter 3.41.5 / Dart 3.11.3 toolchain is runnable; the earlier Intel SDK failure is historical. See the [evidence index](README.md#evidence-and-acceptance-limits) for bounded source/native results.

## Design and remaining acceptance

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/spoken-text-highlighting-and-reading-focus.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [follower progress coalescing and drift resynchronization](../specifications/follower-progress-coalescing-and-drift-resynchronization.md)
- [playback progress and jump mapping](../specifications/playback-progress-and-jump-mapping.md)
- [reading focus follow policy](../specifications/reading-focus-follow-policy.md)
- [spoken text selection and display mapping](../specifications/spoken-text-selection-and-display-mapping.md)
