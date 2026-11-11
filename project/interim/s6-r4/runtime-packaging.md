# S6 R4 runtime packaging amendment

Source #137; predecessors S6 R1/R2/R3; parent R23; baseline `6f98390`.

## Problem and decision

Fresh signed local full-app launches took 4.77–4.91 seconds, mostly before window/Dart startup. A disposable otherwise equivalent signed app with both embedded Python trees removed reached native playback position in 866.206ms. Removing runtimes is not a usable fix. The earlier nested-helper layout did not improve startup. These are native-position diagnostics, not emitted-onset acceptance or proof that compression solves the problem.

Package the existing signed, relocatable standalone MLX and ModernBookNLP runtime roots as compressed immutable resources. Resolve them lazily only when the corresponding feature needs executable Python. Completed portable-book reading must neither extract nor initialize either runtime. Both features, their dependency versions, the qualified BookNLP OpenMP library, licenses and inheritance entitlements remain present. No arbitrary system Python, target-side re-signing, quarantine removal or security-policy changes.

This is an implementation correction authorized by the user's first-launch request. It does not add multimedia, relax two-second opening-to-audible speech, exempt first-use extraction/model loading, or claim broader neural startup conformance. S7 owns later resource work and must reuse this owner.

## Packaging and identity

Existing embed scripts construct and sign the standalone roots outside the final bundle, then a shared helper produces `Resources/python-runtimes/{mlx,modernbooknlp}.zip` and adjacent bounded manifests. Do not archive the original build-machine venv. Remove obsolete expanded runtime roots only from the current build output. Preserve source runtimes and model assets.

A manifest records schema/policy, runtime ID, exact Python/package identities, executable relative path, compressed archive size/hash and sorted signed-tree entries with relative paths, types, sizes, SHA-256, executable modes and contained relative symlink targets. Hash after signing. Resource identity derives from the complete signed tree and policy; paths or package versions alone never qualify an unrelated runtime. Explicit developer runtime overrides remain explicit provenance and retain their existing caller authorization.

## Runtime ownership

Use a shared application runtime installer with at most one active installation per known runtime and no unbounded request queue. Same-identity consumers may share work through cancellable interests; no more than the two known runtime installations are active. Each producer names its runtime digest, attempt and consumer revision/session. UI state/progress projection remains on the main isolate; manifest parsing, archive/tree hashing, inventory checks and filesystem work belong to an explicit worker. Use maintained codecs/platform tools rather than a custom archive parser: macOS `ditto -x -k` is preferred for preserving executable/link metadata. The existing archive package's high-level extraction helpers swallow errors, so they cannot establish completion.

Install under sandbox Application Support `python-runtimes/v1/<runtimeId>/<signedTreeDigest>/`. Verify the archive before extraction into an attempt-private same-volume staging directory. Validate safe paths, exact extracted inventory, contained links, modes, member sizes/hashes and interpreter executable architecture/signature before publication. Only then write/flush the completion receipt and atomically rename. Never replace or mutate a published tree beneath readers. Concurrent processes may stage independently; a losing publisher validates/reuses the winner and deletes only its own staging. Corrupt published output fails visibly; this amendment adds no eviction or repair-by-overwrite.

Each consumer can cancel immediately and must suppress stale success/failure. Last-interest cancellation terminates/reaps the owned extractor, drains the validation worker and removes only its own staging. Shutdown drains owned work before app exit. Bound stage/overall deadlines and surface actionable failure. Pausing or replacing a reading/analysis request must not launch obsolete Python or speech after extraction finishes.

Progress reports actual archive bytes verified and extracted entries/bytes verified, with stage-specific totals and explicit extraction/waiting states. Verbose extractor messages alone are activity, not verified completed bytes. No fabricated percentages or premature overall completion. MLX reports through existing resource progress/close ownership; BookNLP provider creation must acquire progress/cancellation ownership before awaiting runtime installation, rather than hiding setup before its existing progress state.

## Acceptance and reconciliation

Source checks cover corrupt archives/manifests/publications, path/link/mode safety, interrupted installation, cancellation during hash/extract/verify, same-identity concurrent consumers/publishers, immutable reuse, changed runtime identity, relocation and failure cleanup. Packaging checks verify required manifests/archives and preserve executable signatures.

The exact signed full-feature candidate must demonstrate fresh opening-to-emitted-audio timing and responsive completed-book playback with zero extraction/model calls. Separately verify first-use extraction and real MLX synthesis plus real BookNLP analysis, runtime identity/path/version/entitlements, meaningful progress/cancel/replacement/Quit and no owned processes left. Retain uncached regeneration and broader audio/listening failures independently. Do not substitute compressed archive checks or a stripped diagnostic app for these gates.

Reconcile implemented behavior into runtime architecture and MLX/BookNLP setup/package docs, and record exact source/binary evidence in #137. If packaged first-use or cold-launch qualification fails, leave S6 open and preserve the failure; this amendment is not a completion waiver.
