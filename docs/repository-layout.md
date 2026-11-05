# Repository layout and local files

Start with the root [README](../README.md) for the product and launch command,
[development](development.md) for checks, and [project management](project-management.md)
for active GitHub work. This map explains file ownership; it is not another plan.

## Source and maintained references

| Location | Purpose |
| --- | --- |
| `lib/`, `test/` | Flutter application and automated tests |
| `macos/` | Current native target and platform integration |
| `android/`, `ios/`, `linux/`, `web/`, `windows/` | Retained Flutter platform scaffolds; not qualified production targets |
| `assets/` | Bundled dictionaries, fonts, voice references, engine manifests and the packaged MLX worker |
| `third_party/` | Vendored dependencies and their notices; includes native modifications |
| [tools](../tools/README.md) | Launch, packaging, asset maintenance and bounded qualification tools |
| `docs/` | Human setup, usage and maintenance guidance |
| `project/architecture/` | Implemented structure, invariants and evidence limits |
| [project/interim](../project/interim/README.md) | Versioned design drafts/published revisions awaiting explicit architecture reconciliation and retirement |
| `project/product-definition.md`, `project/ui/` | Product expectations and retained interface guidance |
| `project/specifications/`, `project/test-specifications/` | Detailed legacy contracts and acceptance scenarios; retain until their semantics are explicitly reconciled |
| `project/research/` | Source-backed research, read by topic; dates matter |
| `project/testdocs/` | Import and pronunciation fixtures used by tests and probes; these are inputs, not generated clutter |
| [project/archive](../project/archive/README.md) | Historical architecture, ancestor specifications, plans, release intent and journal records |
| `.agents/`, `AGENTS.md`, `.github/` | Scoped agent procedures, repository workflow and GitHub templates |

The root community files, Flutter manifests/lockfile, analysis options and
`.metadata` are intentional. `pubspec.lock` pins application dependencies;
`.metadata` supports Flutter project migrations. Keep platform folder names where
Flutter expects them. Do not remove a vendor file merely because the app does not
import it directly; native build and license requirements also apply.

## Local-only state

These paths are ignored by Git and can dominate Finder's view of a checkout.
Ignored does not mean disposable.

| Location | Ownership and cleanup rule |
| --- | --- |
| `.readaloud-tools/` | Current launcher's writable Flutter SDK and package cache. Keep for reuse; other worktrees may symlink here. |
| `.flutter-sdk/`, `.local/` | Legacy tooling and preserved local resources. Check editor settings, symlinks and historical probe dependencies before retiring individual contents. |
| `.dart_tool/`, `build/`, platform `ephemeral/` and `Pods/` | Generated build state. Regenerable, but a particular build can also be an evidence artifact; check ownership first. |
| `assets/kokoro/model/*.onnx` | Downloaded model weights. Keep to avoid repeated downloads. |
| `tmp/`, `project/test-artifacts/` | Disposable scratch alongside locally retained receipts, fixtures, audio and test app copies. Classify individual entries before removal; preserve evidence referenced by issues. |
| `.idea/`, `.vscode/` | Local editor configuration; preserve user settings. |
| `kokoro-voice-sampler/` | Independent nested repository, not part of this application's tracked source. Check its own Git status and owner before moving or deleting. |

MLX models and user documents may also live outside the repository in application
support/container storage; repository cleanup must not clear them. See the
[MLX setup guide](mlx-tts-engines.md) for acquisition and reuse.

## Keep the structure clean

- Keep execution/status and published decision/evidence receipts in GitHub; draft
  and preserve fixed design revisions under `project/interim/`. Add historical
  repository material to `project/archive/` only when preserving existing history;
  do not recreate local planning or release-status directories.
- Put reusable developer commands in `tools/` and list their purpose in its index.
  Keep experiments and their output in ignored scratch space until deliberately adopted.
- Before cleaning local files, inspect `git status --short --ignored=matching`,
  nested repositories, active processes and referenced evidence. Avoid blanket
  `git clean -fdx`: it would remove models, SDKs and local work along with caches.
- Run `ruby tools/check_docs.rb` after moving documents. The archive index is
  maintained navigation; archived prose is historical and may describe retired paths.
