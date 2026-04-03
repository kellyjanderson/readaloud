# Headless Synthesis Session

Last updated: April 3, 2026
Status: Final specification

## Overview

This specification defines how the app imports files and exports spoken audio in ordinary file-driven headless export mode.

## Backlink

Parent specification:

- [Audio Export and Headless Execution](audio-export-and-headless-execution.md)

## Scope

This specification covers:

- headless session startup
- file import behavior
- voice and rate selection
- sequential export behavior
- console reporting and exit status

This specification does not define pronunciation-probe or sentence-probe QA harness modes.

## Behavior

### Session Model

A headless invocation represents one export session.

The session may process:

- one input file
- multiple input files sequentially

### Import Rule

Each headless input file must be imported through the same document importer used by the interactive app.

### Voice Rule

Voice selection for headless mode follows this order:

1. explicit `--voice`
2. saved preferred voice when available
3. default installed voice

If the requested voice is unavailable, the session must fail clearly.

### Rate Rule

Rate selection for headless mode follows this order:

1. explicit `--speed`
2. saved per-voice speed when available
3. `1.0`

### Export Rule

For each input file, the session must:

1. import and normalize the document
2. fail early if no readable speech text is available
3. build the same speech planning inputs used for playback
4. export finalized audio to the resolved output path
5. print a concise success line including source path and output path

### Sequential Processing Rule

When multiple files are provided:

- they are processed one at a time
- one file failure does not prevent later files from being attempted
- the final process result summarizes successes and failures

### Exit Status Rule

- exit `0` when all requested files export successfully
- exit `1` when any requested file fails
- exit `2` for command-line validation errors before export begins

### Console Reporting Rule

The headless session must print concise structured progress, including:

- selected mode
- file being processed
- success output path
- failure reason
- final summary

## Constraints

- headless mode must not launch the normal reader UI
- headless mode must use the same importer and export pipeline as the app
- headless processing may remain sequential in `v1`

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- one or more input files can be exported without launching the UI
- voice and speed selection match the app’s product behavior
- exit status distinguishes success, export failure, and argument-validation failure
