# UI System Overview

`Read Aloud` should present a clean, simple, reading-first interface.

The top-level surface should emphasize the controls a user needs for normal reading and minimize visual competition from advanced features.

## Top-Level Goal

The primary interface should feel calm, direct, and low-friction.

Complexity should exist, but it should be layered behind predictable access points instead of competing with core reading controls.

## Primary Interface Principles

- keep the main reading surface visually simple
- keep the most common reading controls immediately available
- avoid presenting domain complexity at the top level unless it is part of normal reading flow
- make advanced options discoverable without making them visually dominant

## Complexity Layering

The interface should distinguish between:

- primary controls for normal reading flow
- secondary controls related to already visible UI domains
- advanced or less frequent controls that should live in menus

Default rule:

- top-level complexity should move into the File menu or other menu surfaces when it is not part of normal continuous reading
- second-level complexity for already surfaced controls should be accessed through a consistent iconographic affordance integrated into the control or control group

## Current Direction

The current direction for `Read Aloud` is:

- simplify the top-level surface
- reduce prominently displayed voice options
- keep reading transport central
- keep the current reading text visible and prominent
- move live file watching out of the primary surface and into the File menu
- make advanced control-specific behavior accessible through a consistent iconographic mechanism
