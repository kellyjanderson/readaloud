---
name: implementation-plan
description: Coordinate bounded GitHub implementation slices for a Read Aloud design issue.
---
# GitHub implementation slices

Read AGENTS.md and docs/project-management.md#directed-work, then the owning issue, parent when present and accepted revision. Before dispatch/delegation read #conditional-orchestration; load issue-write and delivery procedures only when applicable. Use native sub-issues/dependencies and Project Status for execution. Substantial plan drafts and fixed published snapshots may live in Git-tracked project/interim/<revision>/ under its lifecycle guide; never keep design documents in tmp/ or mirror live progress locally. TEMPLATE.plan is a slice issue-body outline. An orchestrator may delegate independent work to isolated branches/worktrees with scoped ownership, base commit, acceptance and return contract. One PR per plan is not required. Workers preserve other work and report evidence to their slice or orchestrator. The orchestrator is the single dispatcher and integration owner; no duplicate claims or uncoordinated parent edits. FINAL verifies acceptance, merged architecture/user docs and integration target before closing the feature. Reconcile and retire interim documents through reviewed Git changes. Batch checkpoints; do not poll or duplicate status in files.
