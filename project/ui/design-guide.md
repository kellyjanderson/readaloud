# Design Guide

## Purpose

This document translates the brand guide into concrete visual and interaction choices for the app.

It defines:

- exact color usage
- typography application
- spacing and shape language
- motion guidance
- workspace boundaries
- key interaction patterns

## Visual North Star

`Read Aloud` should feel like a quiet editorial reader, not like a dashboard or a half-finished tool suite.

The default experience is:

- document first
- transport second
- voice sophistication third

Everything else should feel secondary.

## Workspace Strategy

The current product should expose one work mode:

- `Reader`

### Reader

`Reader` is the primary product experience.

It owns:

- opening documents
- listening
- follow-along reading
- voice selection
- cast management
- export

### Workspace Rule

Unimplemented authoring is noise on the main reader surface right now.

The main reading UI should remain consumption-first and should not surface authoring controls, authoring terminology, or placeholder workspace entries until there is real authoring functionality to support them.

## Platform Navigation

`Read Aloud` should not use the same shell-navigation strategy on every platform.

### Desktop

On macOS desktop, the app should behave like a native document app.

The current rule is:

- remove the in-app three-dots overflow menu from the desktop Reader shell
- move the commands currently collected there into native menu-bar items
- use the File menu as the primary product-facing home for those commands
- if a command belongs to the application menu by platform convention, keep the native convention rather than duplicating it in File

The desktop shell should not ask the user to choose between a native menu bar and an in-app overflow menu for the same command family.

### Mobile

On mobile, where a native desktop menu bar does not exist, the three-dots overflow menu should remain the standard access point for secondary or global commands that do not belong on the primary reading surface.

### Platform Rule

Preserve the overflow menu on mobile.

Remove it from desktop.

## Color System

Use the brand palette through semantic tokens rather than one-off literal colors.

### Light Theme Tokens

- app background: `#F4EFE6`
- chrome surface: `#EFE7D8`
- reader surface: `#FCFAF5`
- dialog surface: `#FCFAF5`
- elevated surface: `#F6F1E8`
- border: `#D5CCBB`
- primary text: `#1F2730`
- secondary text: `#58636D`
- muted text: `#74818C`
- primary action background: `#2C7A74`
- primary action foreground: `#FBF8F2`
- secondary action background: `#DCEBE8`
- secondary action foreground: `#1F5D59`
- active highlight background: `#D6A84A`
- range highlight background: `#F1D289`
- highlight text: `#1F2730`
- info toast background: `#DCEBE8`
- info toast foreground: `#1F5D59`
- warning toast background: `#FAE7B8`
- warning toast foreground: `#6F4D11`
- error toast background: `#F4D3D3`
- error toast foreground: `#7A2E2E`

### Dark Theme Tokens

- app background: `#0F141A`
- chrome surface: `#151B22`
- reader surface: `#1A222B`
- dialog surface: `#202A34`
- elevated surface: `#26313C`
- border: `#34424E`
- primary text: `#E8E0D3`
- secondary text: `#B4BEC7`
- muted text: `#93A0AA`
- primary action background: `#5FB1AA`
- primary action foreground: `#102026`
- secondary action background: `#23333A`
- secondary action foreground: `#D4EBE8`
- active highlight background: `#B9892D`
- range highlight background: `#7F6226`
- highlight text: `#15120D`
- info toast background: `#1F3A3A`
- info toast foreground: `#D7ECEA`
- warning toast background: `#4A3614`
- warning toast foreground: `#F7E0B2`
- error toast background: `#4B2326`
- error toast foreground: `#F5D7D9`

## Typography Application

### App Chrome

Use `Source Sans 3` for:

- app bar
- menu labels
- dialog titles
- buttons
- form labels
- status and toast copy

### Reading Surface

Use `Source Serif 4` for:

- document body text
- long-form reading content

Recommended reading sizes:

- desktop default: `21px / 34px`
- mobile default: `19px / 30px`

### Technical Surfaces

Use `IBM Plex Mono` for:

- debug traces
- technical ids
- serialized internal document inspection

## Spacing And Shape

Use a simple spacing scale:

- `4`
- `8`
- `12`
- `16`
- `24`
- `32`
- `48`

Use rounded shapes consistently:

- small chip or pill radius: `999`
- control radius: `14`
- card radius: `18`
- dialog radius: `28`

## Motion

Motion should be calm and useful.

Recommended timing:

- micro state transition: `120ms`
- control-state or icon transition: `180ms`
- dialog or sheet transition: `240ms`

Avoid bouncy or theatrical motion on reading surfaces.

## Transport Recommendation

The transport should become a single segmented capsule.

### Structure

- one shared visual container
- three distinct hit targets
- left segment: jump back
- center segment: play, pause, or processing
- right segment: jump forward

### Proportions

- total control height should increase by roughly `10 to 14 percent`
- center segment should be visually wider than the side segments
- separators may be used, but they should be thin and quiet

### Visual Hierarchy

- center segment is the primary action
- side segments are secondary actions
- processing state lives only in the center segment

## Voice-Management Surface Recommendation

The voice-management dialog should behave like a curated casting surface.

Each visible voice choice should show:

- name
- quality rank
- gender when known
- locale
- one-line description when available
- preview action

Longer traits and descriptions can remain behind the information affordance.

## Feedback Hierarchy

Use exactly three surfaced feedback patterns:

- toast for critical but non-blocking user-actionable feedback
- overlay for in-progress blocking preparation
- modal dialog for rare high-consequence confirmation or failure

Routine runtime or debug noise should not become persistent inline banners.

No feedback surface should push the reading surface around.

## Relationship To Other UI Docs

- [Brand Guide](brand-guide.md)
- [Component System](component-system.md)
- [Primary Surface and Complexity Layering](primary-surface-and-complexity-layering.md)
- [Voice Library and Cast Management](voice-library-and-cast-management.md)
