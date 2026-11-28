# Maintenance and GitHub workflow

Working designs and evidence live in GitHub; implemented architecture and human documentation stay in Git. Start with the [current issue index](project-management.md). Use one bounded issue for a directed fix and delegate only when independent ownership makes the work more effective. Avoid mirrored plans and routine status comments.

## Local verification

GitHub Actions must remain disabled. The former automatic documentation workflow has been removed. Run checks locally with the native arm64 Flutter SDK:

```sh
ruby tools/check_docs.rb
tools/flutter analyze
tools/flutter test
```

Choose relevant tests for a small change. A cleanup integration also runs the full source suite. Audio changes require emitted-audio and running-app checks; neither a passing suite nor a cleanup tag establishes acoustic quality, uninterrupted long-form playback or human acceptance. The [MLX guide](mlx-tts-engines.md) describes native probes and their limits.

## Branches and worktrees

Preserve uncommitted source before integration. Reconcile each independent branch tip against the intended target; patch-equivalent cherry-picked work can be recorded as historical ancestry without restoring superseded source. Merge the reviewed cleanup branch through a PR. Verify the remote main commit before creating an immutable annotated cleanup tag.

Remove only clean worktrees whose commits are integrated and whose ignored or local-only files are disposable or preserved. Check active ownership, open PRs and pending evidence before deleting branches. Never force-remove a dirty checkout or infer main integration from a feature-branch merge. Keep source and test provenance available through Git and linked issue receipts.

## Release and dependency maintenance

Follow the [release workflow](project-management.md). Keep project-license selection, model licenses, reference-voice provenance and third-party notices explicit in [release compliance](release-compliance.md). A source cleanup tag is a recoverable development baseline, not full product qualification.

Keep inference libraries and model snapshots pinned for reproducible audio. Upgrade them deliberately with comparable fixtures, memory measurements and listening evidence. A package-manager update cannot reconcile the vendored ONNX plugin's native changes.

Measure process changes using matched tasks, actual token fields when available, tool payload sizes, elapsed time and missed acceptance. Static instruction size and issue/PR counts are only proxies. Historical workflow investigations remain recoverable in Git; no allowance or productivity saving is claimed without measurement.
