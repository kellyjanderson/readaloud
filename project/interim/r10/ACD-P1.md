## ACD-P1 — One maintained repository and distribution entry path

> Fixed published R1 snapshot, captured November 4, 2026 Pacific.
> [Source design/plan](https://github.com/kellyjanderson/readaloud/issues/115#acd-p1--one-maintained-repository-and-distribution-entry-path) · [package provenance](README.md) · [lifecycle](../README.md).
> GitHub owns current execution state; this snapshot is not an implementation or acceptance claim.

Design revision R1, November 4, 2026 Pacific; base `1f605cfa74bc4374ffc278cb9ccb67218efe6cc4`. This development/presentation architecture delta builds on [completed layout cleanup](https://github.com/kellyjanderson/readaloud/issues/115#issuecomment-6647919044), #122 integration and #55 distribution requirements. It does not reauthorize branch deletion or publication.

### Completed baseline and remaining change
Cleanup main/tag, writable pinned launcher, all feature-branch consolidation, branch retirement and historical-document consolidation are done. Root README → human setup/tools guide → implemented architecture is the maintained discovery path; active ACDs/plans remain GitHub-only. Keep the new repository/local-file map. SDKs, models, test artifacts, nested sampler WIP and detached worktrees are preserved intentionally, not a backlog for blind deletion.

Remaining change: make README, About/support descriptions, model/runtime support matrix, packaging prerequisites and public examples agree with the exact candidate. Each supported engine entry distinguishes selectable, locally source-tested, native-qualified and distributed states, tied to exact runtime/model revision and hardware. A model appearing in Settings is not proof of smooth playback. Remove stale fixed-24-kHz and environment-only-selection claims from current architecture when reconciling actual source; retain historical snapshots as history.

### Ownership and boundary
Maintain one developer entrypoint `tools/flutter`; it owns a writable pinned native SDK/package cache and verifies acquisition. Native OS prerequisites stay explicit. Existing install/embed/package tools own the MLX runtime; model snapshots belong to persistent application storage, never a build directory. A successful Kokoro-only package must not be presented as Drama-capable when the optional runtime was omitted. Release #122 chooses the candidate and owns final artifacts; #55 owns unresolved license/notices decisions. Do not add automatic Actions or paid services.

No app process, model asset or user configuration is modified for documentation work. Any onboarding/package test uses an isolated checkout/profile, names its process and evidence owner, records exact inputs and quits its app normally with exit verification. Public screenshots/text use synthetic or cleared samples; City remains private. Repository cleanup decisions preserve native probes, used test fixtures, vendor notices and unique historical requirements.

### Migration, checks and reconciliation
Update existing README/docs/architecture/About surfaces rather than create another status ledger. Follow the release support matrix back to its feature receipts, without copying entire plans. Triage an old issue as complete only when its acceptance exists; merged code is not enough. Keep old local SDK/worktree retirement a separate specifically inventoried operation if later needed.

Acceptance: clean worktree can bootstrap/build/launch using documented prerequisites; package contains its declared runtime; installed model reuse works after rebuild; links and maintained indexes pass `tools/check_docs.rb`; public capability statements match candidate evidence; no private content or competing plans added. Existing seven bootstrap tests and layout checks are already passed, not new work. Final candidate/native onboarding remains open. Reconcile system overview, runtime messaging, setup, maintenance and repository map with the implementation. Depends on actual M1/S1 qualification for final support claims; basic stale factual corrections can proceed independently.

### Source and reconciliation anchors

Pinned existing owners, not implementation of this ACD. Additional exact locations and test matrices remain in the linked review findings.

- [docs/repository-layout.md](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/docs/repository-layout.md)
- [tools/README.md](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/tools/README.md)
- [tools/embed_mlx_runtime.sh](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/tools/embed_mlx_runtime.sh)
- [project/architecture/system-overview.md](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/project/architecture/system-overview.md)
