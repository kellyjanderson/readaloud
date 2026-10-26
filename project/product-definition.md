# Read Aloud Product Definition

Last updated: October 25, 2026
Status: Standing product requirements; current implementation does not yet meet all requirements

## Mandatory Reading Experience

With the intended document available and Play requested promptly, the user must hear smooth, uninterrupted speech within **two seconds of opening the app, regardless of document size**. Measure opening-to-audible-output, including initialization and preparation. Record Play separately; do not autoplay to satisfy timing. For documents opened after launch, also measure document-open-to-audio. Human delay, missing inputs/assets and access failures must be reported honestly rather than disguised as successful latency results. Cold-process, warm-process and reusable-document runs require separate evidence; document size is not an exemption.

The interface must always feel responsive: scrolling, menus, voice selection, pause/cancel and document replacement must remain usable during preparation, inference, persistence and export. A pending Play must be visible and cancellable immediately at the intent level even if native work takes longer to drain. Old requests must never start unexpected speech. Smooth speech means sustained playback without starvation, missing or duplicated words, or unintended replay; authored pauses are preserved.

**All work involved in reading text is dynamic and incremental.** This includes source acquisition where supported, parsing, normalization, display and speech mapping, semantic analysis, pronunciation and delivery planning, voice/resource binding, synthesis, buffering and persistence. Character discovery is one example, not a separate exception. Prepare only the bounded material needed to begin, continue ahead of playback, prioritize the current listening position and invalidate only affected work. Whole-book parsing, analysis, cast completion, serialization or cache validation must not become a hidden first-audio gate. Format-specific acquisition constraints must be exposed and addressed, not silently used to relax the experience requirement.

Characters and other derived knowledge evolve as content is encountered. Keep stable content identities and positions, provenance and uncertainty; retain explicit user choices when new evidence arrives. Late discoveries must not silently rewrite already-spoken material or override newer playback intent. A jump prioritizes the new position rather than waiting for all preceding background work.

Every operation exceeding one or two seconds must show a dynamic progress bar driven by actual completed work. Show the operation/stage, completed units and honest totals; disclose unknown or expanding totals. Distinguish work, waiting, stalled/failed and completed states. Do not invent percentages, leave the only feedback motionless without explanation, or show 100% while required downstream work is still pending. Progress does not excuse UI blocking or replace the two-second startup requirement.

