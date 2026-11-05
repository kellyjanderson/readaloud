# Versioned interim designs

This Git-tracked location holds substantial design/plan drafts and fixed published
revisions until implementation is reconciled. `tmp/` is volatile transport space,
not a place to keep design documents. The user's November 4, 2026 direction adds
this lifecycle to the earlier GitHub-only drafting process.

Current amendment: [R13 progressive analysis and automatic casting](r13/README.md),
applied to [R12 character contract and consolidated delivery](r12/README.md).
[R11](r11/README.md) retains the review coverage and acceptance supplement;
[R10](r10/README.md) retains the ten original ACD designs. R12 explicitly identifies
the character ownership and sequencing decisions it supersedes.

## Authority and revision lifecycle

1. **Draft:** create `project/interim/<revision>/` with a README identifying its
   author/owner, source issue, design revision and implementation baseline. Use
   Markdown and commit meaningful draft checkpoints. Describe proposed structure,
   migration, acceptance and eventual architecture targets. Do not copy live issue
   bodies, current blocks, task status or assignment ledgers.
2. **Publish:** publish the reviewed revision to the design issue, or link its
   exact Git commit from the issue. Record the publication/decision URL and a
   `manifest.json` of document filenames, revisions, source URLs and SHA-256 hashes.
   A published package is a fixed design reference; publication does not imply
   human approval, implementation or acceptance. GitHub current blocks identify
   the operative revision; Project Status and native dependencies own execution.
3. **Revise:** keep published document bytes fixed. Author the next revision in a
   new package, record its predecessor and publish the changed decisions. Do not
   continuously synchronize issue bodies and repository files. A GitHub-only
   correction must be identified as newer until captured in a new package.
4. **Reconcile:** with implementation, update `project/architecture/` and relevant
   human docs to describe the actual behavior. Record exact implementation commits,
   acceptance evidence, final architecture links and any superseding decisions in
   the GitHub design issue. Unimplemented requirements remain explicitly open.
5. **Retire:** after the linked reconciliation gate is satisfied, remove obsolete
   interim files in a reviewed commit and update incoming links/indexes. The issue
   retains an immutable Git link to the original revision. Git history preserves
   the design; do not create another archive copy automatically. A superseded draft
   may be retired with an explicit replacement/withdrawal record, never to conceal
   missing acceptance. Remove disposable transport payloads after publication and
   versioned-copy verification, independently of feature completion.

## Package checks

Published manifests use schema version 1 and record `package_revision`,
`publication`, `implementation_baseline` and `documents`. Each document records
`path`, `revision`, `source`, `source_section_sha256` and `sha256`. The source hash
identifies the published section before local provenance wrappers/link expansion;
the file hash protects the retained local bytes. These are provenance/integrity
records, not a second completion tracker.

Run `ruby tools/check_docs.rb` after editing indexes or adding a package. It checks
local targets and published document hashes. It does not fetch GitHub, certify
acceptance or authorize deletion. Source publication is verified separately when
capturing a revision. Draft packages need no manifest until publication, but their
README must say they are unpublished and link the owning issue.
