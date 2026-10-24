---
name: observable-feature-completion
description: Treat Read Aloud user-facing work as incomplete until the intended visible, audible, or interactive outcome can be observed in the running app.
---

# Observable Feature Completion

For Read Aloud, user-facing features are not complete until they surface in the running app.

## Completion Rule

Internal support work may still be valuable and final.

It must not be reported as completing the user-facing feature unless the intended outcome is visible, audible, or directly interactive in the running app.

## Specification Rule

When refining specifications for user-facing work:

* at least one final leaf must capture the surfaced running-app outcome explicitly
* live settings surfaces, dialogs, or panels should have explicit named UI or specification parent branches

Do not leave a live surface represented only by scattered behavior leaves.
