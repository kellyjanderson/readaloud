# Mobile Overflow Menu Domain Grouping

## Backlink

Feature specification:

- [Mobile Overflow Menu Domain Grouping](../specifications/mobile-overflow-menu-domain-grouping.md)

## Manual Smoke Check

- Open the mobile overflow menu.
- Confirm the commands are visually grouped by domain rather than shown as one flat miscellaneous list.

## Automated Smoke Expectations

- widget coverage should verify that the mobile overflow menu includes lightweight grouping treatment such as dividers between command domains
- widget coverage should verify that grouped menu domains still expose the current expected commands

## Automated Acceptance Expectations

- automated UI tests should verify that document-intake actions, export actions, live-input actions, and Reader Options remain present and separated into readable groups
- automated tests should verify that the grouped mobile menu remains mobile-only and is not shown on desktop
