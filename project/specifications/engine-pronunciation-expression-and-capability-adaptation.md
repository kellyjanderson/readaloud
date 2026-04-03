# Engine Pronunciation Expression and Capability Adaptation

Last updated: April 3, 2026
Status: Draft specification

## Overview

This specification defines the implementation branch for explicit engine capability modeling and adapter-boundary translation of app-owned pronunciation artifacts.

## Backlink

Parent architecture:

- [Engine Pronunciation Expression and Capability Adaptation](../architecture/engine-pronunciation-expression-and-capability-adaptation.md)

## Scope

This specification covers:

- engine capability representation
- engine-adapter translation boundary ownership
- engine-specific phoneme inventory adaptation where direct phoneme expression is supported
- the explicit separation between canonical app-owned artifacts and engine-native payload construction

This specification does not redefine chunk planning, pronunciation planning, or fallback traceability already covered by other specification branches.

## Refinement Status

This specification requires refinement.

## Child Specifications

- [Engine Capability Model](engine-capability-model.md)
- [Engine Adapter Translation Boundary](engine-adapter-translation-boundary.md)
- [Kokoro Phoneme Inventory Adaptation](kokoro-phoneme-inventory-adaptation.md)

## Acceptance

- The remaining implementation work unique to this architecture branch is represented by final leaf specifications.
- No unresolved adapter-boundary or capability-model work remains hidden only in architecture prose.
