# macOS candidate notices and packaging

The working authority is [#55](https://github.com/kellyjanderson/readaloud/issues/55),
under the [RC2 release contract](https://github.com/kellyjanderson/readaloud/issues/83).
This guide describes implemented tooling and its limits, not release approval.

The reviewed [inventory](../third_party/licenses/inventory.json) covers every
non-SDK entry in the pinned Pub lockfile, with development and other-platform
packages retained as a conservative superset. It records license-text hashes,
sources and identities of tracked bundled assets. Native ONNX 1.22.0 grants and
third-party notices are separate from the MIT Dart wrapper. `just_audio` 0.10.5
uses AVFoundation on macOS; Android ExoPlayer obligations are not evidence of
the shipped macOS backend. Final linked frameworks must still be inspected.

Run the local integrity checks without Flutter, CocoaPods or network access:

```sh
ruby tools/release_notices.rb
ruby tools/release_notices_test.rb
```

Lockfile, dependency identity, tracked asset, text or aggregate drift fails the
check. The ignored ONNX file is deliberately excluded from the tracked asset
snapshot; the actual candidate file is identified in the package receipt.
An integrity pass says that the reviewed snapshot has not changed. It is not
legal approval, proof that every compiled dependency has been found, or proof
that a model has permission to ship.

## Candidate staging

The coordinator owns one serialized native lane. Build and verify the integrated
ordinary macOS app with a native arm64 SDK before staging. Record its exact source
commit, Flutter/Dart/engine/Xcode/Pods versions, command and build log, model/voice
hashes, and architecture of all embedded native frameworks in #91. Use the
existing application version/signing configuration unless separately authorized;
this tooling does not select identities, alter entitlements, install or publish.

From a clean committed checkout, provide an existing app and a new output folder:

```sh
ruby tools/package_macos_candidate.rb /absolute/path/read_aloud.app /absolute/path/new-candidate
```

The tool checks the source notice snapshot, requires arm64 in the main executable,
records read-only `codesign` verification/details, copies the app using `ditto`,
and places `Open Source Notices/`, this guide and `candidate.json` beside it.
The input app and its signature are not modified. The receipt hashes every staged
app file, including actual model/voice assets, and retains all known release
blockers. It does not prove source-to-binary identity, inspect every framework
architecture, notarize, create an installer, or clear a public distribution.
Attach the exact build provenance and qualification evidence to the receipt.
Failure leaves a partial new output folder for inspection, never a replacement
of an existing candidate. A successful stage with failed signature verification
is explicitly an unverified local review candidate.

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
- #78 must provide discoverable in-app access to the notice text and wire the
  asset into Flutter. This worker provides `third_party/licenses/NOTICES.txt`;
  it does not alter UI or `pubspec.yaml`. Packaging sidecars alone do not satisfy
  #55's in-app exit criterion.
- Distribution identity, Developer ID/notarization authorization, entitlements
  and a usable artifact remain unqualified. No keychain or signing changes have
  been made. Local ad hoc candidates and public signed releases require separate
  evidence; the packaging script makes neither claim automatically.

The pinned font files byte-match Google Fonts and the corresponding OFL grants
are retained with their family copyright notices. Do not sell fonts by themselves
or change reserved font names when modifying them without following those grants.
These existing grants do not choose a license for Read Aloud's own code.
