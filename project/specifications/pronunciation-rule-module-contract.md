# Pronunciation Rule Module Contract

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines the contract for productive pronunciation rule modules.

## Backlink

Parent specification:

- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)

## Scope

This specification covers:

- required module inputs
- required module outputs
- execution ordering
- conflict behavior

This specification does not define any one specific English rule module.

## Behavior

### Required Input

A pronunciation rule module must be able to consume:

- normalized segment text
- token or token-range information
- the selected English pronunciation profile
- currently merged pronunciation resources
- local neighboring-token context

### Required Output

A pronunciation rule module must emit one of:

- no decision
- a resolved pronunciation candidate or artifact decision
- an unresolved diagnostic decision

### Ordering Rule

The first implementation round must support an explicit stable module order per profile.

### Conflict Rule

If multiple modules target the same token range, the higher-priority module in the ordered module list wins unless a higher-layer user override already exists.

## Constraints

- modules must not directly call the speech runtime
- modules must not emit engine-native commands
- module execution must be deterministic for the same inputs

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The system has a reusable contract for productive pronunciation rule modules.
- Module ordering and conflict behavior are explicit.
- Rule modules can be enabled or disabled by profile without changing the rest of the pipeline.

