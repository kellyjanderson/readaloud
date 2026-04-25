---
name: workflow-readaloud-overlay
description: Apply Read Aloud-specific workflow expectations around issue or specification anchors, paired verification, and surfaced running-app outcomes.
---

# Read Aloud Workflow Overlay

This Skill adds Read Aloud-specific workflow emphasis on top of `workflow-core`.

## Anchor Rule

Implementation work should stay on the issue-or-spec path for this workspace.

Do not rely on ad hoc implementation without a durable issue or specification anchor.

## Verification Rule

Every final feature leaf should gain a paired test specification when it is marked final.

Keep implementation completion and verification completion separately visible.

## Surfaced Outcome Rule

For user-facing work, do not treat internal enablement as full completion until the running app exposes the intended outcome.
