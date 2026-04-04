# UI Definition Guidance

UI definitions are the visible-behavior analog to system architecture.

They define the durable structure of the interface and interaction model without dropping immediately into implementation detail.

---

## Purpose

UI definitions exist to describe:

* what interface surfaces exist
* which controls are primary
* how complexity is layered
* what interaction states mean
* how status is communicated
* how appearance modes and navigation patterns should work

They should capture durable design intent, not transient implementation detail.

---

## When To Use UI Definitions

Use UI definitions when the question is primarily about visible behavior, interaction structure, or interface semantics.

Examples:

* top-level vs secondary controls
* where advanced features should live
* what a disabled-but-communicating control should look like
* how themes and appearance modes should work
* how a live mode should behave from the user's perspective
* what persistent affordances should exist across screens

If the problem is about system structure, use architecture.

If the problem is about exact implementation rules, thresholds, or acceptance criteria, use specifications.

---

## Recommended Structure

UI definition documents should generally include:

### Overview

A short description of the interface area or UI concept.

### Primary Interface Elements

What should be visible and dominant on the primary surface.

### Secondary Access

How advanced or less frequent actions are accessed without cluttering the main interface.

### States And Semantics

The meaning of visible states, control conditions, and status communication.

### Appearance And Accessibility

Theme behavior, contrast requirements, and other durable visual rules.

### Related Specifications

References to narrower specifications that implement parts of the UI definition.

---

## Relationship To Architecture

Architecture defines invisible system structure.

UI definitions define visible interaction structure.

Both sit above specifications and should stabilize before detailed implementation work begins in their area.

Specifications should refine a coherent UI definition rather than inventing interface behavior ad hoc during implementation.

---

## Stability

UI definitions should change less often than implementation-level specifications.

They are intended to preserve coherent interface behavior across multiple implementation rounds.
