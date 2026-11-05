# Local ModernBookNLP provider qualification

The experimental provider runs the pinned upstream ModernBookNLP joint pipeline
locally on CPU. Settings → **ModernBookNLP evaluation → Prepare and evaluate**
opts into background diagnostic analysis. It does not change existing attribution
rules, dialogue boundaries or voice selections; automatic promotion remains gated. The current work and
promotion decision belong to [#127](https://github.com/kellyjanderson/readaloud/issues/127),
under the [Character contract](https://github.com/kellyjanderson/readaloud/issues/124).
The user reported a significant attribution regression in the preceding slice;
passing storage/voice tests does not invalidate that report.

## Isolated setup

The installer uses `uv` to obtain managed standalone Python 3.11.15. Keep these
dependencies out of the MLX speech environment. An explicit interpreter argument
remains available for CLI evaluation; app packaging requires the managed runtime.
Run from the repository root, with an explicit persistent destination:

```sh
tools/install_modernbooknlp_runtime.sh "$HOME/Library/Application Support/ReadAloudProviderQA/runtime"
```

This installs pinned Python dependencies and upstream revision
`84f1f34f6f0ec7c6e9c558b4371e61ea2354d95b`, applies the narrow local-runtime patch,
and acquires checksummed model assets. The patch redirects encoder/model paths and
disables CUDA autocast on CPU. A shape correction preserves unknown trailing
quotations instead of truncating the output list and crashing the renderer; speaker
scoring and quotation segmentation are unchanged. Installed adapter hashes are checked.
The catalog is [modernbooknlp_models.json](../assets/modernbooknlp_models.json).
Hugging Face owns snapshot caching/resumption. Complete pinned snapshots are checked
locally first; the destination does not include a build or worktree identity.
Entity/coreference checkpoints use their pinned HTTPS source and SHA-256.

Validate a saved installation without network acquisition:

```sh
"$HOME/Library/Application Support/ReadAloudProviderQA/runtime/venv/bin/python" \
  tools/prepare_modernbooknlp_assets.py \
  "$HOME/Library/Application Support/ReadAloudProviderQA/runtime/assets" --offline
```

The native build embeds the separate interpreter/packages using
`embed_modernbooknlp_runtime.sh` (override `READALOUD_BOOKNLP_RUNTIME_ROOT` to change
the build input). It includes code, not model weights. Settings prepares missing
models under the actual app's Application Support `modernbooknlp/models` directory.
The shared acquisition helper reports downloaded bytes and verified file counts;
unmeasured model initialization displays its stage without a spinner. Complete
assets are checked locally first and reused across builds. Stop cancels setup or
inference; Retry preserves the current reading demand. A missing bundled runtime
produces an actionable error instead of borrowing the MLX environment. Upstream source is MIT; model/data redistribution
clearance remains separate. The pinned upstream archive includes its license.

For sandboxed macOS packaging, the build replaces Torch 2.6's OpenMP library with
the qualified arm64 LLVM OpenMP 22.1.6 artifact. The original library aborts with
`Can't open SHM2` inside the sandbox; the newer implementation handles unavailable
shared memory (see [LLVM's implementation](https://openmp.llvm.org/doxygen/kmp__runtime_8cpp_source.html)).
This preserves sandboxing and does not alter model scoring. The default build
input is `/opt/homebrew/opt/libomp/lib/libomp.dylib` and its adjacent package
`LICENSE.TXT`. Override `READALOUD_BOOKNLP_OPENMP_LIBRARY` and
`READALOUD_BOOKNLP_OPENMP_LICENSE` to supply the same artifact from another location.
Its required pre-signing SHA-256 is
`7f07009be4fb2ec519ef62f7cc864aa2412c7ece7de41c15eb89dce5eb991650`.
The build checks the hash, copies the license and signs the replacement; an absent
or changed artifact fails explicitly. A Homebrew upgrade therefore requires fresh
qualification rather than silently changing the shipped inference runtime.
End users need neither Homebrew nor a system Python: these are bundle build inputs.

## Evaluation

The app starts the worker with `--serve`: one JSON request at a time, retaining
model weights between windows. The CLI one-shot mode remains available. It validates all component hashes
before loading and forces offline Transformers/Hub use. Its source window is limited
to 16,384 UTF-16 units and 4,096 upstream tokens. Python codepoint offsets are converted
explicitly to Dart UTF-16 offsets; upstream's `byte_onset` name is misleading.
No character IDs are inferred from model-local integer IDs across windows.

`ModernBookNlpProvider` uses `dart:io` Process ownership, one admitted request, no
transport queue, a two-minute analysis deadline (30-minute cancellable setup deadline)
and bounded stdout/stderr. `ModernBookNlpAnalysis` owns one active window and one
replaceable latest demand. The controller offers the current prepared range without
waiting for setup or inference; duplicate range demand is ignored. Document replacement
revokes old publication before cancellation; Stop and shutdown drain the child.
The native Quit path waits for both NLP and MLX cleanup. Cancel revokes
publication before TERM/KILL and exit verification. Close waits for startup/inference
cleanup. The caller must validate its current work revision before applying a result;
the provider independently checks the echoed request identity and pinned model.

The Character adapter only admits exact, unambiguous named aliases already present
in the canonical registry. It preserves supplied dialogue bindings and marks unmatched
boundaries unknown; it does not invent a new character, confidence score or turn.
`WorkCharacterStore` retains selection ownership and revision admission. Arbitrary
entity reconciliation, rolling context and correction precedence require the next
integration stage before production promotion.

Run the fixed **synthetic smoke cases**, not a held-out literary benchmark:

```sh
.venv/bin/python tools/evaluate_modernbooknlp.py MODEL_ASSET_DIRECTORY --output RECEIPT.json
.venv/bin/python tools/modernbooknlp_worker_test.py
READALOUD_MODERNBOOKNLP_ROOT=MODEL_ASSET_DIRECTORY \
  tools/flutter test test/modernbooknlp_local_inference_test.dart
```

The last test defaults to this checkout's `.venv`; set
`READALOUD_MODERNBOOKNLP_PYTHON` to use another isolated runtime interpreter.
normal Flutter tests skip it when the environment variable is absent. The evaluator
can use the installed runtime interpreter instead. No model download occurs in tests.

For the native diagnostic probe, build with
`sh tools/build_macos_release.sh tools/modernbooknlp_app_smoke.dart`, copy the
resulting bundle into a disposable QA directory, change the copy's bundle ID to
`com.kellyjanderson.readAloud.residentNlpTest`, then re-sign it with
`macos/Runner/Release.entitlements` and verify with
`ruby tools/verify_macos_release_entitlements.rb APP_PATH`.
Launch the copy's executable with one new sandbox-writable JSON receipt path.
The probe rejects a production Application Support path. Its QA model cache may
be populated from existing verified assets; keep every symlink inside that copy.
It uses the real controller and reading screen with silent speech, evaluates two
windows, verifies process reuse, then Stops and restarts analysis. After the receipt,
send normal Quit to that exact app path and verify both app and reported child PIDs
have exited, including on failure. This is not an audible playback test.

The November 5 sandbox probe passed resident reuse, Stop/restart, unchanged
attribution and normal-Quit child cleanup. Its first setup rendered hundreds of
scheduled frames; that establishes continued rendering, not full keyboard/pointer
responsiveness or launch-to-audio timing. Short synthetic windows took about
0.6–0.7 seconds with approximately 4.60 GB peak child RSS. The initial bundled
OpenMP crash and successful replacement are retained separately in #127 evidence.

The first actual Mac run loaded in 11.34 seconds and inferred a short two-speaker
passage in 0.75 seconds, with approximately 4.61 GB peak process RSS. Cached loading
was about 5.5 seconds; six subsequent tiny windows took 0.66–0.75 seconds each. The first run passed five of six smoke cases; the unidentified-speaker case raised
an upstream `IndexError`. After the output-list shape correction, all six passed,
including explicit unknown preservation. Both receipts remain in the issue evidence.
Do not equate these measurements with two-second app startup, physical process-tree
memory, a held-out quality score, or smooth Fish playback.

Remaining promotion gates: independent literary and private City labels, fair
fallback comparison, explicit correction precedence, bounded rolling entities/context,
shared memory admission, startup/audio and M3 measurements. Background windows currently
produce diagnostics only; they do not yet replace future prepared speaker routes.
Provider processes are resident, but rolling book-level coreference is not implemented.
Native UI/storage/quit evidence is recorded in #127 separately from audible acceptance. Initial playback must continue
through fast discovery while deeper analysis becomes available. There is no default
neural routing switch in this slice.
