# UI, Brand, and Component Rules

This document distills the project UI guides into agent-operating rules.

It exists so agents can apply the current brand, design, and component decisions consistently during implementation and specification work without having to re-derive them from the broader guide documents every time.

## Distillation Rule

When any of these documents change:

- `project/ui/brand-guide.md`
- `project/ui/design-guide.md`
- `project/ui/component-system.md`

agents must update this folder with distilled operating rules that capture the implementation-relevant decisions.

The goal is:

- broad guides remain the design source of truth
- `project/agents/` remains the fast operational layer agents can apply directly

Do not let major UI-system changes live only in the broader guide documents.

## Shared UI/UX Invariants Rule

The repository-wide UI invariants in:

- `agents/ui-ux-invariants.md`

are mandatory for this project.

Project-specific brand, design, and component rules may refine the look and behavior of `Read Aloud`, but they do not override those structural invariants.

For this project, that especially means agents must protect:

- layout stability across loading, empty, partial, error, and full states
- stable scan positions in repeated rows and lists
- fixed or reserved regions where later content would otherwise cause layout shift
- explicit empty states instead of silent disappearance
- stable primary-action placement
- responsive adaptations that preserve hierarchy rather than merely squeezing content smaller

## Brand Rules For Agents

### Product Voice

User-facing product copy should be:

- calm
- plainspoken
- specific
- low on technical jargon
- reassuring without sounding gushy

Avoid:

- internal implementation language
- alarming copy when recovery is simple
- dashboard or enterprise-software tone

### Developer And GitHub Voice

GitHub-facing and developer-facing writing should be:

- clear
- welcoming
- low-drama
- user-impact-first

Prefer issue and PR titles that name the user-visible problem and affected surface directly.

## Naming Rules

Use these terms consistently:

- product name: `Read Aloud`
- primary workspace: `Reader`
- secondary settings surface: `Reader Options`
- multi-voice entry: `Character Voices`

Default to `document` in user-facing copy.

Use `file` only when file-backed behavior matters.

Do not surface authoring-workspace terminology in the current product until there is real authoring functionality behind it.

## Typography Rules

Use exactly these font families in UI work:

- UI sans: `Source Sans 3`
- reading serif: `Source Serif 4`
- technical monospace: `IBM Plex Mono`

Role rules:

- app chrome, dialogs, controls, menus, and buttons use `Source Sans 3`
- reading content uses `Source Serif 4`
- debug or technical surfaces use `IBM Plex Mono`

## Color Rules

The product uses one editorial-warm palette rather than separate unrelated visual moods.

Core palette anchors:

- `Paper 50`: `#FBF8F2`
- `Paper 100`: `#F4EFE6`
- `Ink 900`: `#1F2730`
- `Slate 950`: `#0F141A`
- `Slate 900`: `#151B22`
- `Slate 800`: `#202A34`
- `Teal 700`: `#2C7A74`
- `Teal 500`: `#5FB1AA`
- `Gold 500`: `#D6A84A`
- `Gold 300`: `#F1D289`

Accessibility wins over branding.

Do not preserve a branded color treatment if it makes text or controls hard to read.

## Workspace Rules

`Reader` is the default and only exposed product workspace in the current phase.

For the current phase of the product:

- authoring is noise on the main reading surface
- authoring controls should not leak into `Reader`
- placeholder authoring menus and stub workspaces should not be surfaced

## Desktop Menu Segmentation Rule

On desktop, especially macOS, native menu-bar expectations matter.

The current rule is:

- preserve the three-dots overflow menu on mobile
- remove the in-app three-dots overflow menu from the desktop Reader shell
- move the commands currently collected there into native menu-bar items
- use the File menu as the primary product-facing home for those commands on desktop
- if a command belongs to the application menu by platform convention, keep the native convention rather than duplicating it in File

That means desktop-global commands such as:

- opening documents
- app-level settings
- export
- quit or standard app actions

should continue to respect native desktop menu expectations unless the project explicitly commits to a full custom-shell navigation strategy.

Agents should not drift toward a hybrid mess where:

- some commands live in the native menu bar
- the same commands also live in a desktop custom overflow menu
- and the two systems imply different product structure

The mobile overflow menu remains acceptable because mobile does not have a native desktop menu bar.

If the project later chooses a fully custom desktop shell, that must be an explicit design-system decision and broader spec effort, not an accidental drift.

## Component Rules

### Transport

The primary transport direction is a segmented capsule:

- one visual control group
- three independent hit targets
- left: back
- center: play, pause, or processing
- right: forward

Do not implement this as one literal single button target.

### Voice Management

Voice-management surfaces should behave like curated casting surfaces.

Each surfaced voice choice should show, when available:

- name
- quality rank
- gender
- locale
- one-line description
- preview action

Preview must not require committing the assignment first.

If ordinary Reader playback is active and the user requests a preview, agents should prefer pausing playback automatically over surfacing a warning that tells the user to do it manually.

### Feedback

Use three surfaced feedback patterns:

- toast for non-blocking actionable feedback
- overlay for blocking in-progress preparation
- modal dialog for rare high-consequence cases

Do not use inline feedback surfaces that push the reading surface around unless there is a very strong reason.

If a surfaced problem is only useful to developers, such as a non-actionable startup restore failure that the user can work around by opening the document normally, prefer diagnostics or debug logging over a user-facing toast.

Reader toasts should behave like app-level feedback and remain visible above dialogs and sheets.

### Reading Surface

The reader surface should remain:

- document-first
- stable
- highly legible
- protected from overlapping shell chrome

On desktop, avoid redundant in-app app-title chrome when native window chrome already identifies the app.

### Voice Rows

Voice-library rows should preserve stable scan positions.

If metadata such as quality or gender is missing, do not let the remaining metadata or preview controls slide into a different horizontal slot.

If summary text such as a short description is missing, do not collapse the supporting-text region in a way that makes the row height or action relationship jitter unpredictably from one row to the next.

### Future Authoring

If authoring work eventually earns a surfaced workspace, it should use its own workspace structure.

Do not force future authoring tools to share Reader’s main layout just because both belong to the same app.
