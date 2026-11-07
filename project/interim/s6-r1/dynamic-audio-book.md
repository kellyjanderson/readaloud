# S6 R1 architectural delta

Source: #137, parent #110 R23. Baseline: 1d7fe27.

## Problem and outcome

Current `.radoc-v4` retains prepared text, annotations, Character evidence and voice intent, but rendered WAVs remain in private caches. Reopening also initializes synthesis before it knows whether usable audio exists. A portable audio book must retain both reusable processing and rendered output. A completed copied book must play offline without an installed model; a partially rendered book must expose its gaps and resume through the existing synthesis pipeline. Changed directions or Character voices invalidate affected scenes without destroying unrelated valid audio.

## Format and existing infrastructure

Keep the `.radoc` extension and legacy JSON v1–v4 reads. Introduce an explicit `read-aloud-audio-book` / `radoc-v5` ZIP envelope. Use the already-pinned archive 4.0.9 library for ZIP directory/encoding and platform streaming DEFLATE, reusing the existing bounded member-read pattern in DocumentImportService. Do not use permissive generic extraction or rely on archive's disabled CRC verification.

The envelope has a bounded versioned manifest plus independently checksummed prepared-range JSON, analysis records and native scene WAV members. Range payloads reuse current prepared-document codecs and Character ownership; no second text/parser/attribution model. The manifest records ordered source word coverage, preparation versus rendering completeness, global work/document identity, retained voice intent, scene dependencies and actual audio format/frame counts. Member names are relative identifiers; absolute cache paths, process handles and local model locations are never package dependencies. External source URIs may be retained only as descriptive provenance, never required for replay.

Prepared ranges and audio are read and admitted incrementally on demand. Complete metadata/PCM must not be loaded into the UI isolate. ZIP directory metadata is worker-owned; bound counts, sizes and emitted decompression bytes. A small initial manifest/range must suffice for first display and audio admission. Explicit export may enumerate committed ranges sequentially, but partial preparation must not be labeled complete. Partial rendering with complete prepared content is valid; an uncovered source region is a gap, not EOF.

## Rendered scenes and selective reuse

Store one record per native synthesis scene, retaining ordered NativeSpeechTurn source spans, Character/voice identities and canonical directions. A scene is the indivisible regeneration unit. Keep stable source identity distinct from the dependency digest. Dependencies include source text/normalization, canonical directions and pronunciation decisions, resolved voice intent for every turn, model/reference content identities, engine/capability versions and effective synthesis rate. Ephemeral assignment/session revisions govern admission only; they must not invalidate portable audio by themselves.

Keep raw rendered speech reusable independently of neighbor boundary correction. Where a boundary derivative depends on the previous scene, changing that predecessor invalidates the derivative, not the following scene's raw synthesis. Existing raw/derivative artifact identities remain authoritative; preserve provenance rather than infer it from filenames. Packaging must retain the audio needed to reuse those dependencies correctly. Do not call matching reference IDs proof of acoustic identity.

Automatically register finalized output while existing artifact pins protect it. Publication uses the existing durable artifact/repository machinery, with bounded worker copying/hashing and metadata commits. A canceled attempt cannot remove committed output. Changes to voice/direction produce a new captured intent revision and compare scene dependencies; unaffected committed audio remains available. Missing/invalid audio enters the existing model/resource/synthesis path only when demanded, with a truthful regeneration wait/failure.

## Playback and startup integration

Add an immutable rendered-audio request/capability alongside existing TtsSpeakRequest. Extract player-only initialization from KokoroTtsEngine and reuse its player, playlist mutation ownership, queue, progress callbacks, reset barrier and normal shutdown. Do not create another player or synthesized-speech implementation. The controller admits validated rendered coverage before synthesis-specific readiness/binding checks; manifest identity and current playback intent own acknowledgment. A fully rendered book must not call engine model initialization, voice loading, binding preparation or inference.

Document intake/startup must establish whether it has a rendered book before eager model preparation. A gap can demand synthesis; merely opening a valid complete book cannot. Existing text/legacy-book startup remains supported. Native `.radoc` file association is added without broadening sandbox entitlements. No advanced alignment is introduced: retain existing basic source/audio spans and honest approximate highlighting.

## Ownership, failure and cancellation

Controller UI state remains main-isolate owned. A package supervisor owns one active worker request, no implicit waiting queue, immutable request/revision identity and bounded input/output messages. Copying, decompression, checksums, JSON and archive operations are worker-owned. Existing artifact pins outlive admitted copying; final commit follows an explicit current-owner check. Cancellation/replacement suppresses stale success and failure, stops further bounded I/O and drains the worker before reuse. Shutdown joins package owners and the existing player/native owners.

Export stages beside the destination and publishes one complete ZIP by atomic rename after flush and current-owner admission. Preserve original inputs and prior valid outputs on cancellation/failure. Import validates exact schemas and member references, duplicate/aliased names, traversal/absolute/backslash paths, symlinks, compression, sizes/hashes, source identity and ordered non-overlapping coverage. A corrupt later member must fail actionably when demanded and never be treated as completed audio. No untrusted member name becomes an unrestricted filesystem destination. Unknown future versions fail visibly; never downgrade by discarding intent.

## Acceptance and reconciliation

Source tests cover copied package round trips, prepared/analysis/Character intent retention, complete/partial coverage, wrong voice/direction dependencies, missing/corrupt members, traversal/duplicates/size bounds, atomic cancellation and stale-owner outcomes. A complete-book controller test uses an engine whose model initialization, voice loading, resource binding and inference throw; valid audio must play with zero such calls. Voice/direction edits must regenerate affected native scenes while unaffected raw hashes stay equal. Pause/replacement must suppress late audio after blocked file or player work.

Running-app acceptance opens a copied package through the normal route with unavailable models, measures launch-to-audio from process opening, captures actual emitted continuity and verifies source ending, controls and normal Quit/no children. Test a partial render gap and selective regeneration, then reopen to demonstrate reuse. Human listening establishes expression/voice identity separately. Existing startup/S3 failures remain explicit until corrected, not waived by packaging or source tests.

Reconcile document-speech-pipeline, audio-artifact-identity-and-lifetime, audio-export-and-headless-execution, reader usage and format guidance with implemented behavior in the final PR. Keep #137 open until required acceptance/reconciliation reaches the declared release chain; no merge or publication authorization is inferred.
