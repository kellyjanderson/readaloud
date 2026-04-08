# Transient Feedback Toast Behavior

Status: final

## Overview

This specification defines the non-blocking feedback pattern for ordinary surfaced runtime messages in the Reader workspace.

Issue anchor:

- GitHub issue `#24`
- GitHub issue `#26`
- GitHub issue `#38`
- GitHub issue `#36`
- GitHub issue `#42`

## Backlink

Parent specification:

- [Primary Reader Surface UI](primary-reader-surface-ui.md)

## Scope

This specification covers:

- transient in-app toast behavior
- layout-stability requirements for surfaced feedback
- separation between user-facing feedback and debug-facing diagnostics
- copy hierarchy for recoverable warnings and errors
- routing of menu-triggered or command-triggered non-blocking failures through the same surfaced feedback system
- app-level toast layering across dialogs and modal surfaces

## Behavior

Ordinary non-blocking runtime feedback in the Reader workspace must use a toast-style surfaced message rather than an inline banner that pushes the reading surface downward.

This same rule applies to recoverable command-triggered failures such as export-start failures or similar menu-initiated actions. Those failures should use the shared Reader feedback surface rather than a separate `SnackBar` path.

Ordinary successful document loads or restores should stay silent by default. If the user can already see that a document is now present, the Reader should not surface a redundant success toast just to confirm that obvious fact.

The toast should:

- float above the layout
- preserve the position of the reading surface and transport
- use concise user-facing language
- reflect severity through semantic styling

Routine technical diagnostics that are not directly useful to the user should remain in logs or diagnostics surfaces rather than being surfaced as primary reading-time feedback.

If a startup restore attempt fails but the user can still recover by simply opening the document normally, that restore failure should default to diagnostics or debug logging rather than a surfaced Reader toast.

Recoverable user-facing failures should use plain language and specific next steps when needed.

Raw exception strings should not be passed through directly to the user-facing Reader feedback surface when a plainer product-language message is available.

If a startup restore attempt fails but the user can reopen the document normally, the surfaced message must describe the recovery accurately and must not imply a more serious permission failure unless that is actually true.

App-level Reader toasts must render above dialogs and sheets instead of disappearing beneath modal surfaces.

## Constraints

- surfaced feedback must not cause visible layout shift in the Reader workspace
- surfaced feedback must remain visible even when a Reader dialog or sheet is open
- raw engine or inference error strings must not be the default user-facing copy for ordinary recoverable issues
- critical blocking states belong to overlays or dialogs, not toasts

## Acceptance

- the running app uses a toast-style non-blocking feedback surface instead of pushing the reader down with an inline banner
- ordinary Reader feedback no longer splits between toast-style surfaced feedback and unrelated `SnackBar` treatment
- ordinary recoverable feedback stays concise and readable
- ordinary successful document loads do not produce redundant toast noise
- startup restore failures that are only useful to developers remain out of the user-facing toast surface
- Reader toasts remain visible above dialogs and sheets
- debug-oriented details no longer dominate the user-facing feedback surface
- recoverable startup-restore failures are described accurately
