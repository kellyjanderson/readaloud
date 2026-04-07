# Reader Options And Secondary Settings UI

Status: draft

## Overview

This specification refines the Reader Options secondary surface into implementable UI leaves.

## Backlink

Parent UI definition:

- [Reader Options and Secondary Settings](../ui/reader-options-and-secondary-settings.md)

## Scope

This specification covers:

- reading-preferences controls placed in Reader Options
- sleep-timer and timing-model controls placed in Reader Options
- diagnostics and source-information panels placed in Reader Options

## Behavior

The parent UI branch now delegates detailed implementation to child specifications.

In particular:

- reading-preferences controls belong to one leaf
- sleep-timer and timing-model presentation belong to one leaf
- diagnostics and document-source panels belong to one leaf

This parent specification keeps only the branch-level contract that Reader Options is a secondary settings surface rather than a competing primary interface.

## Constraints

- Reader Options must remain secondary to the reading surface
- controls in this surface must be grouped by purpose rather than presented as one flat list
- features that have their own menu or integrated-surface path must not be duplicated here without an explicit reason

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Reader Preferences Controls](reader-preferences-controls.md)
- [Sleep Timer And Timing Surface](sleep-timer-and-timing-surface.md)
- [Reader Diagnostics And Source Panels](reader-diagnostics-and-source-panels.md)

## Acceptance

- the current Reader Options surface is fully covered by final leaf specifications
- future work can refine this surface without inventing its structure ad hoc
