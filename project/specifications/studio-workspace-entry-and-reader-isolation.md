# Reader-Only App Shell Until Authoring Exists

Status: final

## Overview

This specification defines the current product rule that the shipped app shell remains Reader-only until there is real implemented authoring work to surface.

## Backlink

Parent specification:

- [App Shell And Platform Navigation UI](app-shell-and-platform-navigation-ui.md)

## Scope

This specification covers:

- Reader as the default and only exposed workspace
- keeping authoring terminology and stubs out of the shipped shell
- deferring authoring entry points until there is meaningful implemented functionality behind them

## Behavior

The app must open into the Reader workspace by default.

The current product phase must not expose a `Studio` entry, `Studio` menu item, or authoring-workspace stub on desktop or mobile.

The Reader workspace must not expose authoring controls, authoring terminology, or placeholder panels for unimplemented authoring work.

Future authoring functionality may earn its own workspace later, but until that work exists, the shell should stay reading-first and free of unused stubs.

## Constraints

- no placeholder authoring surface should occupy space in the current shell
- Reader must stay consumption-first while authoring remains unimplemented
- future authoring work must re-enter the tree through new specs rather than through dormant UI affordances

## Acceptance

- the running app opens into Reader by default
- the running app does not expose a Studio entry or authoring stub on desktop or mobile
- Reader does not surface Studio controls or terminology on the main reading surface
