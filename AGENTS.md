# Read Aloud repository workflow

This is the authoritative process. Current architecture stays in Git; active design, planning, assignments and evidence records live in GitHub. Local skills are procedures, not competing authorities.

## Start with bounded context

Read README.md, project/README.md, docs/project-management.md, the assigned GitHub issue and affected architecture/source/tests. Fetch the current issue body and relevant decision/handoff comments, not the entire history or legacy tree. Archived files are historical references only.

## Authority and ownership

- `project/architecture/`: implemented structure, intent, invariants, durable rationale and honest evidence limits. Update with implementation; never promote a proposal to current fact.
- GitHub design issue: working ACD, scope, alternatives, decisions, acceptance and architecture targets.
- Native sub-issues/dependencies: implementation slices and readiness. Small fixes may use a single issue.
- GitHub Project: authoritative status and priority. Issue comments: assignment, handoff, blockers, evidence and reconciliation records.
- `docs/`: durable setup, usage and process guidance. `project/ui/`, legacy specifications/test specifications and research are retained references; new working drafts belong in issues.
- `project/archive/` and historical journals: preserved history, not active instructions. Do not create local ACDs, plans, progress journals, task checklists or mirrored issue bodies. Ignored `tmp/` may hold disposable tool payloads, never the sole authority.

## Orchestrator and workers

An orchestrator chat may coordinate multiple workers, worktrees and slice PRs. No single-branch/single-PR rule may prevent safe delegation. The orchestrator owns parent design, dependency readiness, assignment claims, integration and final reconciliation. Workers own their assigned files/modules and report in their slice issue.

Before dispatch, record the worker/chat identity, design revision, scope/exclusions, exclusive file/module ownership, dependency state, base commit, branch/worktree, target integration branch, acceptance checks and return contract. Workers are not alone: preserve others' changes, do not revert unrelated edits, and coordinate overlap before writing. Use isolated `codex/<feature>-<slice>` branches/worktrees when concurrency would collide. Do not concurrently edit the same checkout/index.

User-requested orchestration authorizes appropriate subagent delegation; creating or messaging separate user-owned chats still requires the platform's user authorization. Do not invent thread identities. Subagents return through their parent; the orchestrator publishes durable checkpoints. Platform limits and user restrictions take precedence.

Read the latest design revision before starting and before integration. A material scope change is an orchestrator decision recorded as a new revision; pause only affected work. Do not mutate parent scope from a worker. Claims are advisory, not a lock: the orchestrator is the single dispatcher and resolves duplicate/stale claims explicitly. No force takeover or duplicate dispatch merely because a chat is quiet.

## Delivery and completion

Use scoped branches, preserve WIP, stage intentional paths. Link slice and parent in every PR; use `Refs` for the parent so an intermediate merge cannot close the feature. Declare the actual PR base. The orchestrator may integrate slice PRs into a feature branch or directly into main when authorized; always identify what has and has not reached main. No merge or push directly to main without explicit user authorization.

Run bounded relevant checks; report passed, failed, blocked and not run distinctly. Checkpoints report result, changed paths, commit/PR, base, evidence and remaining work. Batch meaningful updates; no heartbeat comments, repeated whole-plan rewrites or routine agent polling.

Final slice reconciles architecture and human docs in the implementation/final PR, verifies required evidence and merged commits, then closes the feature. `Reconcile` is a real gate; merged PRs, closed children or Project Done alone do not prove acceptance. Record missing evidence explicitly and leave incomplete work open. Never archive a feature as a substitute for finishing it. Do not delete branches/worktrees before integration is verified.

## Execution and evidence

Every asynchronous producer names its owner, execution context, bounded queue, revision/session identity, stale success/failure handling, cancellation/timeout, shutdown and proof scenario. `async` is not CPU offload. UI state belongs on Flutter's main isolate; preparation, planning, inference, assembly and heavy I/O need explicit worker/native ownership.

Audio changes need comparable emitted-audio evidence; source tests, hashes, listening and native runtime checks answer different questions. User-facing acceptance requires the running app. Keep automatic speaker routing distinct from user assignment edits and preserve uncertainty. macOS is the current functional target; verify SDK architecture before use. Never report unrun tests as passed.

GitHub outages or missing access do not justify a second local planning authority. Preserve code work, report the blocker and resume publication when access returns. Do not alter model assets, user data, signing or installed apps during a process-only change.
