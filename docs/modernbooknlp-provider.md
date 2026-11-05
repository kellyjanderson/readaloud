# Local ModernBookNLP provider qualification

The experimental provider runs the pinned upstream ModernBookNLP joint pipeline
locally on CPU. It is **not enabled in the reader** and does not change the existing
attribution rules, dialogue boundaries or voice selections. The current work and
promotion decision belong to [#127](https://github.com/kellyjanderson/readaloud/issues/127),
under the [Character contract](https://github.com/kellyjanderson/readaloud/issues/124).
The user reported a significant attribution regression in the preceding slice;
passing storage/voice tests does not invalidate that report.

## Isolated setup

Python 3.11 is required. Keep these dependencies out of the MLX speech environment.
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

The reader's launch/Settings download integration and packaged Python sandbox are
still pending. This explicit evaluation installer must not be represented as an
implemented app-owned download flow. Upstream source is MIT; model/data redistribution
clearance remains separate. The pinned upstream archive includes its license.

## Evaluation

The worker consumes one JSON request and exits. It validates all component hashes
before loading and forces offline Transformers/Hub use. Its source window is limited
to 16,384 UTF-16 units and 4,096 upstream tokens. Python codepoint offsets are converted
explicitly to Dart UTF-16 offsets; upstream's `byte_onset` name is misleading.
No character IDs are inferred from model-local integer IDs across windows.

`ModernBookNlpProvider` uses `dart:io` Process ownership, one admitted request, no
additional queue, a two-minute deadline and bounded stdout/stderr. Cancel revokes
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
The first actual Mac run loaded in 11.34 seconds and inferred a short two-speaker
passage in 0.75 seconds, with approximately 4.61 GB peak process RSS. Cached loading
was about 5.5 seconds; six subsequent tiny windows took 0.66–0.75 seconds each. The first run passed five of six smoke cases; the unidentified-speaker case raised
an upstream `IndexError`. After the output-list shape correction, all six passed,
including explicit unknown preservation. Both receipts remain in the issue evidence.
Do not equate these measurements with two-second app startup, physical process-tree
memory, a held-out quality score, or smooth Fish playback.

Remaining promotion gates: preserve/report upstream error categories, independent
literary and private City labels, fair fallback comparison, explicit correction
precedence, bounded rolling entities/context, resident provider lifecycle and shared
memory admission, app-owned installation/progress, sandbox packaging, real reading
UI responsiveness, startup/audio and M3 measurements. Initial playback must continue
through fast discovery while deeper analysis becomes available. There is no default
neural routing switch in this slice.
