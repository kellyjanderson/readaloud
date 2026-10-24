# Contributing to Read Aloud

Start with [setup](docs/development.md), [project navigation](project/README.md) and [AGENTS.md](AGENTS.md). Read Aloud currently targets macOS; other generated Flutter targets are not qualified by this repository review.

Architecture changes use one [ACD](project/acd/README.md) and a same-name [implementation plan](project/planning/README.md). Small fixes that conform to existing architecture can use an issue or dated journal entry. Use one branch/PR per plan; no new nested specification tree is required.

Preserve unrelated changes. Include focused validation and reconcile current architecture and relevant human documentation with the code. Audio changes require emitted-audio verification and user-visible changes require running-app evidence. Distinguish tests not run from tests passed.

Submit a PR with the problem, resulting behavior, planning anchor and validation. A maintainer authorizes merging. See the [code of conduct](CODE_OF_CONDUCT.md), [security policy](SECURITY.md) and [support guidance](SUPPORT.md).