These are user requirements, not proof of present capability. The source-linked [issue #83 report](https://github.com/kellyjanderson/readaloud/issues/83) owns active findings and acceptance work. Current architecture remains the authority for implemented behavior. Current-release scope remains with its existing coordinator.

## Prepared Documents and Voice-Directed Publishing

`.radoc` is the reusable prepared-document format. After processing input, the app automatically writes the processed result so a second run does not repeat valid preparation. Processing and persistence must cooperate incrementally for long documents, with safe checkpoints, explicit completeness and atomic publication/recovery. Preserve the source; never treat an interrupted write as complete. Version and dependency validation must distinguish reusable results from stale ones and recompute only invalid portions without introducing a whole-document startup barrier.

The format must preserve stable content/position anchors, derived analysis and its provenance, character identities and user choices, plus annotations for inflection and other speech directions. Canonical direction belongs to the document, independently of voice packages, engine capabilities or generated audio. Unsupported directions must survive loading/saving and engine fallback without being discarded or falsely claimed as realized.

The long-term goal is a publishing tool and portable document format through which books can be published with voice direction. Published content must not depend on local absolute paths, process handles or private cache state. Versioned interchange, authoring and direction fidelity require explicit design and acceptance; this declaration does not claim a complete publishing tool exists today. A data-only codec round trip is not proof of application reopen, second-run acceleration or usable annotation authoring.

## Product Summary

`Read Aloud` is a document-reading app that lets people open, share, or paste real-world text and have it read aloud in a voice they actually want to listen to.

The product should feel calm, dependable, and personal. It is not a document management platform, a collaboration tool, or a cloud library. It is a reading companion built around high-quality listening.

## Product Promise

`Read Aloud` should let a person:

- bring a document into the app with very little friction
- start listening quickly
- stay oriented in the document while listening
- choose a voice that feels good enough to use regularly
- move between desktop and mobile without learning a different product on each platform

## Who The Product Is For

The product is for people who:

- want documents read aloud instead of reading them visually all the time
- listen to articles, PDFs, ebooks, notes, reports, or drafts
- care about voice quality and smooth playback
- want a tool that feels private and local-first

The product is not primarily for:

- team collaboration
- shared cloud libraries
- a complete audiobook publishing workflow in the current release; voice-directed publishing through `.radoc` is a long-term goal
- full document editing workflows

## Core User Jobs

Users should be able to:

- send a document to `Read Aloud` from wherever they already are
- open a document directly in the app
- paste text directly into the app
- listen with simple, trustworthy controls
- adjust the voice and speed to match their preference
- save spoken output as an audio file when they want a durable listening result
- come back to the document view and remain oriented

## Platform Expectations

`Read Aloud` is one product across:

- desktop platforms supported by Flutter
- iPhone
- Android

The core product should feel consistent across platforms, even when platform-specific file opening or sharing flows differ.

## Core Experience

### Getting Content Into The App

The product must support:

- opening supported document files
- receiving shared documents or text from other apps
- opening a new document while the app is already running
- pasting text directly into the app

Paste should work up to the practical maximum allowed by the platform.

The app should request file access only when needed and should rely on the operating system’s normal permission and document-picking flows.

### Reading Surface

The reading surface must be scrollable and must present the document as a document, not as a plain text dump.

Users should expect the app to display:

- styled text
- headings and paragraphs
- images
- tables when practical
- embedded or attached media context when present

The reading surface should help the user stay visually oriented while listening, even when media is not itself being spoken.

### Voice Experience

Voice quality is central to the product.

Users should be able to:

- choose a preferred voice
- expect that voice choice to matter to the experience
- expect speed to be remembered per voice

The product should favor local, high-quality playback whenever possible. The user should not be required to perform manual runtime setup for speech before the app becomes useful.

For `v1`, the product is English-first. Languages beyond English are explicitly a possible future release area, not a current product promise.

### Playback Experience

The transport must remain simple and predictable.

Core controls:

- play
- pause
- jump backward 30 seconds
- jump forward 30 seconds
- speed control
- sleep timer

Product behavior expectations:

- there is no stop button
- if playback reaches the end, the user remains at the end until they press play again
- pressing play at the end starts the document over
- sleep timer expiry should fade playback out rather than cut off abruptly

### Playback Feel

Users should experience playback as responsive and uninterrupted.

This means:

- starting playback should feel quick
- controls should remain responsive while speech is being prepared
- the app should not feel like it is freezing while the user listens
- previously prepared audio should not feel like it is being pointlessly regenerated

### Export and Automation

The product should support saving spoken output as audio.

Users should expect:

- export to reflect the voice and speed they selected
- export to use the same speech quality path as playback
- desktop builds to support useful command-line invocation for opening files and running exports without the normal UI when desired

## Supported Content

`Read Aloud` should support common reading inputs including:

- plain text
- markdown
- HTML
- PDF
- EPUB
- DOCX
- RTF

The product goal is not perfect fidelity to every source format. The goal is a useful reading and listening experience for real documents.

## Product Boundaries For v1

`Read Aloud v1` does include:

- document intake from open, share, and paste flows
- a rich reading surface
- voice selection
- per-voice speed
- audio export
- play and pause
- 30-second jump controls
- a fading sleep timer

`Read Aloud v1` does not include:

- its own iCloud document library
- built-in cloud sync
- collaborative features
- advanced annotation authoring workflows in the current release; preserving direction in `.radoc` and future authoring remain product goals
- deep semantic document metadata features
- a product promise of non-English local TTS support
- a destructive stop action in playback

## Quality Bar

For the product to feel ready, users should be able to trust that:

- opening a document is straightforward
- the document view remains understandable
- playback starts without confusing setup steps
- voice choice and speed changes behave predictably
- the product behaves more like a real reading tool than a prototype

## Success Criteria For The Product

`Read Aloud` is succeeding at the product level when a user can:

- get a document into the app without friction
- choose a voice they like
- listen comfortably for extended periods
- move around the document with confidence
- trust the app to behave consistently across ordinary reading sessions

## Questions To Drive Product ↔ Research

The next research cycle should help answer questions such as:

- what document behaviors users most expect when opening PDFs and EPUBs
- what reading apps do well for orientation, chapter movement, and media context
- what voice library expectations users will reasonably have at first release
- what sleep timer and playback behaviors feel standard versus surprising
- what accessibility expectations should shape the reading surface and controls
