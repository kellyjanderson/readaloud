# GitHub planning and directed work

[AGENTS.md](../AGENTS.md) is authoritative; these linked procedures carry its conditional rules. [GitHub Issues](https://github.com/kellyjanderson/readaloud/issues) and the [Project](https://github.com/users/kellyjanderson/projects/1) own execution; [architecture](../project/architecture/README.md) owns implemented structure.

## Directed work

Use one directed owner for a bounded change. A small fix can use one issue; create a parent/slice graph only when the work needs it. Read the assigned current block (and parent when present), relevant accepted contract/revision and affected source/tests. Use `ruby tools/read_issue_context.rb NUMBER`; default retrieval excludes comments and refuses absent/malformed blocks. Re-entry reads changed evidence and current blocks, not historical review archives. Missing or stale context requires the [issue protocol](#compact-issue-reads-and-updates), not guessed readiness.

Preserve other work, name scope/exclusions and actual base/target, run bounded relevant checks, reconcile architecture/human docs and return exact evidence limits. Keep progress, assignments and handoffs in GitHub; [versioned interim designs](../project/interim/README.md) are draft/fixed design artifacts, never live status mirrors. No Actions/paid work, main merge or publication is authorized by this guide.

Load only the procedure needed: [storage authority](#authority-and-storage), [issue writes](#compact-issue-reads-and-updates), [delegation/model budgets](#conditional-orchestration), [PRs/completion](#delivery-and-reconciliation), or [releases](#conditional-release-delivery). No worker/model/worktree fields are required from visitors reporting a bug or feature; actual execution records retain applicable ownership, base/target, checks and missing acceptance. `acd` and `implementation-plan` remain distinct thin routes to this authority. Inspect/change managed skills only through the verified live SkillsKeeper source, validation and archive/sync procedure; do not edit generated global copies or overwrite newer managed sources from an older worktree.

## Authority and storage

- `project/architecture/`: implemented structure, intent, invariants, durable rationale and honest evidence limits. Update with implementation; never promote a proposal to current fact.
- GitHub design issue: working ACD, scope, alternatives, decisions, acceptance and architecture targets.
- `project/interim/`: Git-tracked design drafts and immutable published revision snapshots, with source issue/revision, lifecycle and reconciliation links. Follow its README; never rely on volatile `tmp/` for design documents. GitHub current blocks and Project Status still own execution; do not mirror live issue bodies or progress here.
- Native sub-issues/dependencies: implementation slices and readiness. Small fixes may use a single issue.
- GitHub Project: authoritative status and priority. Marked issue-body blocks: current coordination/work orders and exact evidence pointers. Issue comments: durable decision, handoff and evidence receipts; historical claims do not supersede a reconciled current block without new evidence.
- GitHub milestone: release scope, tentative version, intended outcomes and exclusions. One release issue owns release-wide readiness and publication; link feature evidence instead of copying plans.
- `docs/`: durable setup, usage and process guidance. `project/ui/`, legacy specifications/test specifications and research are retained references; new substantial design drafts use `project/interim/` and publish to their owning issues.
- `project/archive/` and historical journals: preserved history, not active instructions. Design drafts and fixed plan snapshots belong only in `project/interim/`; do not create local progress journals, task checklists, release-status ledgers or mirrored issue bodies. Ignored `tmp/` may hold disposable transport payloads, never design-document storage. After implementation, reconcile accepted design into current architecture and record evidence in GitHub before retiring interim files through a reviewed Git change; history preserves the revision.

## Lifecycle

Proposed → Ready → In Progress → Review → Reconcile → Done. Dependencies gate dispatch; blocked work records its blocker without pretending readiness. Parent features may remain active while children progress. A parent enters Done only after accepted evidence and merged architecture reconciliation. Avoid default automation that marks parent designs done solely because a PR merges or an issue closes.

The opening design-issue body is the current proposal: problem, intended behavior, exclusions, architectural delta, ownership/concurrency, migration, acceptance, affected architecture and open decisions. Comments preserve decisions and discussion. Use native sub-issues and blocking relationships rather than a second checkbox plan. Use labels for kind/area and milestones for releases; Project Status owns lifecycle.

Record an accepted scope revision (R1, R2...) in a decision comment. Reference the revision and relevant body update in work orders. For material revisions, preserve the prior accepted scope in its decision record and identify affected workers; mutable issue text alone is not an immutable approval. Do not claim a human approved an agent's change.

## Conditional orchestration

Read before dispatching workers, parallel work, changing assignments or model budgets. One directed owner remains the default; no delegation is required just to complete a small fix.

An orchestrator chat may coordinate multiple workers, worktrees and slice PRs. No single-branch/single-PR rule may prevent safe delegation. The orchestrator owns parent design, dependency readiness, assignment claims, integration and final reconciliation. Workers own their assigned files/modules and report in their slice issue.

Maintain one `<!-- readaloud:current:start -->` / `<!-- readaloud:current:end -->` block at the top of each active issue. Parent target: 400–700 tokens; slice target: 250–500. Update at dispatch, blocker, handoff, integration or decision changes. Include revision, owner, base/target, active ownership/dependencies, next action, model/effort, remaining acceptance and exact decision/evidence links. Keep Project Status authoritative. Preserve the design and historical evidence outside the block; summaries never waive acceptance. Re-fetch before writing and preserve unrelated body changes. Comments record new evidence/decisions, not repeated whole-state copies.

Use a fresh subagent with no inherited conversation (`fork_turns: none`) for each bounded task; keep its focused fix/test cycle together, then retire it. Give compact work orders, not whole histories. The standalone orchestrator uses Luna/medium; workers default to Sol/medium, Sol/high for ambiguous debugging or independent acceptance review, and Luna/low for mechanical checks. Record exact available model IDs and effort. Astra defaults to medium for unresolved architecture only. Obtain human approval before Astra/high or higher, round 3 within one Astra task, consecutive Astra task 3, or total Astra task 4 per orchestration. Count substantive assignments/follow-ups across nested agents and replacements; tool calls/waits are not rounds. Track counters in the parent current block; a fresh chat does not reset them. Approval grants a bounded extension. Do not invent usage/cost figures.

Before dispatch, record the worker/chat identity, design revision, scope/exclusions, exclusive file/module ownership, dependency state, base commit, branch/worktree, target integration branch, acceptance checks and return contract. Workers are not alone: preserve others' changes, do not revert unrelated edits, and coordinate overlap before writing. Use isolated `codex/<feature>-<slice>` branches/worktrees when concurrency would collide. Do not concurrently edit the same checkout/index.

User-requested orchestration authorizes appropriate subagent delegation; creating or messaging separate user-owned chats still requires the platform's user authorization. Do not invent thread identities. Subagents return through their parent; the orchestrator publishes durable checkpoints. Platform limits and user restrictions take precedence.

Read the latest design revision before starting and before integration. A material scope change is an orchestrator decision recorded as a new revision; pause only affected work. Do not mutate parent scope from a worker. Claims are advisory, not a lock: the orchestrator is the single dispatcher and resolves duplicate/stale claims explicitly. No force takeover or duplicate dispatch merely because a chat is quiet.

### Work-order handoff

Give the orchestrator the parent issue URL and intended delivery target. It reads the current design, decision revision and native dependency graph, then claims coordination in one comment. It selects ready work and provides each worker:

- Parent/slice URL, design revision and the bounded relevant architecture/source context.
- Objective, explicit exclusions, owned files/modules and overlap constraints.
- Dependency results, base commit, branch/worktree and intended PR base.
- Required verification and limits on completion claims.
- Return contract: summary, paths, commit/PR, tests/evidence, blockers, remaining work.

The orchestrator owns assignment and parent updates. Workers may report to their slice when authorized; otherwise the orchestrator publishes their returned results. No worker needs to create or rewrite local planning documents. An isolated worktree per concurrent writer avoids index and checkout collisions; sequential work may reuse a safe checkout. The orchestrator decides integration order and resolves conflicts. A slice branch merged into a feature or release branch is not yet delivered to main or shipped. Include the release milestone, release issue and release branch in each assignment.

## Compact issue reads and updates

Each active parent/slice begins with exactly one block using the markers below. The parent heading is `Current orchestration`; a slice uses `Current task`. Target 400–700 tokens for a parent and 250–500 for a slice; these are writing budgets, not measured billing limits. Keep full design/acceptance material below the block. Never compress away an unresolved constraint or replace accepted contracts with a summary.

```markdown
<!-- readaloud:current:start -->

## Delivery and reconciliation

The user has no budget for GitHub Actions. Keep repository Actions disabled; do not enable, dispatch, or add automatic workflows. Run bounded checks locally and report their results. Do not require new remote CI runs for integration; historical CI is evidence only. Any paid service/execution or change to this constraint requires explicit user approval.

Use scoped branches, preserve WIP, stage intentional paths. Link slice and parent in every PR; use `Refs` for the parent so an intermediate merge cannot close the feature. Declare the actual PR base. Create each release working branch as `codex/release-<version-or-name>` from freshly fetched `origin/main`; record its starting commit in the release issue. Worker/feature branches start from the assigned release branch (or a declared dependency branch) and target that release branch, optionally through a feature integration branch. Do not merge individual release slices directly into `main`. Preserve existing work: record how an existing feature branch will join the release rather than resetting or rewriting it. Process-only maintenance may use a scoped branch from main and a PR back to main, explicitly marked as outside a product release. No merge or push directly to main without explicit user authorization; this process definition is not authorization to publish a release.

Run bounded relevant checks; report passed, failed, blocked and not run distinctly. Checkpoints report result, changed paths, commit/PR, base, evidence and remaining work. Batch meaningful updates; no heartbeat comments, repeated whole-plan rewrites or routine agent polling.

Final slice reconciles architecture and human docs in the implementation/final PR, verifies required evidence and merged commits, then closes the feature. `Reconcile` is a real gate; merged PRs, closed children or Project Done alone do not prove acceptance. Record missing evidence explicitly and leave incomplete work open. Never archive a feature as a substitute for finishing it. A feature may close after acceptance and reconciliation are merged into the declared release branch; record that it is integrated but unreleased. Do not rely on GitHub auto-closing issues for PRs targeting a non-default branch. Do not delete release branches/worktrees until the release merge is verified on local `main` and publication is verified.

Workers return evidence to their parent; publish in the slice only when authorized. Close a parent only after its required evidence and reconciliation are accepted and merged to the declared final target. The [PR template](../.github/PULL_REQUEST_TEMPLATE.md) records result, actual integration target, evidence and missing gates; it cannot authorize integration.

## Conditional release delivery

Use one GitHub milestone and one release issue per release. Keep tentative versions, scope changes, assignments and readiness evidence in GitHub; do not create local release plans or planning-only tags/releases. Change package version metadata only when preparing a real release candidate. The release coordinator owns integration and release readiness; feature orchestrators retain their bounded assignments.

The release issue records the milestone, release branch/base, included feature links, dependencies, version decision, release PR, exact candidate commit, checks and evidence limits, architecture/doc reconciliation, packaged-app validation, artifacts and publication result. Reuse feature evidence where applicable; run release-wide checks for integration and packaging risks. Milestone completion is not proof of release readiness.

Prepare the version/changelog and final architecture on the release branch, validate the candidate, and open the release PR into `main`. Merge only with user authorization and stable passing checks/review gates. Verify the resulting `main` commit and validate/build the actual release artifacts from that commit before tagging it `vX.Y.Z` and publishing the GitHub Release. If the merge or subsequent changes alter the candidate, rerun affected checks; never label an untested artifact as the tested candidate. A draft release may stage notes/assets before publication. Published version tags are immutable; corrections get a new version.

Close the release issue and milestone only after verifying the main merge, tag, published release and downloadable artifacts. Record exact commit/tag and evidence links. If publication fails after merge, leave the release issue open and resume from the recorded state; do not claim shipped or move an existing tag. Actual merges and publication require explicit user authorization, which may cover a whole release in advance.

The milestone's issue/PR membership is the scope list. Use the [release template](../.github/ISSUE_TEMPLATE/release.yml); it is not another feature checklist. Do not switch another worker's checkout or rewrite its history. Reconcile package/tag conventions before choosing the actual version. Record source/toolchain/runtime/model provenance and packaged-app evidence in the release issue; staging sidecars or milestone percentage cannot establish readiness.

## Reference entry points

- [Product-first review and integration](https://github.com/kellyjanderson/readaloud/issues/110); [repository cleanup](https://github.com/kellyjanderson/readaloud/issues/115).
- [Drama 3 fiction reading](https://github.com/kellyjanderson/readaloud/issues/111), [model variants and live switching](https://github.com/kellyjanderson/readaloud/issues/112), and [required concurrency repairs](https://github.com/kellyjanderson/readaloud/issues/113).
- [Existing MLX/full-document implementation](https://github.com/kellyjanderson/readaloud/issues/109), [RC2 product requirements](https://github.com/kellyjanderson/readaloud/issues/83), and [outstanding integrated acceptance](https://github.com/kellyjanderson/readaloud/issues/91).
- [Release compliance](https://github.com/kellyjanderson/readaloud/issues/55).

### Earlier implementation evidence

- [Prepared-document runtime design](https://github.com/kellyjanderson/readaloud/issues/48); accepted direction R1 is linked in its decision comment.
- [P0 baseline](https://github.com/kellyjanderson/readaloud/issues/49), [P1 preparation](https://github.com/kellyjanderson/readaloud/issues/50), [P2 resident resources](https://github.com/kellyjanderson/readaloud/issues/51), [P3 worker planning](https://github.com/kellyjanderson/readaloud/issues/52), [P4 assignment/cache](https://github.com/kellyjanderson/readaloud/issues/53), [FINAL acceptance/reconciliation](https://github.com/kellyjanderson/readaloud/issues/54).
- [Release compliance](https://github.com/kellyjanderson/readaloud/issues/55).

These links are navigation, not a copied progress checklist. Consult GitHub for live state.

## Migration receipt and proof limits

On October 24, 2026 the ACD at commit 62a16f3 moved to #48; its complete slice plan moved to #49–#54, with native parent/dependency relationships. The supplementary target contract moved into #48 and integrated verification scenarios into #54. The compliance plan moved to #55. Original files remain recoverable in Git history. Active copies were removed rather than synchronized. Legacy archives and detailed historical contracts are retained as references, not new working-document locations.

The documentation checker rejects local working files in the retired ACD/planning directories and checks local documentation links/legacy architecture ownership. It does not contact GitHub or prove live issue state. Track planning-only mutations, maintenance/recovery effort and available token usage across actual changes; allowance savings remain unproven.

## Access and automation

GitHub Actions is disabled at the repository level at the user's request: there is no budget for Actions. Keep it disabled and use local documentation, source and runtime checks as appropriate. Do not dispatch workflows, enable Actions, add automatic CI, or treat a new Actions run as an integration prerequisite. Existing completed checks are historical evidence; record local commands/results on new PRs. Paid execution requires explicit user approval. If a repository rule blocks merging without Actions, report that conflict rather than enabling Actions or bypassing the rule silently.

The board enables auto-add for open Read Aloud issues, auto-add for sub-issues and an initial Proposed status. Auto-close, close-to-Done, merge-to-Done and linked-PR-to-In-Progress shortcuts are disabled. The orchestrator owns lifecycle transitions. Repository issue/PR API access and Projects access are separate permissions: CLI Project operations require the project scope; use the authenticated GitHub browser if it is unavailable. Do not silently fall back to local plan files.
