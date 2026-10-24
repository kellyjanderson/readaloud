# Character Cast Registry Model

## Architecture ownership

- [character dialogue attribution and voice casting](../architecture/character-dialogue-attribution-and-voice-casting.md)
- [speech enrichment and narration](../architecture/speech-enrichment-and-narration.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the active ACD/plan.

Status: final target contract; October 24, 2026 additions pending implementation verification

## Overview

This specification defines the stable document-scoped cast model used for narrator and character identity.

## Backlink

Historical specification lineage:

- [Character Cast Registry and Voice Assignment](../archive/specification-ancestors/character-cast-registry-and-voice-assignment.md)

## Scope

This specification covers:

- narrator entry requirements
- character entry requirements
- cast ids
- display labels and supporting evidence

## Behavior

The system must maintain a cast registry that includes:

- one explicit narrator entry
- zero or more detected character entries

Each cast entry must preserve:

- a stable document-scoped cast id
- a role kind such as narrator or character
- a display label
- supporting confidence and provenance

Character entries may also preserve:

- observed aliases
- attribution evidence
- optional gender identity extraction output
- optional pronoun profile output
- supporting evidence spans
- conflict state when identity evidence cannot be resolved cleanly

Gender identity, pronouns, and descriptors must remain separate concepts in the stored cast model rather than one collapsed inferred-gender field.

Cast ids must remain stable within one normalized document version.

## Prepared Voice Binding

Before playback, every character and the narrator must resolve a typed voice binding containing automatic assignment, optional user override, effective voice id, voice-asset digest, model-manifest identity/digest, engine compatibility, pronunciation-profile identity and binding revision. Shared manifests are referenced rather than duplicated. The character retains supported presented-gender evidence, pronouns, descriptors and uncertainty independently of voice choice.

The document runtime loads the required voice resources before audio starts and keeps them resident through ordinary character changes until document completion/replacement. Native handles and cached audio are runtime-owned; character records serialize identity and binding references only. Span-level delivery and pronunciation remain on the instrumented document, optionally inheriting character defaults. See [Document Preparation and Execution Contexts](../acd/prepared-document-runtime.acd).

## Constraints

- narrator is a first-class cast entry, not null
- character identity evidence and voice assignment provenance remain separate typed fields; the character aggregate owns or references its document voice binding
- cast identity must remain traceable to document-time attribution results

## Acceptance

- the app can represent narrator and characters in one stable registry
- cast identity remains stable within one normalized document version
- voice assignment can resolve against cast ids without redoing attribution work
- the registry has room for document-owned identity evidence without forcing casting to guess from names alone
