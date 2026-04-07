# Reader Options And Secondary Settings

## Purpose

Define the lower-complexity settings and diagnostics surface that supports reading without competing with the primary reader controls.

## Surface Role

The Reader Options surface is the default in-app home for settings and panels that are useful during reading but do not belong on the primary reading surface.

It is a secondary surface, not a second primary interface.

## Included Domains

This surface may include:

- voice-speed tuning for the currently selected voice
- reading-font choice
- reading-font scale
- appearance selection when appearance is not promoted to shell-native settings
- sleep-timer controls
- timing-model visibility when it supports jump and playback behavior
- speech-debug or trace panels
- current document source metadata

## Excluded Domains

This surface should not become the catch-all home for every advanced workflow.

It should not own:

- live file input controls that are defined as File-menu workflows
- primary transport controls
- large voice-library or cast-management surfaces that already have their own integrated access path

## Complexity Rule

Reader Options should support adjustment and inspection, not overwhelm the user with an unrelated wall of controls.

The surface should group controls into clear sections and keep the reading-first hierarchy intact.

## Relationship To Other UI Docs

- [Primary Surface and Complexity Layering](primary-surface-and-complexity-layering.md)
- [Theme and Appearance Modes](theme-and-appearance-modes.md)
- [Live Input and File Menu Behavior](live-input-and-file-menu-behavior.md)
