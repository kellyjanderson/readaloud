# Import Structural Cleanup and Visible Content Preservation

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines the cleanup pass that removes non-content noise while preserving visible structure that matters for display and speech.

## Backlink

Parent specification:

- [Importer Normalization Contract](importer-normalization-contract.md)

## Scope

This specification covers:

- removal of hidden or irrelevant content
- preservation of visible structural elements
- media placeholder preservation
- unsupported visible structure handling

This specification does not define format-family reading-order rules.

## Behavior

### Cleanup Rule

The cleanup pass must remove or exclude:

- scripts
- styles
- hidden elements
- obvious parser noise
- navigation scaffolding that is not body content

### Preservation Rule

The cleanup pass must preserve visible structure when the source exposes it, including:

- headings
- paragraphs
- lists
- captions
- blockquotes
- tables
- media references
- explicit separators or page breaks when meaningful

### Media Rule

If media can be resolved:

- preserve it as a display asset or attachment reference

If media cannot be resolved:

- preserve the structural position where feasible
- emit diagnostics rather than silently dropping the issue

### Unsupported Visible Structure Rule

If visible source structure cannot be normalized into a richer supported block type:

- preserve it as an explicit unsupported or downgraded block when feasible
- emit an `unsupported_structure` diagnostic

## Constraints

- cleanup must not erase visible content only because it is awkward to normalize
- cleanup must not inject engine-specific speech markup
- cleanup decisions that lose user-visible structure must be diagnosable

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Import cleanup removes noise without flattening meaningful visible structure.
- Media and unsupported visible structure are handled explicitly instead of vanishing silently.
- Cleanup behavior is reusable across multiple source-format families.
