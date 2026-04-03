# Synthesis Boundary Policy

Last updated: March 31, 2026
Status: Draft specification

## Overview

This specification defines how generated speech chunks are corrected and finalized at join boundaries before they are treated as playback-ready cached audio.

## Backlink

Parent architecture:

- [Playback Orchestration and Synthesis Boundaries](../architecture/playback-orchestration-and-synthesis-boundaries.md)

## Scope

This specification covers:

- boundary classes
- boundary candidate metadata
- trim-and-cap join behavior
- special handling for initial and resumed chunks
- finalized corrected-chunk reuse behavior

This specification does not define chunk planning itself.

## Behavior

The parent branch now delegates the detailed policy behavior to focused child specifications.

In particular:

- boundary taxonomy and required candidate metadata belong to their own leaf
- noninitial trim-and-cap correction belongs to its own leaf
- initial and resumed startup semantics belong to their own leaf
- corrected-chunk finalization and reuse belong to their own leaf

This parent specification keeps only the branch-level rule that chunk-boundary handling is centralized and must occur before chunks are treated as finalized playback-ready outputs.

## Constraints

- boundary policy runs before playback-ready cache write
- silence correction must remain deterministic for the same input chunk pair and boundary class
- chunk metadata must remain available for evaluation and debugging

## Refinement Status

This specification requires further refinement.

## Child Specifications

- [Boundary Candidate Metadata Contract](boundary-candidate-metadata-contract.md)
- [Boundary Silence Thresholds](boundary-silence-thresholds.md)
- [Trim-and-Cap Join Correction](trim-and-cap-join-correction.md)
- [Initial and Resumed Boundary Handling](initial-and-resumed-boundary-handling.md)
- [Boundary-Corrected Chunk Output and Reuse](boundary-corrected-chunk-output-and-reuse.md)

## Acceptance

- Noninitial joins can be corrected without re-synthesizing audio.
- The system distinguishes weak, sentence, paragraph, and section joins.
- Replay reuses corrected chunks rather than regenerating them.
- The player does not stack extra fixed gaps on top of finalized chunk audio.
- The remaining boundary-policy work is represented by final leaf specifications.
