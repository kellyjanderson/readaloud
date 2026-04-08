# UI Definitions

This folder is the durable source of truth for `Read Aloud` interface structure and interaction semantics.

UI definitions are the visible-behavior analog to system architecture.

They define:

- the product voice and brand choices used by the interface
- the visual system and concrete design tokens
- the reusable component families that shape implementation
- what belongs on the primary interface
- how complexity is layered
- what control states mean
- how status is communicated
- how theming and appearance modes work
- where advanced features should live

## Current Documents

- [Brand Guide](brand-guide.md)
- [Design Guide](design-guide.md)
- [Component System](component-system.md)
- [UI System Overview](ui-system-overview.md)
- [Platform Navigation And Menu Segmentation](platform-navigation-and-menu-segmentation.md)
- [Primary Surface and Complexity Layering](primary-surface-and-complexity-layering.md)
- [Control State Semantics](control-state-semantics.md)
- [Voice Library and Cast Management](voice-library-and-cast-management.md)
- [Follow-Along Reading Surface](follow-along-reading-surface.md)
- [Reader Options and Secondary Settings](reader-options-and-secondary-settings.md)
- [Theme and Appearance Modes](theme-and-appearance-modes.md)
- [Live Input and File Menu Behavior](live-input-and-file-menu-behavior.md)

## Relationship To Other Project Docs

- `product-definition.md` defines what the product is for
- `ui/` defines how the interface should behave and feel
- `architecture/` defines invisible system structure
- `specifications/` define narrower implementable contracts

UI definitions should stay durable and coherent across multiple implementation rounds.

The preferred internal order is:

1. brand and voice rules
2. design guide
3. component system
4. surface-specific UI definitions
5. UI specifications
