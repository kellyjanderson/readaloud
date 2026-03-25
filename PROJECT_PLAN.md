# Read Aloud Project Plan

Last updated: March 24, 2026
Status: Draft for review

## Product Summary

`Read Aloud` is a Dart/Flutter app for all platforms supported by Flutter that opens documents and
reads them aloud. The current priority is the basic product, not long-range metadata or standards
work. The `v1.0.0` release target is a simple, solid reader with document intake, a rich
scrollable reading surface, voice selection, and reliable playback controls.

## Current Product Direction

### Required Platforms

- all targets supported by Flutter

### Required Input Paths

- open a document directly in the app
- open a document while the app is already running
- share a document or text into the app
- paste text directly into the app

### Required Document Types

Initial plan:

- plain text
- PDF
- EPUB
- additional text-oriented formats later if they fit the same import pipeline

### Required Reader Features

- scrollable reading view
- voice selection
- play
- pause
- jump back 30 seconds
- jump forward 30 seconds
- speed control
- sleep timer

## Scope Clarifications

### What v1.0 Is

- a feature-complete reading app
- focused on intake, display, and playback
- one Flutter codebase across supported Flutter targets

### What v1.0 Is Not

- not the Kokoro voice sampler prototype
- not an iCloud-backed storage product
- not an embeddings-heavy or semantic-analysis product
- not a plain-text-only architecture that will need to be replaced later

## Priority Change

Standards-heavy metadata design is now deferred. The app should avoid throwing useful structure away,
but deep metadata work is not on the critical path for the initial product.

For now, the plan should optimize for:

- opening real documents
- rendering them in a future-proof way
- reading them aloud well
- preserving enough structure to avoid re-architecture later

## Rendering Strategy

The reading surface should not be built around a plain `Text` widget or a plain-string-only model.
The display layer needs to support:

- variable fonts and styling
- images
- video
- audio
- embedded or attached content
- future richer annotations or semantic overlays

### Recommended Direction

Use a normalized rich-document representation and render it through a rich-capable surface rather
than a plain-text control.

Working recommendation:

- import each source format into a normalized internal document model
- store a rich-content representation for display
- keep extracted reading text available for TTS and navigation

The rendering surface should be chosen so it can handle rich content now and future structured
content later. Based on current Flutter ecosystem support, that points toward an HTML/webview-style
document surface or another rich document renderer, not a plain text widget.

## Architecture Direction

### App Stack

- Flutter app at repository root
- shared Dart application layer
- platform integrations for file-open, share-in, and local storage

### Major Subsystems

- document intake
- document normalization/import
- rich document rendering
- TTS engine abstraction
- playback controller
- sleep timer
- session state and resume position

## Document Model Direction

The app should separate:

- source file format
- display representation
- extracted speakable text
- playback position model

That separation is important because:

- PDFs and EPUBs need different import logic
- the display surface should support rich content
- the TTS pipeline wants normalized readable text
- jump and resume behavior need stable offsets independent of the source parser

## TTS Direction

### Goal

Prefer a local programming-level integration for Kokoro instead of treating it as a local web
service dependency.

### Current Research Result

Kokoro does support programmatic inference APIs today:

- the official `kokoro` Python package exposes `KPipeline`
- `kokoro-onnx` exposes a local ONNX-based API

That means the product does not need to be built around an HTTP server just to use Kokoro.

### Recommended Direction

For the Flutter app, target an embedded/native inference path rather than a localhost web service:

- ONNX Runtime integration in Flutter is available
- Kokoro ONNX models are a plausible path for direct in-app use

Working assumption:

- use a TTS abstraction from day one
- keep Kokoro as a local-engine target
- treat any HTTP wrapper as a prototype tool only

## Playback Model

### Required Controls

- play
- pause
- jump back 30 seconds
- jump forward 30 seconds
- speed control
- sleep timer

### Jump Behavior Requirement

While reading, the app should track observed playback timing and use it to map words to elapsed
time. The goal is to support practical 30-second jumps even when playback is generated from text
rather than from a preauthored audiobook timeline.

### Working Timing Strategy

For each spoken segment, record:

- voice
- speed
- source text range
- word count
- produced audio duration

From that, derive a rolling words-to-seconds estimate for the current session. Jump controls can use
that estimate to choose the next text position when seeking backward or forward.

This does not require precise word-level highlighting in `v1.0.0`, but it does require a timing
model that is better than raw guesswork.

### Speed and Sleep Behavior

- reading speed is remembered per voice
- when the sleep timer expires, playback should fade out rather than stop abruptly

## v1.0 Functional Scope

### In Scope

- Flutter app scaffold for all Flutter-supported targets
- open/share/paste intake flows
- PDF and EPUB intake
- rich scrollable reader view
- voice selection
- play/pause
- 30-second jump controls
- speed control
- sleep timer
- local session timing model for jump estimation

### Explicitly Deferred

- advanced metadata modeling
- chapter/illustration UX standards work
- embeddings
- cloud sync and document library product features
- shipping the Kokoro sampler as the real app

## Format Strategy

### EPUB

EPUB is naturally rich and should flow into the normalized reader model with styling and embedded
resources preserved where practical.

### PDF

PDF support is required, but PDF should be treated as an ingestion problem, not as a reason to make
the entire app PDF-native. The app needs a reading model that can still support rich display and TTS
behavior after import.

### Plain Text and Paste

These should enter the same core pipeline, just with simpler import logic.

## Implementation Phases

### Phase 1: Foundation

- create Flutter project in repository root
- set up all Flutter-supported targets
- define app shell and state model
- define TTS abstraction
- define normalized document model

### Phase 2: Intake

- paste text flow
- open-file flow
- receive shared content flow
- file type detection and importer routing

### Phase 3: Reader Surface

- rich scrollable reading surface
- future-proof display control selection
- basic typography controls
- embedded content support path

### Phase 4: Playback

- voice selection with per-voice speed memory
- play/pause
- speed control
- sleep timer with fade-out behavior
- timing capture for words-to-seconds estimates
- jump back/forward 30 seconds

### Phase 5: Format Support

- EPUB import path
- PDF import path
- consistency work across platforms

## Key Design Constraints

- do not choose a display control that locks the app into plain text
- do not hardwire the product to an HTTP-only TTS architecture
- do not make metadata design a blocker for the first implementation
- do preserve enough structure internally to avoid major rework later

## Open Questions

No blocking product questions are recorded in this revision. The prior questions about targets,
stop behavior, speed scope, and sleep timer behavior have been answered:

- target platforms are all platforms supported by Flutter
- there is no stop button in the product scope
- speed is remembered per voice
- sleep timer expires with a fade-out

## Definition of Done for v1.0.0

`Read Aloud v1.0.0` is ready only when:

- the app runs on the Flutter-supported targets in scope
- a user can open or share in a supported document
- a user can paste text directly
- the document displays in a scrollable rich-capable reader surface
- the user can choose a voice
- the user can play, pause, jump back 30 seconds, and jump forward 30 seconds
- the user can change speed and that speed is remembered per voice
- the user can use a sleep timer that fades playback out
- the jump buttons use observed timing data instead of a fixed blind estimate
- the app is not architecturally locked to plain text or a localhost web-service TTS dependency

## Immediate Next Step

Finalize this plan, then scaffold the Flutter project at the repository root with the document
model, TTS abstraction, and reader-surface choice treated as the first architectural decisions.
