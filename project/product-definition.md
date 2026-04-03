# Read Aloud Product Definition

Last updated: March 29, 2026
Status: Active product definition

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
- audiobook publishing
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
- advanced annotation workflows
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
