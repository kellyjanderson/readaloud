# Lossy Extracted Text Normalization

Last updated: April 1, 2026
Status: Draft specification

## Overview

This specification defines the lossy extracted-text normalization branch.

## Backlink

Parent specification:

- [Importer Normalization Contract](importer-normalization-contract.md)

## Scope

This specification covers normalization behavior for:

- plain text
- pasted/shared text
- PDF extracted text
- RTF flattened text

This specification does not redefine the lower-level line-wrap recovery heuristics already covered elsewhere.

## Behavior

The lossy extracted-text branch must define:

- common heuristic-grouping behavior for extracted-text families
- plain-text and pasted-text normalization rules
- PDF extracted-text normalization rules
- flattened RTF normalization rules

## Constraints

- lossy extracted-text normalization must never pretend high structural confidence when the importer is using heuristics
- heuristic grouping decisions must be diagnosable
- flattened text recovery must still converge on canonical display, speech, and position outputs

## Refinement Status

This specification requires further refinement.

## Child Specifications

- [Lossy Text Common Heuristic Grouping](lossy-text-common-heuristic-grouping.md)
- [Plain and Shared Text Normalization](plain-and-shared-text-normalization.md)
- [PDF Extracted Text Normalization](pdf-extracted-text-normalization.md)
- [RTF Flattened Text Normalization](rtf-flattened-text-normalization.md)

## Acceptance

- Lossy extracted-text normalization work is fully represented by focused child specifications.
- No oversized common, plain/shared, PDF, or RTF normalization work remains hidden in one leaf.
