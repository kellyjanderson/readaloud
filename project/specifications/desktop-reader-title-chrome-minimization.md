# Desktop Reader Title Chrome Minimization

## Architecture ownership

- [reader interface and session state](../architecture/reader-interface-and-session-state.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the active ACD/plan.

Status: final

## Overview

This specification defines the desktop Reader-shell rule that native window chrome should carry app identity without duplicating that same title inside the in-app app bar.

Issue anchor:

- GitHub issue `#39`

## Backlink

Historical specification lineage:

- [App Shell And Platform Navigation UI](../archive/specification-ancestors/app-shell-and-platform-navigation-ui.md)

## Scope

This specification covers:

- desktop Reader-shell app-bar title treatment
- avoiding redundant app-name repetition when native desktop chrome is already present

## Behavior

On desktop platforms that already provide native window-title chrome, the Reader shell should not repeat the app name as a prominent in-app app-bar title.

The desktop Reader shell may keep structural spacing or top chrome when needed, but it should not spend visual weight repeating `Read Aloud` inside the content shell when:

- the window title already names the app or document
- the native menu bar already communicates app context

Mobile may keep a simple in-app app title when that title remains useful there.

## Constraints

- the desktop shell should feel calm and uncluttered
- platform-native identity cues should take precedence over redundant in-app repetition

## Acceptance

- on desktop, the Reader shell no longer repeats a prominent in-app app title when native window chrome already identifies the app
- mobile may still present a useful in-app title when appropriate
