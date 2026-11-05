# Read Aloud repository workflow

This is the authoritative process. Current architecture and versioned interim design documents stay in Git; published design decisions, active execution, assignments and evidence records live in GitHub. Local skills are procedures, not competing authorities.

## Non-negotiable product expectations

Apply the [product definition](project/product-definition.md) and [README reading expectations](README.md) to every design, implementation and acceptance decision. They are requirements, not assertions of current conformance; [issue #83](https://github.com/kellyjanderson/readaloud/issues/83) records the present gaps.

- With a document available and Play requested promptly, opening the app to smooth audible speech must take at most two seconds, regardless of document size. Do not hide initialization/preparation time by moving the measurement start.
- All reading work is dynamic and incremental, including acquisition, parsing, normalization, mapping, analysis, planning, resource binding, synthesis and persistence. Character discovery is only an example. Do not require whole-document completion before first speech; maintain bounded work ahead of playback and explicit revision/cancellation ownership.
- Keep the interface responsive throughout. Pending playback must be cancellable without waiting for background work to drain; obsolete completion must not trigger speech.
- Work exceeding one or two seconds requires a dynamic progress bar with real completed-work accounting, truthful stage/total/wait states and actionable failure. No pretend progress or premature 100%.
- Automatically persist processed input to reusable `.radoc` so valid second runs skip completed preparation. Preserve inflection and other speech directions as content intent; retain the long-term publishing goal independently of current engine support.
- Prefer maintained packages and platform facilities for general-purpose infrastructure. Evaluate existing solutions before writing bespoke scheduling, queues, cancellation, caching or persistence; document the concrete unmet requirement for custom replacements. Application-specific policy and integration remain project responsibilities.

Demonstrate these expectations in the running app with launch-to-audio timing, input responsiveness, emitted-audio continuity and appropriate human listening. Unit tests, codec round trips and internal readiness flags alone cannot establish conformance. Do not silently weaken requirements to fit the current implementation or expand an already accepted release scope without its coordinator's explicit reconciliation.

## Start with bounded context

Read README.md, project/README.md and docs/project-management.md. Start issue retrieval with `ruby tools/read_issue_context.rb NUMBER` for the parent and assigned slice; it returns only the maintained current block. On first assignment or a changed design revision, also read the relevant contract sections, linked accepted decisions and affected architecture/source/tests. Routine re-entry reads current blocks and changed evidence only, not full bodies/comment histories. Missing or stale blocks require bounded reconciliation, never assuming readiness. Archived files are historical references only.

## Authority and ownership

- `project/architecture/`: implemented structure, intent, invariants, durable rationale and honest evidence limits. Update with implementation; never promote a proposal to current fact.
- GitHub design issue: working ACD, scope, alternatives, decisions, acceptance and architecture targets.
- `project/interim/`: Git-tracked design drafts and immutable published revision snapshots, with source issue/revision, lifecycle and reconciliation links. Follow its README; never rely on volatile `tmp/` for design documents. GitHub current blocks and Project Status still own execution; do not mirror live issue bodies or progress here.
- Native sub-issues/dependencies: implementation slices and readiness. Small fixes may use a single issue.
- GitHub Project: authoritative status and priority. Marked issue-body blocks: current coordination/work orders and exact evidence pointers. Issue comments: durable decision, handoff and evidence receipts; historical claims do not supersede a reconciled current block without new evidence.
- GitHub milestone: release scope, tentative version, intended outcomes and exclusions. One release issue owns release-wide readiness and publication; link feature evidence instead of copying plans.
- `docs/`: durable setup, usage and process guidance. `project/ui/`, legacy specifications/test specifications and research are retained references; new substantial design drafts use `project/interim/` and publish to their owning issues.
- `project/archive/` and historical journals: preserved history, not active instructions. Design drafts and fixed plan snapshots belong only in `project/interim/`; do not create local progress journals, task checklists, release-status ledgers or mirrored issue bodies. Ignored `tmp/` may hold disposable transport payloads, never design-document storage. After implementation, reconcile accepted design into current architecture and record evidence in GitHub before retiring interim files through a reviewed Git change; history preserves the revision.

## Orchestrator and workers

An orchestrator chat may coordinate multiple workers, worktrees and slice PRs. No single-branch/single-PR rule may prevent safe delegation. The orchestrator owns parent design, dependency readiness, assignment claims, integration and final reconciliation. Workers own their assigned files/modules and report in their slice issue.

Maintain one `<!-- readaloud:current:start -->` / `<!-- readaloud:current:end -->` block at the top of each active issue. Parent target: 400–700 tokens; slice target: 250–500. Update at dispatch, blocker, handoff, integration or decision changes. Include revision, owner, base/target, active ownership/dependencies, next action, model/effort, remaining acceptance and exact decision/evidence links. Keep Project Status authoritative. Preserve the design and historical evidence outside the block; summaries never waive acceptance. Re-fetch before writing and preserve unrelated body changes. Comments record new evidence/decisions, not repeated whole-state copies.

Use a fresh subagent with no inherited conversation (`fork_turns: none`) for each bounded task; keep its focused fix/test cycle together, then retire it. Give compact work orders, not whole histories. The standalone orchestrator uses Luna/medium; workers default to Sol/medium, Sol/high for ambiguous debugging or independent acceptance review, and Luna/low for mechanical checks. Record exact available model IDs and effort. Astra defaults to medium for unresolved architecture only. Obtain human approval before Astra/high or higher, round 3 within one Astra task, consecutive Astra task 3, or total Astra task 4 per orchestration. Count substantive assignments/follow-ups across nested agents and replacements; tool calls/waits are not rounds. Track counters in the parent current block; a fresh chat does not reset them. Approval grants a bounded extension. Do not invent usage/cost figures.

Before dispatch, record the worker/chat identity, design revision, scope/exclusions, exclusive file/module ownership, dependency state, base commit, branch/worktree, target integration branch, acceptance checks and return contract. Workers are not alone: preserve others' changes, do not revert unrelated edits, and coordinate overlap before writing. Use isolated `codex/<feature>-<slice>` branches/worktrees when concurrency would collide. Do not concurrently edit the same checkout/index.

User-requested orchestration authorizes appropriate subagent delegation; creating or messaging separate user-owned chats still requires the platform's user authorization. Do not invent thread identities. Subagents return through their parent; the orchestrator publishes durable checkpoints. Platform limits and user restrictions take precedence.

Read the latest design revision before starting and before integration. A material scope change is an orchestrator decision recorded as a new revision; pause only affected work. Do not mutate parent scope from a worker. Claims are advisory, not a lock: the orchestrator is the single dispatcher and resolves duplicate/stale claims explicitly. No force takeover or duplicate dispatch merely because a chat is quiet.

## Delivery and completion

The user has no budget for GitHub Actions. Keep repository Actions disabled; do not enable, dispatch, or add automatic workflows. Run bounded checks locally and report their results. Do not require new remote CI runs for integration; historical CI is evidence only. Any paid service/execution or change to this constraint requires explicit user approval.

Use scoped branches, preserve WIP, stage intentional paths. Link slice and parent in every PR; use `Refs` for the parent so an intermediate merge cannot close the feature. Declare the actual PR base. Create each release working branch as `codex/release-<version-or-name>` from freshly fetched `origin/main`; record its starting commit in the release issue. Worker/feature branches start from the assigned release branch (or a declared dependency branch) and target that release branch, optionally through a feature integration branch. Do not merge individual release slices directly into `main`. Preserve existing work: record how an existing feature branch will join the release rather than resetting or rewriting it. Process-only maintenance may use a scoped branch from main and a PR back to main, explicitly marked as outside a product release. No merge or push directly to main without explicit user authorization; this process definition is not authorization to publish a release.

Run bounded relevant checks; report passed, failed, blocked and not run distinctly. Checkpoints report result, changed paths, commit/PR, base, evidence and remaining work. Batch meaningful updates; no heartbeat comments, repeated whole-plan rewrites or routine agent polling.

Final slice reconciles architecture and human docs in the implementation/final PR, verifies required evidence and merged commits, then closes the feature. `Reconcile` is a real gate; merged PRs, closed children or Project Done alone do not prove acceptance. Record missing evidence explicitly and leave incomplete work open. Never archive a feature as a substitute for finishing it. A feature may close after acceptance and reconciliation are merged into the declared release branch; record that it is integrated but unreleased. Do not rely on GitHub auto-closing issues for PRs targeting a non-default branch. Do not delete release branches/worktrees until the release merge is verified on local `main` and publication is verified.

## Releases

Use one GitHub milestone and one release issue per release. Keep tentative versions, scope changes, assignments and readiness evidence in GitHub; do not create local release plans or planning-only tags/releases. Change package version metadata only when preparing a real release candidate. The release coordinator owns integration and release readiness; feature orchestrators retain their bounded assignments.

The release issue records the milestone, release branch/base, included feature links, dependencies, version decision, release PR, exact candidate commit, checks and evidence limits, architecture/doc reconciliation, packaged-app validation, artifacts and publication result. Reuse feature evidence where applicable; run release-wide checks for integration and packaging risks. Milestone completion is not proof of release readiness.

Prepare the version/changelog and final architecture on the release branch, validate the candidate, and open the release PR into `main`. Merge only with user authorization and stable passing checks/review gates. Verify the resulting `main` commit and validate/build the actual release artifacts from that commit before tagging it `vX.Y.Z` and publishing the GitHub Release. If the merge or subsequent changes alter the candidate, rerun affected checks; never label an untested artifact as the tested candidate. A draft release may stage notes/assets before publication. Published version tags are immutable; corrections get a new version.

Close the release issue and milestone only after verifying the main merge, tag, published release and downloadable artifacts. Record exact commit/tag and evidence links. If publication fails after merge, leave the release issue open and resume from the recorded state; do not claim shipped or move an existing tag. Actual merges and publication require explicit user authorization, which may cover a whole release in advance.

## Execution and evidence


Every asynchronous producer names its owner, execution context, bounded queue, revision/session identity, stale success/failure handling, cancellation/timeout, shutdown and proof scenario. `async` is not CPU offload. UI state belongs on Flutter's main isolate; preparation, planning, inference, assembly and heavy I/O need explicit worker/native ownership.

Audio changes need comparable emitted-audio evidence; source tests, hashes, listening and native runtime checks answer different questions. User-facing acceptance requires the running app. Keep automatic speaker routing distinct from user assignment edits and preserve uncertainty. macOS is the current functional target; verify SDK architecture before use. Never report unrun tests as passed.

Any agent that launches the application for UI, native, audio, or acceptance testing must quit the application when that test session ends, including when the test fails or is blocked. Use the app's normal Quit action, then verify its process has exited before finishing the test or development task. Do not leave a test build running between cases. Record inability to close or verify as a test blocker. Automated test commands that launch a UI app must likewise clean up their owned process before returning.

GitHub outages or missing access do not justify a second local planning authority. Preserve code work, report the blocker and resume publication when access returns. Do not alter model assets, user data, signing or installed apps during a process-only change.
