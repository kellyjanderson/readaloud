---
name: observable-feature-completion
description: Treat Read Aloud user-facing work as incomplete until the intended visible, audible, or interactive outcome can be observed in the running app.
---

# Observable Feature Completion

For Read Aloud, user-facing features are not complete until they surface in the running app.

## Completion Rule

Internal support work may still be valuable and final.

It must not be reported as completing the user-facing feature unless the intended outcome is visible, audible, or directly interactive in the running app.

## Acceptance Rule

When defining GitHub design and slice acceptance for user-facing work:

* the parent feature and final acceptance slice must name the observable running-app outcome
* live settings surfaces, dialogs, or panels must have clear ownership and linked durable UI/architecture references

Do not leave a live surface represented only by scattered implementation tasks.
