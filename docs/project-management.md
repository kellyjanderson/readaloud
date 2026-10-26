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

The orchestrator owns assignment and parent updates. Workers may report to their slice when authorized; otherwise the orchestrator publishes their returned results. No worker needs to create or rewrite local planning documents. An isolated worktree per concurrent writer avoids index and checkout collisions; sequential work may reuse a safe checkout. The orchestrator decides integration order and resolves conflicts. A slice branch merged into a feature branch is not yet delivered to main.

For re-entry, read the marked current blocks and their linked changed results. Update the blocks at dispatch, meaningful blocker, handoff or integration—not every tool call. Record new evidence/decisions in comments and link them from the block instead of copying the whole checkpoint to several issues. Chat summaries are convenience; GitHub is durable authority. Do not depend on another chat being open to reconstruct ownership.

## Compact issue reads and updates

Each active parent/slice begins with exactly one block using the markers below. The parent heading is `Current orchestration`; a slice uses `Current task`. Target 400–700 tokens for a parent and 250–500 for a slice; these are writing budgets, not measured billing limits. Keep full design/acceptance material below the block. Never compress away an unresolved constraint or replace accepted contracts with a summary.

```markdown
<!-- readaloud:current:start -->
## Current task
Updated: timestamp; based on: exact checkpoint link
Authority: parent + accepted revision/decision links
Owner: coordinator/chat; worker identity and exclusive files/lane
Delivery: base commit, branch/worktree, PR and actual integration target
Readiness: dependency evidence; next action; blockers
Execution: exact model/effort; escalation condition
Acceptance: passed/failed/blocked/not-run boundaries; remaining checks
Evidence: exact decision, result and handoff comment links
<!-- readaloud:current:end -->
```

Parent blocks additionally index active slices and track Astra rounds/consecutive/total task counters. Child blocks link the parent policy rather than repeat it. Project Status/priority and native dependency edges retain authority; the block records actionable readiness and evidence, not a competing lifecycle tracker.

Use the [read helper](../tools/read_issue_context.rb) before returning issue text to model context:

```sh
ruby tools/read_issue_context.rb 48
ruby tools/read_issue_context.rb 54 --headings
ruby tools/read_issue_context.rb 54 --section 'Scenarios'
ruby tools/read_issue_context.rb 48 --comment 6392370567
```

The default never loads comments and fails if the block is absent/malformed. `--headings` lists contract headings; `--section` returns one exact heading including nested headings; `--comment` fetches one numeric REST comment ID from its issuecomment URL and verifies the issue. `--full` is an explicit first-assignment/revision-review escape hatch. A block is an index, not enough by itself for implementation or acceptance review. Fetch accepted revision and relevant contracts once per task, and again if they change. Do not routinely request `gh issue view --comments` or all-comment connector output. Collapsed Markdown still costs tokens if returned by a tool.

The orchestrator is the single block writer. Before updating, re-fetch the body, preserve all material outside the managed block, and reconcile newer comments/decisions. GitHub issue-body updates do not provide a transactional merge here: serialize ownership and verify the written result. A timestamp alone does not prove freshness; use linked checkpoint/revision plus current dependencies. If stale or missing, inspect bounded recent comments and explicit referenced decisions, repair the block, and report unresolved ownership rather than guessing. Keep old comments intact. No synchronized local copies or separate orchestration documents.

Project text/number/select fields may hold small filterable metadata when access exists; do not mirror the full block there. Issue-body blocks work with repository access and do not depend on Projects permissions. Fresh-task/model/effort and Astra review thresholds are defined in AGENTS.md. Publish a bounded approval receipt before changing those thresholds; unknown counters require reconciliation before further Astra use.

## Completion and reconciliation

Workers submit evidence and move to Review. The orchestrator verifies dependencies and integration, then performs FINAL. Repository architecture documents the resulting implementation and intent, with links back to the design issue for discussion. Update user docs or explain no impact. Close the parent only after required evidence and architecture changes are accepted and merged to the declared final target. No automatic closing keyword for the parent on intermediate PRs.

## Migration receipt and proof limits

On October 24, 2026 the ACD at commit 62a16f3 moved to #48; its complete slice plan moved to #49–#54, with native parent/dependency relationships. The supplementary target contract moved into #48 and integrated verification scenarios into #54. The compliance plan moved to #55. Original files remain recoverable in Git history. Active copies were removed rather than synchronized. Legacy archives and detailed historical contracts are retained as references, not new working-document locations.

The documentation checker rejects local working files in the retired ACD/planning directories and checks local documentation links/legacy architecture ownership. It does not contact GitHub or prove live issue state. Track planning-only mutations, maintenance/recovery effort and available token usage across actual changes; allowance savings remain unproven.

## Access and automation

The board enables auto-add for open Read Aloud issues, auto-add for sub-issues and an initial Proposed status. Auto-close, close-to-Done, merge-to-Done and linked-PR-to-In-Progress shortcuts are disabled. The orchestrator owns lifecycle transitions. Repository issue/PR API access and Projects access are separate permissions: CLI Project operations require the project scope; use the authenticated GitHub browser if it is unavailable. Do not silently fall back to local plan files.
