# English Suffix Allomorph Module

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines the English suffix-allomorph rule module used for productive `s`-class endings.

## Backlink

Parent specification:

- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)

## Scope

This specification covers:

- plural-like `s`-class endings
- possessive `’s`
- future compatibility with third-person singular present `-s`

This specification does not define contraction handling.

## Behavior

### Supported Surface Classes

The first implementation round must support:

- noun possessive `’s`
- noun plural-like `-s` class behavior when the planner uses the same productive rule family

### Allomorph Rule

The module must select among:

- `/s/`
- `/z/`
- `/ɪz/` or `/əz/`

using:

- sibilant avoidance
- voicing agreement

### Default Rule

When the ending is neither sibilant nor clearly voiceless, the default allomorph is the voiced `/z/` class.

### Contraction Exclusion Rule

Tokens that are contractions rather than noun possessives must not be rewritten by this module.

## Constraints

- this module must operate structurally rather than through per-name hard-coding
- this module must remain profile-aware so future English variants can tune behavior if needed

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The system has one reusable suffix-allomorph module for English `s`-class endings.
- Possessive handling no longer depends on per-name rules.
- Contractions remain separate from productive noun-possessive behavior.

