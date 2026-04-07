# Internal Document Serialization Format

Status: final

## Overview

This specification defines the first project-owned on-disk format for serialized Read Aloud internal documents.

Issue anchor:

- GitHub issue `#21`

## Backlink

Parent architecture:

- [Document and Speech Pipeline](../architecture/document-speech-pipeline.md)

## Scope

This specification covers:

- a project-specific file type for serialized internal documents
- first-version encoding and readability expectations
- versioned storage of normalized document, attribution, and related sidecar data for testing and verification

## Behavior

The app must be able to serialize its internal imported document representation to a project-owned file format for testing and verification.

The first shipped version of that format should be:

- human-readable
- UTF-8 JSON
- versioned by an explicit envelope field
- stored under a project-specific extension

The preferred first extension is:

- `.radoc`

The file contents should remain JSON even though the extension is project-specific, so the format is easy to inspect, diff, and discuss during early development.

The serialized envelope should be able to carry at least:

- document identity and source metadata
- normalized display and speech structures
- speech annotations
- dialogue attribution
- cast registry
- document-owned voice attribution

## Constraints

- the serialized format must be stable enough for test fixtures and debugging workflows
- the first version should optimize for inspectability over compactness
- later binary or hybrid packaging must not block the first readable version

## Acceptance

- the app has a project-specific serialized internal document file format
- the first version is human-readable and versioned
- the format can carry the internal structures needed to inspect normalization and voice attribution decisions
