# GitHub planning and orchestrator workflow

Working design and planning live in [GitHub Issues](https://github.com/kellyjanderson/readaloud/issues) and the [Read Aloud Project](https://github.com/users/kellyjanderson/projects/1). Final architecture remains in [the repository](../project/architecture/README.md), reviewed alongside code. [AGENTS.md](../AGENTS.md) is authoritative.

## Current entry points

- [Prepared-document runtime design](https://github.com/kellyjanderson/readaloud/issues/48); accepted direction R1 is linked in its decision comment.
- [P0 baseline](https://github.com/kellyjanderson/readaloud/issues/49), [P1 preparation](https://github.com/kellyjanderson/readaloud/issues/50), [P2 resident resources](https://github.com/kellyjanderson/readaloud/issues/51), [P3 worker planning](https://github.com/kellyjanderson/readaloud/issues/52), [P4 assignment/cache](https://github.com/kellyjanderson/readaloud/issues/53), [FINAL acceptance/reconciliation](https://github.com/kellyjanderson/readaloud/issues/54).
- [Release compliance](https://github.com/kellyjanderson/readaloud/issues/55).

These links are navigation, not a copied progress checklist. Consult GitHub for live state.

## Lifecycle

Proposed → Ready → In Progress → Review → Reconcile → Done. Dependencies gate dispatch; blocked work records its blocker without pretending readiness. Parent features may remain active while children progress. A parent enters Done only after accepted evidence and merged architecture reconciliation. Avoid default automation that marks parent designs done solely because a PR merges or an issue closes.

The opening design-issue body is the current proposal: problem, intended behavior, exclusions, architectural delta, ownership/concurrency, migration, acceptance, affected architecture and open decisions. Comments preserve decisions and discussion. Use native sub-issues and blocking relationships rather than a second checkbox plan. Use labels for kind/area and milestones for releases; Project Status owns lifecycle.

Record an accepted scope revision (R1, R2...) in a decision comment. Reference the revision and relevant body update in work orders. For material revisions, preserve the prior accepted scope in its decision record and identify affected workers; mutable issue text alone is not an immutable approval. Do not claim a human approved an agent's change.

## Orchestrator launch

Give the orchestrator the parent issue URL and intended delivery target. It reads the current design, decision revision and native dependency graph, then claims coordination in one comment. It selects ready work and provides each worker:

- Parent/slice URL, design revision and the bounded relevant architecture/source context.
- Objective, explicit exclusions, owned files/modules and overlap constraints.
- Dependency results, base commit, branch/worktree and intended PR base.
- Required verification and limits on completion claims.
- Return contract: summary, paths, commit/PR, tests/evidence, blockers, remaining work.

The orchestrator owns assignment and parent updates. Workers may report to their slice when authorized; otherwise the orchestrator publishes their returned results. No worker needs to create or rewrite local planning documents. An isolated worktree per concurrent writer avoids index and checkout collisions; sequential work may reuse a safe checkout. The orchestrator decides integration order and resolves conflicts. A slice branch merged into a feature or release branch is not yet delivered to main or shipped. Include the release milestone, release issue and release branch in each assignment.

For re-entry, read the latest coordination checkpoint and linked slice results. Record a checkpoint at dispatch, meaningful blocker, handoff or integration—not every tool call. Include current owner, active assignments, branches/commits and next safe action. Chat summaries are convenience; GitHub is durable authority. Do not depend on another chat being open to reconstruct ownership.

## Completion and reconciliation

Workers submit evidence and move to Review. The orchestrator verifies dependencies and integration, then performs FINAL. Repository architecture documents the resulting implementation and intent, with links back to the design issue for discussion. Update user docs or explain no impact. Close the parent only after required evidence and architecture changes are accepted and merged to the declared final target. No automatic closing keyword for the parent on intermediate PRs.

## Release planning and delivery

Use a GitHub milestone named for the tentative release version and one release coordination issue, created with the release template. The milestone describes intended user outcomes, exclusions and optional target date; its issue/PR membership is the scope list. Feature issues retain their own slices and dependencies. The release issue links those records and owns only release-wide readiness and publication, not a duplicate feature checklist. Scope and tentative version changes stay in GitHub.

The release coordinator creates `codex/release-<version-or-name>` from freshly fetched `origin/main` and records the base commit. Workers branch from the release branch or a declared prerequisite branch, integrating via scoped PRs into the release branch, optionally through feature branches. Keep existing in-flight branches intact and record their integration route. Do not switch another worker's checkout or rewrite its history. Individual release features do not merge directly into main.

Features can complete once their acceptance and architecture reconciliation are integrated into the release branch; record them as integrated but unreleased. Close their issues explicitly after checking evidence, since PRs into a non-default branch may not auto-close them. Release readiness remains separate from feature completion and milestone percentage.

The release issue coordinates this sequence:

1. Select the actual version; reconcile existing package/tag conventions before changing metadata. Record release membership through the milestone, without copying slice plans.
2. Integrate accepted features, reconcile architecture/user docs, update package version and release notes on the release branch, and record the candidate commit.
3. Validate integration and the packaged macOS application, including applicable installation, playback and voice-transition evidence. Reuse valid feature evidence; report missing checks explicitly.
4. Open the release PR from the working release branch into main. Merge only with user authorization and stable passing checks and review gates.
5. Verify the resulting main commit; build and validate the artifacts from that exact commit before tagging and publishing. Recheck affected behavior if the candidate changed. Use a draft GitHub Release to prepare notes and assets, then publish the immutable `vX.Y.Z` tag and release under the user's authorization.
6. Verify the tag points to the intended main commit and published artifacts are downloadable. Record evidence and close the release issue/milestone. Retain release branches/worktrees until the merge is verified on local main and publication is verified. Publication failure leaves the issue open; never move a published tag to disguise a correction.

The repository holds final architecture, human guidance, actual version/build metadata and release automation. It holds no working release plan or duplicate scope ledger. Defining this workflow does not itself authorize any particular merge or publication.

## Migration receipt and proof limits


On October 24, 2026 the ACD at commit 62a16f3 moved to #48; its complete slice plan moved to #49–#54, with native parent/dependency relationships. The supplementary target contract moved into #48 and integrated verification scenarios into #54. The compliance plan moved to #55. Original files remain recoverable in Git history. Active copies were removed rather than synchronized. Legacy archives and detailed historical contracts are retained as references, not new working-document locations.

The documentation checker rejects local working files in the retired ACD/planning directories and checks local documentation links/legacy architecture ownership. It does not contact GitHub or prove live issue state. Track planning-only mutations, maintenance/recovery effort and available token usage across actual changes; allowance savings remain unproven.

## Access and automation

The board enables auto-add for open Read Aloud issues, auto-add for sub-issues and an initial Proposed status. Auto-close, close-to-Done, merge-to-Done and linked-PR-to-In-Progress shortcuts are disabled. The orchestrator owns lifecycle transitions. Repository issue/PR API access and Projects access are separate permissions: CLI Project operations require the project scope; use the authenticated GitHub browser if it is unavailable. Do not silently fall back to local plan files.
