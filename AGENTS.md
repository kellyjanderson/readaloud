# Read Aloud repository workflow

This is the authoritative repository process. Local skills are procedures, not competing workflow authorities. The workflow is intentionally lightweight: current architecture → one ACD → one same-basename implementation plan → bounded slices → reconciliation and archive.

## Read the minimum useful context

Start with README.md, this file, project/README.md, the affected architecture and active ACD/plan. Inspect source and relevant tests. Do not load the entire legacy specification tree, archives, research or other projects by default. Use targeted search and links. Read archived material only for a specific unresolved question.

## Document ownership

- `project/architecture/`: reconciled current implementation, source pointers, invariants and honest verification limits. Never silently replace current facts with proposed behavior.
- `project/acd/<change>.acd`: temporary architectural delta, rationale, ownership, constraints, migration, acceptance and reconciliation targets.
- `project/planning/<change>.plan`: exactly one same-basename plan per active ACD; slices, dependencies, bounded validation and progress.
- `docs/`: durable setup, use and maintenance guidance for humans.
- `project/ui/`: retained interaction/design intent; consult only for affected UI work.
- `project/specifications/` and `project/test-specifications/`: retained detailed legacy contracts and evidence scenarios. Final means refinement, not passing tests. No new recursive specification stage or mandatory one-test-document-per-leaf process.
- `project/archive/`: historical architecture and superseded ancestors; never active work orders.
- `project/journal/`: dated records for unplanned changes, experiments and incidents. Do not duplicate each planned slice here.
- `project/research/`: evidence resolving specific unknowns; not an alternate task list.

`.acd` and `.plan` contain UTF-8 Markdown. Use the local ACD/plan skills and templates when needed. Keep new work proportional: a small architecture-conforming defect or documentation fix may use an issue or journal entry rather than an ACD pair.

## Delivery

Use one scoped `codex/<change>` branch for an entire plan and one PR. Preserve unrelated WIP; stage intentional paths only. Slices can become coherent commits. Do not push directly to main or merge without explicit user authorization. Run declared checks once and broaden only for changed risk or failures. Record blocked verification rather than marking it passed.

The final plan slice reconciles implemented and validated facts into architecture, updates subject-oriented human docs (or explains no impact), removes contradictions, checks links, and archives the completed ACD and plan into their respective archive directories. A proposal is not complete merely because its documents exist. Do not delete branches/worktrees until the merge is verified on local main.

## Execution and evidence

Every new asynchronous producer names its owner, execution context, bounded queue policy, revision/session identity, stale-success/failure handling, cancellation/timeout, shutdown and proof scenario. `async` is not CPU offload. Flutter UI state stays on the main isolate; preparation, planning, inference, audio assembly and heavy I/O require explicit worker/native queue ownership.

Audio-affecting fixes need comparable before/after emitted-audio evidence; unit tests, hashes, listening and native runtime proof answer different questions. A user-facing feature is complete only when the running app exposes the intended result. Keep automatic character transitions distinct from user assignment edits. Preserve model/data uncertainty.

Current functional target is macOS. Use the documented pinned SDK baseline; check CPU architecture before using the ignored local `.flutter-sdk`. Never claim tests ran because test files exist. Do not modify model weights, user documents, caches, application preferences, signing identities or installed apps during documentation cleanup.

## GitHub without duplicated state

Issues capture bugs and acceptance; a Project can show priority/status and linked PRs. Keep design in the ACD and work decomposition in the plan. Do not copy entire documents into issues or maintain a second slice checklist. Prefer deterministic CI/link checks and grouped dependency updates over recurring agent audits. Project Done/PR merged is not proof of audio acceptance.
