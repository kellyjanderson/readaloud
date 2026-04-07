# Theme And Appearance Modes

`Read Aloud` should support explicit appearance modes rather than a fixed look.

## Supported Modes

The interface should support:

- light mode
- dark mode
- follow system

## Default

Default behavior should be:

- follow system

## Semantics

Follow system means the app adopts the operating system appearance mode automatically.

Light and dark modes should act as explicit overrides.

Appearance behavior includes the reading surface itself, not only shell chrome.

In dark mode, the reading pane should use a very dark gray surface with clearly lighter text rather than a low-contrast light-on-light presentation.

## UI Placement

Theme selection is not a primary reading control.

It should live in a lower-complexity settings path rather than competing with the core reading controls on the main surface.

For the current app shell, the preferred placement is Reader Options rather than the primary reader bar.
