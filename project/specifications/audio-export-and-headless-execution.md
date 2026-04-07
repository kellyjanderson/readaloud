# Audio Export and Headless Execution

Last updated: April 3, 2026
Status: Draft specification

## Overview

This specification refines the product-facing audio export and headless execution architecture into implementable units.

## Backlink

Parent architecture:

- [Audio Export and Headless Execution](../architecture/audio-export-and-headless-execution.md)

## Scope

This specification covers:

- exported audio assembly
- in-app export behavior
- command-line launch handling
- headless export execution
- automation-oriented speech QA tooling that reuses the shared export/runtime path

## Behavior

The implementation must support:

- saving spoken audio from the interactive app
- passing files to the app on startup
- selecting a headless launch mode from command-line parameters
- exporting one or more files without launching the UI in headless mode
- running pronunciation and sentence-probe harnesses without creating a second synthesis implementation

## Constraints

- export must reuse the same normalized document and speech pipeline as playback
- headless mode must not create a separate importer or synthesis behavior
- output must remain useful both as a user feature and as a speech-debugging tool

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Audio Export Assembly](audio-export-assembly.md)
- [Command-Line Mode Selection](command-line-mode-selection.md)
- [Headless Synthesis Session](headless-synthesis-session.md)
- [In-App Audio Export Workflow](in-app-audio-export-workflow.md)
- [Speech QA Debug Tooling](speech-qa-debug-tooling.md)

## Acceptance

- audio export and headless execution behavior are fully covered by final child specifications
