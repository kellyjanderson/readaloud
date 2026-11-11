# Local ModernBookNLP provider qualification

The experimental provider runs the pinned upstream ModernBookNLP joint pipeline
locally on CPU. Settings → **ModernBookNLP evaluation → Prepare and evaluate**
opts into background character refinement. Completed, source-matched quotations
can refine newly built future reading routes. Existing heuristic rules and turn
boundaries stay intact, explicit voice choices win, and already captured speech
keeps its original routing. The current work and
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
the build input). It assembles/signs the standalone tree outside the bundle and
packages Python/data as `Resources/python-runtimes/modernbooknlp.zip` plus a
schema-2 content manifest. All Mach-O code and adjacent Metal resources remain
in `Resources/python-runtimes/modernbooknlp-native/`, including the qualified
OpenMP binary; licenses remain in the data inventory. It does not archive the
build venv. First provider creation owns progress/cancellation before awaiting
verification and extraction into Application Support
`python-runtimes/v2/modernbooknlp/<signed-tree-digest>-<bundle-location-digest>/`.
This immutable data view has explicit manifest-owned links to verified bundled
native files. The provider's own child receives this home through `PYTHONHOME`,
independently of MLX; explicit injected interpreters receive no inferred home.
The shared installer verifies current bundled targets, archive bytes, exact
inventory, links, modes, file hashes and the signed
arm64 interpreter before atomic immutable publication. Stop/replacement cancels
setup and drains its extractor/validation lifetime; damaged published trees fail
visibly and are never overwritten. App relocation creates a new view without
rewriting published links; removed/changed native targets require reinstalling
the app. No native code is extracted or re-signed. Saved portable-book analysis bypasses provider
creation. It includes code, not model weights. Settings prepares missing
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

The Character adapter consumes the preserved typed entity/alias/coreference,
pronoun, syntax and quotation outputs. Proper and nominal people, including
singletons missing from `.book`, enter the existing Character owner. Non-person
clusters and pronoun-only unresolved clusters do not become invented people.
Exact overlap anchors and unambiguous aliases reconcile window-local IDs;
collisions abstain. Linked pronouns provide an implied voice hint. Upstream
referential estimates (including name priors) remain evidence, not explicit or
presented gender. Explicit selections, Reset and user corrections are preserved.

The controller builds paragraph-preserving windows at the listening position,
including imported `.radoc` books. Bounds are 12,288 target UTF-16 units plus at
most 4,096 preceding units, 32 context segments, and the provider's 4,096-token
admission limit. Short documents keep one bounded window; long documents use
positional segment groups, with safe slices for oversized segments. A jump demands
the new position directly. No neural completion gates first speech.
Annotation and attribution indexes are built during existing immutable snapshot
construction. Window binding queries target segments and their spans instead of
rescanning every dialogue and annotation in a complete book.

The new `paragraph-context-v2` policy distinguishes these requests from S1's
speech-segment newline layout. Existing v1 candidates survive export/import, but
changed layout or text requires fresh inference; exact v2 windows reuse saved
results before provider creation. Single newlines cannot substitute for upstream
paragraph boundaries: the qualification caught actual City/Rosalina errors when
paragraphs were collapsed. Multi-token mention projection now takes exact text
from verified token coordinates, preserving punctuation and source whitespace.

Raw evidence parsing and Character projection run on an isolate within the
existing supervisor's bounded lifetime. The main-isolate store rejects obsolete
source/analysis/correction revisions and preserves later selections/Reset. Each
Character retains complete record/entity references and at most eight recent
summaries, with up to 64 observations each; full upstream evidence stays in book
records. New planning contexts can consume up to 128 recently refined dialogue
spans. Unmatched source boundaries retain fallback routes; matched unknowns stay
unknown. Source-authored attribution metadata is protected. Captured active
requests are never restarted or rewritten: refinement becomes effective at the
next ordinary planning boundary, range, jump or subsequent Play.

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
Do not equate these measurements with the two-second app startup goal, physical process-tree
memory, a held-out quality score, or smooth Fish playback.

