# macOS candidate notices and packaging

The working authority is [#55](https://github.com/kellyjanderson/readaloud/issues/55),
under the [RC2 release contract](https://github.com/kellyjanderson/readaloud/issues/83).
This guide describes implemented tooling and its limits, not release approval. [Release #122](https://github.com/kellyjanderson/readaloud/issues/122) owns the final candidate and artifacts; the [engine support matrix](mlx-tts-engines.md#support-and-evidence) separates source/native evidence from distribution.

The [inventory](../third_party/licenses/inventory.json) covers every
non-SDK entry in the pinned Pub lockfile, with development and other-platform
packages retained as a conservative superset. It records license-text hashes,
sources and identities of tracked bundled assets. Native ONNX 1.22.0 grants and
third-party notices are separate from the MIT Dart wrapper. `just_audio` 0.10.5
is now a vendored path override with local Dart/native player changes documented
in its [adaptation record](../third_party/just_audio/README.local.md). Its retained
license byte-matches the SHA-256-verified upstream 0.10.5 Pub archive; its current
path lock entry has no archive digest. It uses AVFoundation on macOS; Android
ExoPlayer obligations are not evidence of the shipped macOS backend. Final linked
frameworks must still be inspected.

Run the local integrity checks without Flutter, CocoaPods or network access:

```sh
ruby tools/release_notices.rb
ruby tools/release_notices_test.rb
```

Lockfile, dependency identity, tracked asset, text or aggregate drift fails the
check. The ignored ONNX file is deliberately excluded from the tracked asset
snapshot; the actual candidate file is identified in the package receipt.
The checker also binds both vendored Pub path descriptions and their retained
license bytes to the collected notices. An integrity pass says that the recorded
snapshot has not changed. It is not legal approval, proof that every compiled
dependency has been found, or proof
that a model has permission to ship.

Fish catalogs/checksum metadata and ModernBookNLP adapter/acquisition/catalog
files are tracked for identity. Their revision and checksum pins do not establish
model/data grants. The exact upstream ModernBookNLP source MIT text comes from
the cached archive verified against the catalog/installer SHA-256. The LLVM
OpenMP 22.1.6 text comes from the adjacent license of the local library matching
the build's qualified pre-signing hash. These two collected texts do not close
the independent ModernBookNLP Python/Torch/Transformers/spaCy dependency graph,
the MLX/Python runtime graph, or downloaded model/data and reference-voice
distribution obligations. Candidate runtime manifests and packaged license
files still require reconciliation against their actual contents.

## Candidate staging

The coordinator owns one serialized native lane. Build and verify the integrated
ordinary macOS app with a native arm64 SDK before staging. Record its exact source
commit, Flutter/Dart/engine/Xcode/Pods versions, command and build log, model/voice
hashes, and architecture of all embedded native frameworks in #91. Use the
existing application version/signing configuration unless separately authorized.
The build tool creates a unique QA bundle identifier and records its allowlisted
environment and Xcode override; it does not authorize public signing or publication.

Before staging an MLX-capable app, verify its declared [packaged runtimes](mlx-tts-engines.md#local-macos-release-packaging), exact manifests/native roots and model reuse. A build that omitted the optional MLX runtime is Kokoro-only; staging cannot turn it into a Drama-capable app. Full candidate setup also includes the independent [ModernBookNLP prerequisites](modernbooknlp-provider.md).

From a clean committed checkout with the verified SDK's `flutter` on `PATH`, use
the tool's attested build and smoke protocol. The build app output, receipt and
candidate output must be fresh paths:

```sh
ruby tools/package_macos_candidate.rb build /absolute/path/read_aloud.app /absolute/path/BUILD.json -- flutter build macos --release
ruby tools/package_macos_candidate.rb profile-preflight /absolute/path/read_aloud.app /absolute/path/BUILD.json > /absolute/path/EMPTY.json
ruby tools/package_macos_candidate.rb smoke-template /absolute/path/read_aloud.app /absolute/path/BUILD.json > /absolute/path/SMOKE.json
```

Capture profile absence before first launch, then retain that proof in the
matching OS-created QA container. Complete the smoke receipt with exact build/
bundle identity, observations and evidence, including native notice access and
content, synthesis output and a separate live playback capture. Follow the
protocol in [the tool](../tools/package_macos_candidate.rb); pending or failed
steps, missing isolation evidence and stale inputs reject packaging.

```sh
ruby tools/package_macos_candidate.rb package /absolute/path/read_aloud.app /absolute/path/new-candidate /absolute/path/BUILD.json /absolute/path/SMOKE.json
```

The tool checks source notices, clean source/assets, fresh build attestation,
exact bundled assets, arm64-only executable/App/Flutter binaries, strict signature
verification and packaged Python manifests. It copies with `ditto`, rechecks the
bundle and receipts, and retains `Open Source Notices/`, this guide, build log,
evidence and `candidate.json`. It does not modify the input app or its signature.
These checks bind the recorded build inputs and staged bytes; they do not prove
reproducible compilation, inspect every transitive framework's license coverage,
notarize, create an installer or clear public distribution. Final timing,
continuity, human and release acceptance remain separate. Failure can leave a
partial new output folder for inspection and never replaces an existing candidate;
failed signature verification rejects staging.

## Remaining release blockers

- The owner has not selected a top-level project grant. Public repository
  visibility is insufficient to license the application for redistribution.
- Identify exact packaged ONNX/voice origins, source revisions, transformations
  and grants, and check that distribution's `NOTICE` obligations. The upstream
  [Kokoro model card](https://huggingface.co/hexgrad/Kokoro-82M) declares Apache 2.0, but the setup guide permits multiple
  sources and does not identify the actual conversion/voice bytes.
- Review upstream data attribution in the matching `malsami` regional tables
  and `kokoro_tts_flutter` tokenizer, which byte-match SHA-256-verified locked
  archives. The local `lexicon.json` differs semantically from that Kokoro
  package (40 versus 35 top-level entries); document its modifications and
  source. Do not infer upstream data permission solely from a wrapper's MIT label.
- Obtain the complete notices for code compiled into the pinned PDFium
  `v144.0.7520.0-20251111-190355` XCFramework. Its root BSD grant and the plugin's
  MIT grant alone do not cover all Chromium/PDFium transitive components.
- Flutter 3.41.5 engine notices are collected from the coordinator-verified arm64
  SDK, including its full `sky_engine` license bundle. Reconcile the actual
  candidate's SDK/engine and linked runtime versions with these notices and locks.
- [#78](https://github.com/kellyjanderson/readaloud/issues/78) provides the
  implemented [Open Source Notices screen](../lib/src/screens/open_source_notices_screen.dart),
  discoverable reader-menu route and `NOTICES.txt` Flutter asset declaration.
  Exact final-candidate native screen/content/access evidence remains a gate;
  source and widget checks alone do not satisfy #55's in-app exit criterion.
- Complete the MLX and independent ModernBookNLP runtime notice inventories,
  including transitive native components, and review Fish/downloaded analysis
  model/data and synthetic reference-voice distribution obligations. Collected
  source/OpenMP texts and tracked asset identities do not close this gate.
- Distribution identity, Developer ID/notarization authorization, entitlements
  and a usable artifact remain unqualified. No keychain or signing changes have
  been made. Local ad hoc candidates and public signed releases require separate
  evidence; the packaging script makes neither claim automatically.

The pinned font files byte-match Google Fonts and the corresponding OFL grants
are retained with their family copyright notices. Do not sell fonts by themselves
or change reserved font names when modifying them without following those grants.
These existing grants do not choose a license for Read Aloud's own code.
