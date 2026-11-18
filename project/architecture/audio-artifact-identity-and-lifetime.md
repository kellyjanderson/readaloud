# Audio artifact identity and lifetime

The resident synthesis worker owns raw inference publication. Each request captures its expected prepared binding fingerprint and binding revision; both must match the resident document/voice context before lookup or inference. Assignment revision and document revision are distinct. The reusable fingerprint describes content, while request/session/generation guards describe ownership. Pending assignment behavior and native acceptance belong to [P4](https://github.com/kellyjanderson/readaloud/issues/53).

Raw identity canonically hashes model/voice content binding, engine version, exact effective double rate, normalization, capability and language, supplied tokenizer/profile synthesis identity, text, tokens and pronunciation realization. It does not trust a caller's rounded cache key. The planner also keeps the exact rate. Unchanged content can reuse a validated artifact across invocation revisions; changed bytes, tokens, profile or rate cannot alias it. Existing legacy artifacts are retained but are not accepted as new complete publications.

The MLX adapter uses its own `mlx-python-raw-v2` identity in the existing artifact
store. It includes native model/reference identities, ordered scene references,
each ordered turn's voice/text/directions,
exact rate, language, normalization/capability context, realized speak text
(including supported delivery controls), pronunciation artifacts and synthesis
identity. It excludes the caller's planner key because that key also carries
initial/resumed/continued boundary policy. The old inclusion caused a seek to
regenerate unchanged stochastic speech. Native binding validation still precedes
lookup for every scene turn; boundary derivatives still include their separate join/predecessor
context. Previously rendered v1 artifacts remain on disk; no migration deletes
or relabels them. Cache reuse proves the same rendered voice survives a replay,
not that independently generated turns have perceptually identical voices.

MLX publication passes the immutable synthesis-attempt path and expected sample
rate to the existing publication isolate. That worker reads the complete WAV,
checks its format/rate and publishes the artifact. Complete PCM is not read into
the UI isolate for this step. The attempt owner waits for publication before
cleanup, and cancellation still suppresses returned completion; a completed
immutable artifact may remain reusable after its consumer becomes obsolete.
This ownership change alone does not establish native responsiveness.

`ModelContentSnapshot` copies the mutable source to a private staging directory, hashes that copy, then publishes its digest-addressed directory. Native initialization opens the snapshot path whose bytes were hashed. A replacement of the source path cannot silently pair the old digest with newly opened model bytes. Voice vectors continue to be parsed and digested from the same byte buffer; the existing NumPy shape/type/finite validation remains in place. Snapshots are retained, and no automatic eviction is implemented.

`AudioArtifactStore` writes a private generation containing canonical mono PCM16 WAV, metadata and a complete schema manifest, flushes all files, and atomically renames the directory into its identity bucket. A hit validates schema/completeness, WAV and PCM SHA256, metadata SHA256, canonical RIFF/data sizes, format, frames and duration. Incomplete or corrupt generations are misses. A replacement gets a distinct generation path; published or queued paths are never overwritten. Publication is atomic within the local filesystem, not a claim of survival across sudden power loss. Failed writers remove only their own staging directories.

The [C03 consumer migration](https://github.com/kellyjanderson/readaloud/issues/148)
uses the existing shared `PcmFormat`, bounded RIFF scanner and header writer in
`pcm_wav.dart`/`pcm_wav_io.dart`. Artifact validation keeps its narrower policy:
nonempty mono PCM16, exactly a 16-byte fmt followed by data, no extra chunks.
The scanner validates signatures, RIFF/chunk lengths, odd padding, integer PCM,
byte rate and frame alignment; this policy then requires data at byte 44 and
ending at EOF. Native sample rates remain unchanged. Export's broader metadata
and format support is not narrowed by artifact policy. No dependency or new
asynchronous owner is introduced; the existing bounded module and package
evaluation are described in [audio export](audio-export-and-headless-execution.md).

Kokoro retains its provider-specific clipped/rounded float-to-mono-PCM16
quantization in `encodeKokoroWav`, writes samples explicitly little endian and
delegates RIFF headers to the shared writer. Boundary correction likewise
rebuilds the canonical header through that writer after trimming, preserving
the exact retained sample bytes and existing versioned onset policy.

Boundary correction runs in the runtime's ordered compute slot. Its derivative identity includes raw content, the complete versioned silence policy, initial/resumed/break context, predecessor artifact identity and predecessor trailing silence. It trims a private copy, publishes a new complete artifact, and returns that path. Raw WAV and sidecar remain unchanged. Different join contexts cannot overwrite each other's audio; a failed or cancelled predecessor clears both context records. Cancellation suppresses stale runtime publication after the compute task drains; completed immutable artifacts can remain reusable.

`AudioArtifactPins` provides an injectable shared main-isolate registry and idempotent release handles. Playback owners retain pins through native removal/clear acknowledgment; export owners retain them through assembly drain. Releasing a pin does not delete a file. There is no eviction or background cleanup of published artifacts. The engine acquires pins for corrected playback artifacts and accepted export chunks. Playback ownership is generation plus chunk; removal/reset captures the exact pin set and releases it after native acknowledgment, preserving newer same-path ownership. Export releases pins after its assembler/runtime/planner drain. The registry is main-isolate accounting, not cross-isolate shared memory; workers retain immutable publications and do not delete them. The bounded assignment probe observed pause retaining native sources/pins and stop clearing them; the [e18c81d supplement](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396165816) additionally observed 118 export pins retained during cancellation of a diagnostically held assembler, then released before replacement playback (one new playback pin), with no cancelled output/sidecar published. The hold was waiting, not CPU-heavy assembly; the store cannot infer playlist or export lifetime from synthesis completion alone.

Source validation uses private temporary bytes only. Focused tests cover exact-rate/token/resource identity, request snapshots, expected binding mismatch, incomplete/corrupt manifests, immutable derivatives under distinct predecessors, simultaneous playback/export pins, model source replacement and owned failure cleanup. Shared runtime tests verify returned corrected paths and stale completion/drain handling. Additional private-byte checks cover corrupt model-snapshot reuse rejection and simultaneous real-isolate artifact publishers; engine ownership tests cover generation-specific pin release. These are source checks, not native drain proof. Source checks do not prove native transport, acoustic continuity, perceptual quality, or assignment UI behavior; those require the independently identified running-app evidence in P4 and FINAL.

The [accepted native resource run 2](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395918850) used private fixture bytes at `25f1dfe`, a resource-harness copy repair with unchanged `295677e` product behavior. A after resident B was rejected before events/cache/inference; B reused unchanged content. Changed same-ID voice bytes missed and changed PCM; a valid appended unknown model field changed identity, loaded/inferred successfully and retained functional PCM. An incomplete publication regenerated and deliberate metadata corruption was rejected. Independent hash/RIFF/strict decoding checks and the [worker record](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395908697) establish those cases. Four native inferences, two session creates/closes and sixteen tensor releases ended at zero sessions/tensors with no native errors. The idle listening app overlapped untouched, so no isolated memory benchmark is claimed. Failed run 1 remains a copy-permission setup failure, with its unrun cases unclaimed. Playback/export-input and acoustic/FINAL acceptance remain separate.

Sources: [artifact store](../../lib/src/services/audio_artifact_store.dart), [raw identity](../../lib/src/services/kokoro_audio_identity.dart), [model snapshots](../../lib/src/services/model_content_snapshot.dart), [boundary policy](../../lib/src/services/synthesis_boundary_policy.dart), [runtime](../../lib/src/services/speech_runtime.dart), [focused tests](../../test/audio_artifact_store_test.dart).

## Durable scene publications

`RenderedSceneRepository` registers finalized native scenes through an awaited
engine callback while both raw and final artifact pins remain held. Its worker
uses the existing immutable artifact store and commits metadata only for the
current document/assignment owner. One active request is admitted; cancellation
kills and joins pure worker work before reuse. Published versions are retained.
A source/start-word index permits bounded opening lookup without enumerating the
book. Explicit publishing enumerates committed metadata sequentially.

Scene dependencies retain ordered turns, used content bindings, canonical source
directions, pronunciation/translation identity, exact rate and engine/capability
versions. Raw identity excludes ephemeral assignment revisions and predecessor
context; final derivatives retain the raw predecessor and boundary-policy version.
A changed predecessor can recalculate the next scene's derivative from retained
raw speech using the existing boundary policy, without another inference. Missing
raw/boundary evidence fails actionably. Package replay verifies content hashes;
matching IDs alone are not acoustic identity proof. No new eviction policy is
introduced. [S6 #137](https://github.com/kellyjanderson/readaloud/issues/137) owns current
native/offline/regeneration acceptance.

`RadocAudioPackage` uses the shared random-access scanner for scene WAV
validation without loading PCM. Its separate canonical PCM16 policy retains
the manifest's rate and channel count (one through eight), rejects metadata or
reordered fmt/data chunks, and compares final scene frames with the manifest.
Raw scenes retain the existing exception to that frame comparison. Each bounded
scanner read checks the existing package worker's cancellation owner; the
validation caller closes its file handle in `finally`. The one-active-request,
zero-waiting-queue admission, timeout, stale publication rejection and private
stage cleanup remain with the package worker.

Focused source fixtures compare exact Kokoro PCM bytes and duration at
24/44.1/48 kHz; artifact/trim fixtures reject structurally valid noncanonical
layouts; boundary fixtures preserve retained PCM; package fixtures preserve
native rates and one/two/eight-channel PCM while rejecting malformed lengths,
alignment, duplicate data and noncanonical layouts. These are structural and
transformation checks, not emitted-audio, responsiveness or human listening
acceptance. Those running-app gates remain with the coordinator.

## Incremental playable packets

An opted-in MLX attempt publishes immutable mono PCM16 packet WAVs alongside its
incomplete scene WAV. `SpeechAudioPacket` carries session, generation, chunk,
binding and synthesis identities plus sequence, raw frame offset and format.
The processing isolate validates these before an awaited, nonterminal
`chunkPacketReady` event. Packet count is capped at 2048 and scene duration at
600 seconds; format and contiguous frame order cannot change mid-scene.
`chunkReady` remains the sole complete-scene event. Complete publication verifies
that the finalized raw WAV contains the same packet frames; it is not queued a
second time after streaming playback.

The existing engine owns packet admission for both ordinary playback and book
repair. Queue/pin identities distinguish packet files while progress, resume and
edit ownership retain the parent scene identity. Onset correction preserves raw
frame accounting; final scene metadata retains actual predecessor/boundary
context. Unknown trailing silence remains unknown until final evidence exists.
The versioned `boundary-native-rate-v3` policy clamps frame rounding to avoid
trimming audible frames. Older derivatives keep their historical identities.

Cancellation suppresses stale packets and terminal results, then drains producer
and native queue ownership. Streamed attempt spools remain private and retained
after drain because native consumers can still reference packet paths. Pins do
not delete files. There is no spool eviction yet; the per-scene bound is not a
total disk-retention bound. Packet/source tests alone do not establish emitted
continuity, startup ceilings or human listening acceptance; see #137/#141.
