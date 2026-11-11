# S6 R6 early playable packets

Source #137/#141; parent #110 R23/R24; baseline 0489667. This corrective
implementation retains R1's complete native-scene persistence and R5's signed
runtime placement. It introduces no multimedia or advanced timing scope.

## Problem and outcome

Fish already generates PCM packets, but the worker, boundary correction,
publication and missing-scene export path gate playback on whole-scene
completion. Startup additionally requests a twenty-second lead. A prepared model
still took sixteen seconds to first audio; cold repair exhausted a saved prefix.
Consume validated immutable packets early through the existing player/queue,
while only successful finalized scenes become reusable processed output.

## Packet and completion contract

SpeechAudioPacket carries parent session/generation/chunk identity, immutable
local WAV path, packet index, raw PCM frame start/count and exact format. It
contains no source-word partition. Only canonical mono PCM16 is admitted.
Packet/frame sequence and format must remain contiguous and exact. Validate
every request/binding identity and owned path before admission. Bound one-scene
spooling by 600 seconds, 2048 packets and corresponding PCM bytes. Next-scene
credit remains the existing player's responsibility.

Packet events are nonterminal. Existing completed/chunkReady remains the only
successful full-scene signal; it includes streamed packet/frame counts, follows
final WAV validation and boundary correction, and does not enqueue the complete
WAV again after streamed playback. Cache hits/nonstreaming exports retain their
current completed-output route. Streaming is opt-in per runtime session/request,
so ordinary exports need not allocate packet files.

Python closes each private packet WAV before emitting its full identity. The
existing stdout channel pauses for short awaited validation/handoff; standard
pipe backpressure plus scene limits bound producer output. Never wait for player
credit while consuming memory/progress messages. Failure, cancellation and
shutdown invalidate packets by generation and drain the existing owned process.
Incomplete output is never a complete cache entry or package scene.

## Player, source and boundary ownership

Both ordinary synthesis and partial-book repair use one packet admission helper
inside KokoroTtsEngine, reusing playlist mutation, pins, pruning and cancellation.
Native queue/pin IDs distinguish packets. Source progress, resume and editing
identity stay with the parent scene. Before total duration exists, show the
scene anchor with unknown progress; after completion use cumulative scene frames
for the existing approximate word mapping, without moving progress backwards.
Source coverage/EOF advances only after successful scene completion and exact
delivered frame coverage. Same-scene continuations validate frame/index order;
next scene/EOF waits for the prior scene's final publication.

Apply the existing onset-silence policy once per scene, including all-silent
leading packets, and retain identical corrected PCM in the finalized scene.
Missing-scene onset uses the actual saved predecessor's raw/trailing evidence.
Later packets remain verbatim. First playback uses a small measured startup
lead; steady-state replenishment retains its independent bounded lead policy.
No guessed startup sleep or hidden preparation-clock reset is permitted.

The reader owns a missing-scene render handle: first packet, bounded packet
pull, final publication future and cancellation/drain. It plans the native scene
once and starts the existing export owner with an optional playable-packet
callback. It does not fabricate incomplete RadocAudioScene metadata/hashes.
Temporary packet paths remain alive through native playback release and producer
drain. Replacement, Pause/Stop and Quit cannot admit obsolete packets or errors.

## Proof and reconciliation

Prove first playback before held completion; sequence/identity/format rejection;
late failure and cancellation after early audio; no duplicate whole-scene replay;
stable scene progress/anchors; persisted PCM matching played packets after the
same onset policy; exact source end; bounded buffers and released pins/processes.
Repeat genuine uncached first-load and saved-prefix repair with emitted capture,
input responsiveness and normal Quit/no children. Include initialization:
R24 goal 2000ms, reusable-book hard limit 5000ms, first-load hard limit 10000ms.
Human listening remains at the already-authorized S11 final candidate gate.

The separate cold-model UI stall remains an independent measured investigation:
packet delivery alone cannot establish its cause or fix. Profile both app and
child during second load and retain failed controls. Reconcile actual behavior
into audio artifact lifetime, reader/pipeline/export architecture and user docs
with implementation, then verify release-stack integration before closing S6.
