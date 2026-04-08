# App Shell And Platform Navigation UI

Status: draft

## Overview

This specification refines app-shell command access and platform-specific navigation structure into implementable UI leaves.

## Backlink

Parent UI definition:

- [Platform Navigation And Menu Segmentation](../ui/platform-navigation-and-menu-segmentation.md)

## Scope

This specification covers:

- platform-specific command-surface rules for desktop and mobile
- desktop use of native menu-bar structure for Reader-shell global commands
- mobile retention of the three-dots overflow menu
- grouped command presentation inside the mobile overflow menu
- keeping unimplemented authoring work out of the current Reader shell
- desktop app-title chrome minimization

## Behavior

The parent UI branch now delegates detailed implementation to child specifications.

In particular:

- the desktop-versus-mobile command-surface split belongs to one leaf
- the mobile overflow-menu grouping rule belongs to one leaf
- the Reader-only shell rule belongs to one leaf
- desktop title-chrome minimization belongs to one leaf

This parent specification keeps only the branch-level contract that app-shell command access is platform-specific and must not drift into a confusing hybrid navigation model.

## Constraints

- desktop command access must respect native macOS menu-bar expectations
- mobile command access may use an overflow pattern where no desktop menu bar exists
- app-shell navigation must remain secondary to the reading surface rather than competing with it

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Desktop Native Menu And Mobile Overflow Navigation](desktop-native-menu-and-mobile-overflow-navigation.md)
- [Mobile Overflow Menu Domain Grouping](mobile-overflow-menu-domain-grouping.md)
- [Desktop Reader Title Chrome Minimization](desktop-reader-title-chrome-minimization.md)
- [Reader-Only App Shell Until Authoring Exists](studio-workspace-entry-and-reader-isolation.md)

## Acceptance

- the current app-shell navigation branch is fully represented by final leaf specifications
- later navigation work can extend this branch without re-deciding the basic desktop-versus-mobile split ad hoc
