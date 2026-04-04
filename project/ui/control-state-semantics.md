# Control State Semantics

Controls in `Read Aloud` should use explicit semantic states rather than ad hoc visual treatment.

## Core States

There are currently three important control states:

- active
- inactive
- inactive but communicating

## Active

An active control:

- accepts interaction
- presents normal emphasis for its role
- does not need a special communicating treatment

## Inactive

An inactive control:

- does not accept interaction
- is visually muted
- is not actively communicating ongoing work or state transition

## Inactive But Communicating

An inactive-but-communicating control:

- does not accept interaction
- remains visually muted at the control-body level
- continues to communicate status through its icon or indicator

The communicating icon or indicator must maintain high contrast against the muted control background.

For this state, the icon or indicator should use whichever of black or white produces the strongest contrast against the selected grey background.

## Current Known Case

The known current case is the play control after the user presses play but before audio is actually produced.

During that interval:

- the button is not clickable
- the button is still communicating work in progress
- the communicating glyph should remain high contrast

Related issue:

- [GitHub Issue #1](https://github.com/kellyjanderson/readaloud/issues/1)
