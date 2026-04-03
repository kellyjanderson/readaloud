# Import Failure and Partial Success Semantics

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines how importer failure, degraded success, and partial success are represented.

## Backlink

Parent specification:

- [Importer Normalization Contract](importer-normalization-contract.md)

## Scope

This specification covers:

- fatal import failures
- degraded but usable normalization results
- partial success with warnings
- unsupported-format handling

This specification does not redefine individual diagnostic codes.

## Behavior

### Fatal Failure Rule

A fatal import failure occurs when the importer cannot safely produce a valid normalized result.

Examples:

- unreadable source
- unrecoverable parse failure
- missing required package/container metadata

Fatal failures must:

- stop normalization
- surface a structured error to the caller
- avoid emitting malformed normalized documents

### Partial Success Rule

An importer may return a usable normalized result with warnings when:

- content was recovered but with lossy conversion
- some assets are missing
- ordering or paragraph grouping is heuristic
- unsupported structures were downgraded but body text is still usable

### Unsupported Format Rule

If a format or source family is unsupported:

- the result must remain explicit about that unsupported status
- the user-facing flow must not misrepresent the output as a faithful import
- the unsupported condition must remain diagnosable

### Degraded Success Rule

If the importer produces a normalized result after fallback behavior:

- diagnostics must explain the degradation
- downstream layers may continue using the normalized result
- callers must be able to distinguish degraded success from clean success

## Constraints

- fatal failure and degraded success must remain distinct states
- import failure semantics must not depend on the active speech engine
- importer recovery must not silently convert fatal corruption into empty but “successful” normalized output

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Import failure, partial success, degraded success, and unsupported-format outcomes are explicitly distinguished.
- Downstream layers can trust that any successful normalized result is structurally valid even when diagnostics report lossiness.
- Callers can present importer problems without guessing from malformed output.
