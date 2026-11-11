# Read Aloud local adaptation

This directory vendors the complete published **just_audio 0.10.5** package,
including its license, upstream README, examples and tests. The application pins
this copy through the root `pubspec.yaml` path override. The upstream package
version and Dart/platform APIs are unchanged.

- Upstream: <https://github.com/ryanheise/just_audio/tree/minor/just_audio>
- Published package: <https://pub.dev/packages/just_audio/versions/0.10.5>
- Pub archive SHA-256 (from the installed package cache receipt):
  `9694e4734f515f2a052493d1d7e0d6de219ee0427c7c29492e246ff32a219908`
- Original `darwin/just_audio/Sources/just_audio/AudioPlayer.m` SHA-256:
  `e9debb9231e4edf7c2bfcbde041df4fd726b33b6f4545425b19738be0454d573`
- Assignment/evaluation: [S6 native continuity repair](https://github.com/kellyjanderson/readaloud/issues/137#issuecomment-6710786783),
  under [S6 R3](https://github.com/kellyjanderson/readaloud/issues/137#issuecomment-6710591303).

## Why the native patch is needed

Read Aloud extends a bounded local-WAV playlist during speech. In this upstream
version, supported playlist add/insert operations reach `enqueueFrom:`, which
removes and reinserts every future native item while preserving the current
item. Removing an already buffered future item coincided with an approximately
119 ms hole inside the currently playing scene in the coordinator's capture.
Changing AVPlayer's automatic-stall setting did not resolve that observation.
The assignment records evaluation of the maintained upstream implementation and
0.10.6 changelog; no supported API supplied the required queue preservation.
This adaptation retains the maintained player rather than replacing its
scheduling, decoding or lifecycle infrastructure.

## Exact change and ownership

Only `AudioPlayer.m` changes upstream runtime behavior. At `enqueueFrom:` entry,
a loop-off, non-loading, non-seeking call whose target is the current native
item computes the desired queue using `_order` and the existing per-source
`lazyLoading`/`TREADMILL_SIZE` rules. An existing queue must be a pointer-identical
prefix of that desired queue. Only after this check does the fast path update
the index/end state, append the missing suffix and update the end action. It
does not remove items, seek, change rate or update playback position. A prune
of an already played prefix therefore performs no native queue mutation when
AVQueuePlayer has already removed those items. Non-prefix edits, item
replacement, loading, seeking and loop modes retain the original rebuild.

Played-prefix removal also resolves the new source index from the actual native
current-item identity after rebuilding the source tree. Its removed-current
fallback compares removed old indices with one immutable old current index.
Previously, removing two predecessors from old index 2 decremented the index to
1 while inspecting old index 0, then mistook old index 1 for the current item;
the resulting enqueue skipped the still-playing source. Resolving identity also
accounts for native advancement during removal. Source/shuffle order and the
existing removed-current successor policy remain intact.

In particular, dynamically inserted URI sources retain upstream's default
non-lazy setting. The patch does not cap them to two items or change their
preparation policy. Read Aloud remains responsible for bounding work ahead.

There is no new asynchronous producer, queue, timer or ownership domain. The
existing native method-channel and player callback paths retain queue ownership
and lifecycle. Prefix computation has no player side effects; appending to a
nonempty queue does not deliberately replace the current item or trigger its
replacement observer. Automatic advancement and its existing observers remain
upstream responsibilities. Snapshot checks do not create an atomic transaction
with AVFoundation's internal playback thread; native boundary/append overlap
still needs running-app validation. No new cancellation or shutdown work is
introduced, and upstream dispose/seek/fallback behavior is retained.

## Focused verification

Run the native recording-queue test on macOS with Xcode and an installed Flutter
macOS engine framework:

```sh
FLUTTER_FRAMEWORK_DIR=/absolute/path/containing/FlutterMacOS.framework \
  third_party/just_audio/test/local_native/run.sh
```

The script compiles all vendored Objective-C sources against the selected
FlutterMacOS and system AVFoundation frameworks, then invokes the production
`enqueueFrom:` and prefix-removal methods with a recording queue. Eighteen scenarios cover preserved
future items, complete/pruned no-ops, actual shuffle order, lazy/mixed lazy
preparation, native treadmill replenishment, non-prefix reorder/removal,
pending seek, loading, both loop modes, target replacement, two-predecessor
removal, native advancement during removal, removed-current successor fallback
and shuffled removal. The batch-removal regression rejects the uncorrected
implementation. The script
cleans up its temporary executable/module cache and starts no Flutter engine,
application or audio playback. These are native compilation and queue-call
checks, not emitted-audio evidence.

Adoption still requires the coordinator's comparable running-app A/B captures,
audio order and continuity, pause/cancel/shutdown checks, bounded long traversal
and appropriate human listening. The shared Darwin source also affects iOS,
which is not qualified here. Future upstream updates should re-evaluate and
remove this patch once maintained queue preservation meets the requirement.