Remaining promotion gates: independent literary and private City labels, fair
fallback comparison, explicit correction precedence, bounded rolling entities/context,
shared memory admission, startup/audio and M3 measurements. Background windows currently
were diagnostic-only evidence for S1. S2's source-matched future-route integration
is described above; these early smoke results do not qualify literary accuracy.
Provider processes are resident, but rolling book-level coreference is not implemented.
Native UI/storage/quit evidence is recorded in #127 separately from audible acceptance. Initial playback must continue
through fast discovery while deeper analysis becomes available. Neural refinement remains opt-in in Settings.

## Saved book analysis

Completed analysis windows now persist in the working book under Application
Support. Reopening the same source or restarting the app checks this saved work
before starting the model. Settings reports **Restored saved book analysis** on a
hit. Model downloads and saved analysis are separate caches; changing the provider,
model, output adapter or window text prevents incompatible result reuse.

The output adapter is `readaloud-cpu-2`; the installed CPU runtime patch remains
version 1 and needs no reinstall or model download for this change. Besides the
person/quotation projection, records retain the upstream token/syntax, complete
entity, quotation and character-summary data already computed. Event/supersense
analysis remains disabled. See the [full capability review](../project/research/modernbooknlp-capability-reuse.md).

The existing document-export API includes these records in `.radoc-v4`, together
with Character choices; v1–v3 imports still work. A portable saved window can be
restored in a fresh working store without loading a model. All records survive
re-export; S2 selects the bounded window at the current playback position,
including forward/backward jumps in an imported book. There is no new save UI or rendered
audio packaging in this slice. Ordinary automatic persistence remains incremental
in Application Support.

`tools/modernbooknlp_persistence_smoke.dart` is the isolated native probe for real
inference, A → B → A cache reuse and copied `.radoc` reopen in a fresh book/Character
store whose provider factory deliberately fails if called. It uses the same
`residentNlpTest` sandbox as the resident probe and a unique run directory. Build
with the repository Flutter toolchain/configuration first, then
`sh tools/build_macos_release.sh tools/modernbooknlp_persistence_smoke.dart`, copy and
sign with the isolated bundle ID as above, and pass a fresh receipt path. Always
Quit that exact app and verify its process and recorded children exit. Speech is
silent in this probe; passing it is not attribution-quality or audible acceptance.

The November 5 persistence probe passed real CPU analysis, A/B/A saved-result
reuse, explicit narrator choice retention through export/re-import, and a fresh
working/Character store with zero provider-creation attempts. Normal Quit and the
app/recorded child exit were verified. This used synthetic prose and silent speech;
it does not qualify City/Rosalina attribution or audible Fish output. Deterministic
tests separately cover fresh-owner disk reuse, stale/corrupt dependencies and
revoked publication. The full implementation evidence is recorded in #127.

To test a real app relaunch, start that same isolated bundle again with a new
receipt path followed by the exported `.radoc` path as its second argument. This
mode opens a fresh working store, refuses all provider creation, and checks restored
evidence and the explicit voice choice. Quit and verify exit again afterward.

## S2 qualification and limits

The frozen comparison contains 43 quotations in the existing independently audited
public prose corpus and 20 in private City/Rosalina excerpts. Private labels were
read from the source and frozen before predictions by the implementation writer;
they have not had a second independent annotator. The paragraph-preserving app
path matched 63/63, versus baseline 50/63 (City 4/13 → 13/13; Rosalina 3/7 → 7/7).
An additional overlapping-window pass matched all 11 audited rain-corpus turns
and preserved an explicit voice across changing local cluster IDs. These small
fixtures do not establish whole-novel accuracy. Full private sources and model
receipts are not published in Git.

Run `test/modernbooknlp_literary_qualification_test.dart` with
`READALOUD_LITERARY_LABELS`, `READALOUD_LITERARY_RECEIPT`, and the existing runtime
environment to reproduce the private comparison. `tools/qualify_modernbooknlp.py`
measures the separate raw-text provider boundary. Committed public rain/orchard
records exercise the adapter without a model. The isolated native persistence
probe additionally checks a discovered singleton, female pronoun evidence, and
an explicit Character voice through portable reopen. These are silent integration
checks, not proof of emitted Fish voice identity, continuous audio, two-second
startup, M3 memory acceptance or the S3 switch/stall repair. Exact execution
receipts and remaining gates belong to [#127](https://github.com/kellyjanderson/readaloud/issues/127).
