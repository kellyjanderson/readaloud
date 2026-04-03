# Import Source Acquisition and Fingerprinting

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines how importer entrypoints acquire source content and derive stable source identity before normalization begins.

## Backlink

Parent specification:

- [Importer Normalization Contract](importer-normalization-contract.md)

## Scope

This specification covers:

- source byte or source text acquisition
- source type and source-locator capture
- canonical source fingerprint derivation
- early read failure behavior before parse

This specification does not define format-specific parsing.

## Behavior

### Supported Acquisition Modes

The importer entrypoint must support:

- direct text input from paste/share flows
- byte-based file import for supported file types

### Required Source Metadata

Before parse begins, the importer must derive or preserve:

- source type
- best available human title
- source locator when available
- canonical source fingerprint or equivalent stable source identity

### Fingerprint Rule

The canonical source fingerprint must be derived from the best available stable source identity for the import mode.

Examples:

- pasted/shared text may use normalized text content
- file imports may use file name plus content bytes
- archive-backed formats may still use the outer file identity rather than internal chapter paths

### Failure Rule

If source bytes or source text cannot be acquired:

- the importer must fail before parse
- the failure must surface as a structured import error rather than malformed normalized output

## Constraints

- source acquisition must remain lightweight enough for responsive file-open behavior
- source identity must not depend on voice, engine, or playback state
- acquisition must not silently substitute empty content for unreadable input

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Import begins from an explicit source-acquisition contract rather than ad hoc per-entrypoint behavior.
- Source type, locator, and stable identity exist before block or segment ids are assigned.
- Read failures are distinguishable from parse or normalization failures.
