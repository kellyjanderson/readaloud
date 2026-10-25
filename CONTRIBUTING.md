# Contributing to Read Aloud

Start with [setup](docs/development.md), [project navigation](project/README.md), [AGENTS.md](AGENTS.md) and the [GitHub workflow](docs/project-management.md). macOS is the current functional target.

Propose changes in GitHub issues. A design issue holds the working ACD; native sub-issues and dependencies hold implementation slices. Small fixes need only one issue. Do not create repository-local plans, ACDs, progress files or mirrored issue bodies.

Orchestrator chats may delegate isolated slice branches/worktrees and coordinate multiple PRs. Each assignment names ownership, base and acceptance. Preserve unrelated work. PRs link parent and slice; use Refs for a parent feature until final acceptance and architecture reconciliation are complete.

Reconcile architecture and relevant human docs with implementation. Audio changes need emitted-audio evidence; visible changes need running-app verification. Report blocked/unrun checks honestly. Maintainers authorize merges. See [conduct](CODE_OF_CONDUCT.md), [security](SECURITY.md) and [support](SUPPORT.md).
