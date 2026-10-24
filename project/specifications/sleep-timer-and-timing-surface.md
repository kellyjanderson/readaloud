# Sleep Timer And Timing Surface

## Architecture ownership

- [system overview](../architecture/system-overview.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the active ACD/plan.

Status: final

## Overview

This specification defines how sleep-timer controls and timing-model visibility are surfaced through Reader Options.

## Backlink

Historical specification lineage:

- [Reader Options And Secondary Settings UI](../archive/specification-ancestors/reader-options-and-secondary-settings-ui.md)

## Scope

This specification covers:

- sleep-timer selection in Reader Options
- visibility of remaining sleep time and fade-out state
- timing-model information that supports jump and playback expectations

## Behavior

The running app must expose sleep-timer controls through Reader Options rather than through persistent primary-surface controls.

When a sleep timer is active, the Reader Options surface should show either:

- the remaining time, or
- that playback is currently fading out because the timer is expiring

Reader Options may also surface explanatory timing-model information when it helps the user understand jump behavior or playback timing.

This timing-model information is informational secondary UI. It should not compete with transport controls on the primary surface.

## Constraints

- sleep-timer controls must remain easy to reach without becoming a dominant primary action
- timing-model presentation should explain behavior rather than expose raw internal implementation detail without context

## Acceptance

- a user can set and clear a sleep timer from Reader Options in the running app
- the running app can visibly report timer-remaining or fade-out state in that surface
- timing-model information is available in Reader Options without becoming top-level interface clutter
