# Desktop Reader Title Chrome Minimization

Paired feature specification:

- [Desktop Reader Title Chrome Minimization](../specifications/desktop-reader-title-chrome-minimization.md)

## Manual Smoke Check

- Launch the desktop app and confirm the native window chrome identifies the app without a second prominent in-app `Read Aloud` title.

## Automated Smoke Expectations

- widget tests for macOS shell behavior verify the in-app app-bar title is absent while native menu-bar integration remains present

## Automated Acceptance Expectations

- acceptance coverage proves desktop shell identity is carried by native platform chrome rather than redundant in-app repetition
