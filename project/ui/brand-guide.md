# Brand Guide

## Purpose

This document defines the concrete brand choices for `Read Aloud`.

It turns broad product adjectives into reusable decisions for:

- user-facing language
- developer-facing GitHub language
- typography
- color direction
- naming

This guide sits above narrower UI surface definitions.

## Brand Position

`Read Aloud` is a calm, private reading companion.

It is not a document platform, a dashboard, or a speech lab.

The brand should feel:

- calm
- literate
- warm
- precise
- trustworthy
- quietly capable

It should not feel:

- noisy
- over-technical
- cute
- sales-heavy
- productivity-software generic

## Product Voice

The product voice should sound like a thoughtful reading tool.

It should be:

- concise
- plainspoken
- reassuring without being gushy
- specific about what the app is doing
- low on technical jargon

### Customer-Facing Voice Rules

Use:

- short sentences
- direct verbs
- plain language
- specific next steps when the user must act

Avoid:

- vague system language
- internal implementation terms
- loud marketing language inside the product
- blameful or alarming copy when recovery is simple

### Customer-Facing Voice Examples

Prefer:

- `Open a document to start reading.`
- `Analyzing voices...`
- `Character voices are ready.`
- `Could not reopen the last document. You can open it again from File > Open Document.`

Avoid:

- `Initializing ingestion pipeline`
- `Inference error while preparing later chunk`
- `Permission denied`

unless the user truly needs the exact technical detail.

## Developer And GitHub Voice

The GitHub-facing voice should still feel like the same product team, but more technical and more explicit.

It should be:

- clear
- welcoming
- specific
- low-drama
- user-impact-first

### Developer Voice Rules

Issues, PRs, and GitHub docs should:

- describe the user-facing problem first
- name the affected surface or workflow
- avoid hype
- avoid vague blame language
- state validation plainly

Prefer:

- `Fix unreadable voice-management dialog contrast in dark mode`
- `Keep quote-tag narration in narrator voice during multi-voice playback`

Avoid:

- `Major dialog bug`
- `Improve UX`
- `Fix stuff`

## Naming And Product Terms

Use these terms consistently:

- product name: `Read Aloud`
- primary workspace: `Reader`
- secondary settings surface: `Reader Options`
- voice-management entry: `Character Voices`

### Naming Rules

- Use `document` for user-facing language by default.
- Use `file` only when file-backed behavior matters.
- Use `voice` for the audible output choice.
- Use `character voice` only when multi-voice reading is active.
- Do not surface authoring-workspace terminology in the current product until there is real authoring functionality behind it.

## Typography

Use exactly these font families:

- UI sans: `Source Sans 3`
- reading serif: `Source Serif 4`
- technical monospace: `IBM Plex Mono`

### Font Roles

- app chrome, menus, dialogs, and controls use `Source Sans 3`
- document reading content uses `Source Serif 4`
- debug traces, hashes, ids, and technical metadata use `IBM Plex Mono`

### Weight Guidance

- display or large section titles: `Source Serif 4 Semibold`
- dialog and panel titles: `Source Sans 3 Semibold`
- body UI copy: `Source Sans 3 Regular`
- labels and button text: `Source Sans 3 Semibold`
- reading content: `Source Serif 4 Regular`

## Brand Color Direction

The palette should feel editorial and warm, with a trust-building teal accent.

Primary color families:

- warm paper neutrals
- dark slate reading shells
- teal primary actions
- restrained gold highlight accent

Avoid introducing new unrelated moods per surface.

### Core Palette

- `Paper 50`: `#FBF8F2`
- `Paper 100`: `#F4EFE6`
- `Paper 200`: `#E7DDCD`
- `Ink 900`: `#1F2730`
- `Ink 700`: `#58636D`
- `Slate 950`: `#0F141A`
- `Slate 900`: `#151B22`
- `Slate 800`: `#202A34`
- `Teal 700`: `#2C7A74`
- `Teal 500`: `#5FB1AA`
- `Gold 500`: `#D6A84A`
- `Gold 300`: `#F1D289`

## Accessibility Rule

The brand is not allowed to come at the expense of legibility.

If a branded color treatment reduces readability, accessibility wins and the treatment must change.

## Relationship To Other UI Docs

- [Design Guide](design-guide.md)
- [Component System](component-system.md)
- [UI System Overview](ui-system-overview.md)
