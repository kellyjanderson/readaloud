# Project Agent Rules

This folder is the canonical place for `Read Aloud`-specific agent rules.

Use this folder for durable project-specific instructions that affect how agents should operate in this repository, but that do not belong in product, architecture, specification, planning, or research documents.

Examples include:

- project-specific coding rules
- project-specific debugging workflows
- project-specific release or QA procedures
- project-specific document maintenance rules
- project-specific UI and brand operating rules

## Current Documents

- [UI, Brand, and Component Rules](ui-brand-and-component-rules.md)

Shared UI structural rules also apply from:

- [`agents/ui-ux-invariants.md`](../../agents/ui-ux-invariants.md)

## Audio Change Verification Rule

For pronunciation, synthesis, and other speech-output fixes, agents must verify that a code change produced a real audio change before claiming the fix had effect.

Use the pronunciation probe and audio comparison workflow when working on these issues.

The rule is:

1. capture a baseline audio run for the target phrase or phrases
2. make the code change
3. capture a second run for the same phrases
4. compare the before and after audio outputs

If the before and after output is identical, the change did not materially affect synthesis and should not be treated as a successful fix.

For this project, prefer the existing headless pronunciation probe path and compare PCM hashes or equivalent waveform-level analysis rather than relying only on code inspection or casual listening.

When reporting work on pronunciation or TTS behavior, agents should state whether:

- the emitted audio changed
- the emitted audio did not change
- or audio change verification was not completed

Do not present a pronunciation fix as successful if audio change verification has not been performed or if the compared output remained identical.

## Implementation Anchor Rule

For this project, implementation changes must not happen without a durable planning anchor.

Allowed anchors are:

1. a specification for feature work
2. an issue for bug-fix work

This is a hard rule.

Code changes should not begin from ad hoc discussion alone.

## Issue Back-Reference Rule

Issue-driven fixes must be back-referenced into the project architecture/specification tree.

That means a bug fix must update the durable project documents that describe the affected behavior, such as:

- an existing architecture document
- an existing specification document
- or a new specification when the tree does not yet cover the behavior that the issue exposed

The goal is that issue work does not live only in:

- GitHub issue text
- branch history
- pull request text
- and code changes

The architecture/specification tree must remain the durable source of truth for the resulting behavior.

## Observable Feature Completion Rule

For this project, user-facing features are not complete until they surface and can be observed in the running app.

Internal support work may still be valuable and may still have its own final leaf specifications.

It must not be reported as completing the user-facing feature unless the intended outcome is visible, audible, or directly interactive in the running app.

Examples:

- automatic voice switching is not complete until playback actually switches voices in the running app
- appearance-mode work is not complete until the running app can be observed following or overriding system theme
- primary-surface simplification is not complete until the running UI actually reflects the simplified control surface

When refining specifications for user-facing work, at least one final leaf must capture the surfaced running-app outcome explicitly.

When a user-visible settings surface, dialog, or panel exists in the running app, it should also have an explicit named UI/specification parent branch.

Do not leave a live surface represented only by scattered behavior leaves with no parent surface definition.

## Feature Test Specification Rule

For this project, every final feature leaf specification should have a paired test specification in:

```text
project/test-specifications/
```

The paired test specification should be created when the feature leaf is marked final, not later as an afterthought.

Manual guidance may stay short.

Automated coverage expectations should be the heavier part of the document, with emphasis on:

- smoke tests
- acceptance tests
- stable fixtures and observable regressions

Feature implementation should use the paired test specification as the verification contract for that leaf.

When progression is updated for a feature leaf, the paired test specification may also be added as its own checkbox so implementation completion and verification completion remain separately visible.

## Implementation vs Verification Tracking Rule

For this project, progression implementation checkboxes and test-specification checkboxes serve different purposes.

The rule is:

- mark the feature leaf complete when the implementation work for that leaf is done
- keep the paired test specification open until the verification work is done

Agents should not leave an implementation leaf unchecked just because manual testing or broader acceptance verification still remains.

That remaining work belongs in the paired test-spec checkbox.

## UI Guide Distillation Rule

When broad UI-system documents change, agents must distill the implementation-relevant decisions into `project/agents/`.

This rule applies at minimum to:

- `project/ui/brand-guide.md`
- `project/ui/design-guide.md`
- `project/ui/component-system.md`

The goal is that agents always have a project-local operational layer for:

- brand voice
- terminology
- typography
- color direction
- workspace rules
- component rules
- desktop navigation expectations

Do not leave major UI-system decisions only in broad guide prose.

## Relationship to `agents/`

The root [`agents/`](../../agents/index.md) folder defines repository-wide agent process and workflow guidance.

This `project/agents/` folder defines additional rules that are specific to `Read Aloud`.

The intended hierarchy is:

1. shared agent process in `agents/`
2. project-specific agent rules in `project/agents/`
3. project product and system documents in the other `project/` folders

Project-specific rules should supplement or narrow the shared agent guidance for this project. They should not restate architecture, specifications, or planning content that already belongs elsewhere.

## Usage

Agents should check this folder before beginning substantial work on the project.

If a new project-specific operating rule is discovered, it should be recorded here rather than improvised in chat history.
