# Desktop Reader Title Chrome Minimization

Status: final

## Overview

This specification defines the desktop Reader-shell rule that native window chrome should carry app identity without duplicating that same title inside the in-app app bar.

Issue anchor:

- GitHub issue `#39`

## Backlink

Parent specification:

- [App Shell And Platform Navigation UI](app-shell-and-platform-navigation-ui.md)

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
