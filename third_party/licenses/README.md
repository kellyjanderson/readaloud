# Third-party notice snapshot

This directory retains grants and copyright notices for the pinned dependency
state in `pubspec.lock` and `macos/Podfile.lock`. The source, version and SHA-256
of every collected text are recorded in [inventory.json](inventory.json).
Imported files preserve upstream bytes, including line endings and whitespace;
the combined display text normalizes line endings and trailing whitespace only.
[NOTICES.txt](NOTICES.txt) combines those texts for candidate packaging and
the future in-app notice viewer. It includes development and other-platform
packages conservatively; it is not an exact linked-binary bill of materials.

The hosted Dart texts were copied from the local Pub cache for each exact locked
version. The inventory records Pub archive URLs and lockfile archive digests;
the offline checker does not authenticate those cache files against archives.
The `malsami` and `kokoro_tts_flutter` texts were additionally checked against
downloaded archives with digests equal to their lockfile archive digests.
The vendored ONNX wrapper text comes from this repository. Its native runtime is
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
set remains unresolved. The collected Flutter/Dart/material-font texts are a
source SDK snapshot, not the actual arm64 release engine notice set. See the
[release compliance guide](../../docs/release-compliance.md) for exact limits.
The reference Apache 2.0 text is not proof of the origin or permission of any
particular model or voice asset. No top-level Read Aloud license is inferred.

Run `ruby tools/release_notices.rb` to check the reviewed snapshot and aggregate.
After an intentional inventory/text reconciliation, regenerate the aggregate
with `ruby tools/release_notices.rb --write`. The tool never downloads or
updates dependencies. It reports blockers and does not grant release clearance.
