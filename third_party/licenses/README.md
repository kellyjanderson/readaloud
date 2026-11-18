# Third-party notice snapshot

This directory retains grants and copyright notices for the pinned dependency
state in `pubspec.lock` and `macos/Podfile.lock`. The source, version and SHA-256
of every collected text are recorded in [inventory.json](inventory.json).
Imported files preserve upstream bytes, including line endings and whitespace;
the combined display text normalizes line endings and trailing whitespace only.
[NOTICES.txt](NOTICES.txt) combines those texts for candidate packaging and
the implemented in-app notice viewer. Exact-candidate native access/content
evidence remains required. It includes development and other-platform
packages conservatively; it is not an exact linked-binary bill of materials.

The hosted Dart texts were copied from the local Pub cache for each exact locked
version. The inventory records Pub archive URLs and lockfile archive digests;
the offline checker does not authenticate those cache files against archives.
The `malsami` and `kokoro_tts_flutter` texts were additionally checked against
downloaded archives with digests equal to their lockfile archive digests.
The vendored ONNX wrapper text comes from this repository. `just_audio` 0.10.5
is now also a path override, with local player changes documented in its
`README.local.md`. Its license byte-matches both the retained text and the exact
upstream Pub archive verified against SHA-256
`9694e4734f515f2a052493d1d7e0d6de219ee0427c7c29492e246ff32a219908`.
The checker binds each vendored path description and current license bytes;
it does not treat an absent path-package archive hash as an upstream identity.
The ONNX native runtime is
covered separately by upstream v1.22.0 `LICENSE` and `ThirdPartyNotices.txt`.
The wrapper has local changes, including macOS resource ownership/tracing;
its MIT grant is preserved. No upstream copyright text was edited.

All five bundled Source Sans 3, Source Serif 4 and IBM Plex Mono files byte-match
the pinned Google Fonts revision in the inventory, whose family OFL files are
included. Regional pronunciation tables byte-match the verified `malsami` 0.0.3
archive; `tokenizer_vocab.json` matches `kokoro_tts_flutter` 0.2.0+1. The local
lexicon differs from that archive (40 versus 35 top-level entries), including
semantic differences beyond formatting. These observations do not settle the
source of other assets, local lexicon modifications or upstream data
attribution. The CMUdict grant is retained separately.

PDFium's Chromium-7520 root grant is included. Its full transitive native notice
set remains unresolved. Flutter/Dart/material-font texts and the full `sky_engine`
license bundle plus macOS release license pointer are collected for Flutter
3.41.5 from the coordinator-verified arm64 SDK. The final app's correspondence
to that SDK remains to be verified. See the
[release compliance guide](../../docs/release-compliance.md) for exact limits.
The reference Apache 2.0 text is not proof of the origin or permission of any
particular model or voice asset. No top-level Read Aloud license is inferred.

ModernBookNLP's source MIT text is extracted from the cached pinned upstream
archive after its SHA-256 matched the source catalog and installer. The LLVM
OpenMP 22.1.6 text is copied from the adjacent local license after the library
matched the build's qualified pre-signing hash. Exact sources and hashes are in
the inventory; neither text closes the optional Python/native runtime graphs or
the model/data grant review. Fish catalog/checksum and ModernBookNLP adapter/
catalog entries record tracked source identity only. Model revision/checksum
pins, public source visibility and generated-reference provenance do not
establish distribution permission. All seven existing blocker records remain.

Run `ruby tools/release_notices.rb` to check the reviewed snapshot and aggregate.
After an intentional inventory/text reconciliation, regenerate the aggregate
with `ruby tools/release_notices.rb --write`. The tool never downloads or
updates dependencies. It reports blockers and does not grant release clearance.
