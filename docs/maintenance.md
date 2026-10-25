# Maintenance and GitHub workflow

## Repository and GitHub boundary

Working design, planning, assignments, blockers and evidence records live in GitHub. Final architecture and human documentation remain in Git and are reconciled with implementation. See [project management](project-management.md) for live entry points and orchestrator handoffs. Multiple isolated worker branches and slice PRs are supported; no duplicate local plan is required.

The documentation checker validates local paths and reciprocal legacy architecture links, and rejects working files in retired ACD/planning locations. It does not establish semantic correctness or runtime conformance.

## GitHub options checked October 24, 2026

Read Aloud is a public personal repository. Most useful features below are available without a paid upgrade. GitHub Pro is the smallest paid personal plan; GitHub's published FAQ lists $4/month. Team is the organization-oriented option; the current pricing page advertises $4/user/month for the first 12 months. Check checkout terms before purchasing. [Plan comparison](https://docs.github.com/en/get-started/learning-about-github/githubs-plans), [Pro price](https://docs.github.com/en/get-started/learning-about-github/faq-about-changes-to-githubs-plans), [Team pricing](https://github.com/pricing).

| Feature | Recommended use | Avoided repeated agent work |
| --- | --- | --- |
| Issues and milestones | One design issue per outcome, sub-issues per bounded slice, milestone per release | Rediscovering scope and release grouping |
| Projects | One board/table with Backlog, Ready, In progress, Review and Done; link issues/PRs | Hand-maintained status reports and duplicate trackers |
| Built-in Project workflows | Auto-add related items; retain an explicit evidence/reconciliation gate before Done | Polling an agent merely to keep status current |
| Pull requests and required checks | Review the exact diff; require deterministic checks before merge | Repeating mechanical review in chat |
| Actions | Start with documentation checks; add Flutter/native jobs once model acquisition and toolchain are reproducible | Agent tokens spent rerunning predictable validation |
| Grouped Dependabot updates | Consider weekly or monthly grouped Dart updates with a small PR limit; isolate native inference updates | Repeated package-version searches and many small PRs |

[Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects) supports board, table and roadmap views. [Built-in workflows](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations) can update status from repository events. [Dependabot configuration](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference) supports grouping and schedules. The vendored ONNX override still needs deliberate upstream comparison; a package update cannot reconcile its local patches.

Pro adds private-repository review/protection features and higher included quotas. It does not increase Codex allowance or include a paid Copilot entitlement. No paid AI reviewer is assumed here. Existing public-repository features are sufficient to start. Exact token savings cannot be promised; avoiding duplicate documents, status polling and repeated deterministic checks is the mechanism.

A Read Aloud Project and design/slice issues were created during migration. No billing change, branch protection or Dependabot schedule was enabled. The documentation workflow is committed configuration; it runs after publication according to its event triggers. Choose account-level settings separately.

## Release decisions still needed

- Select the project's license and complete third-party notices; no license was invented during cleanup.
- Decide the next release identity: historical Beta 2/0.3.0 notes differ from package `1.0.0+1`.
- Pin model provenance/checksum and establish reproducible native CI before claiming clean-clone build qualification.
- Review remaining legacy ancestors whose refinement or semantic coverage is unresolved; do not archive merely because a heading lists children.
- Capture native memory/audio/GUI evidence for runtime claims. Source reconciliation is not installed-app validation.

## External planning evaluation — October 24 clarification

The costs to test are (1) agent work maintaining planning documents and (2) dirty source checkouts, commits and reconciliation caused by planning edits. External planning may reduce these costs, but token/allowance savings have not been established.

The sibling `project managment` prototype defines typed/versioned records (ACD-001), narrow lifecycle operations and compact context packets (ACD-004), and provenance-preserving import/export (ACD-005). Its intended authority includes architecture as well as plans. These are inspected design intentions, not a verified end-to-end service. Some of its design still assumes recursive specs and paired test specs; integration should not silently reintroduce that older process.

GitHub Issues/sub-issues can hold change proposals and bounded slices; dependencies represent blocking relationships; Projects fields hold status and priority. These records live outside source branches. GitHub supports [dependency APIs and webhooks](https://github.blog/changelog/2025-08-21-dependencies-on-issues/), [Projects REST operations](https://github.blog/changelog/2025-09-11-a-rest-api-for-github-projects-sub-issues-improvements-and-more/) and [built-in automation](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project). An adapter would still need to enforce project-specific readiness/evidence rules, stable approved revisions and compact context retrieval. External records do not remove semantic reconciliation with implemented code.

Selected pilot: the prepared-document feature now uses GitHub design and slice issues. Compare its maintenance cost with the prior lightweight file workflow. Use one authority, no bidirectional Markdown mirror, explicit approved revision/hash, and code/PR/evidence links. Export only at deliberate backup or release boundaries. The user authorized this first migration; do not infer measured savings or migrate other repositories from this decision.

Measure matched planning/replanning/review/closure tasks: input/cached-input/output tokens where available, tool-call count and returned payload volume, planning-only file mutations/commits, conflicts/recovery turns, elapsed time and missed requirements. Include adapter/setup/maintenance cost separately and amortize it over realistic task volume. Hold model, task scope and quality gates comparable; repeated observations are needed. Account allowance changes are a separate coarse observation, not interchangeable with token counts. No numeric savings claim is established.
