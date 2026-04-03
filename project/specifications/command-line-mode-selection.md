# Command-Line Mode Selection

Last updated: April 3, 2026
Status: Final specification

## Overview

This specification defines how startup arguments choose between normal UI mode and the supported headless automation modes.

## Backlink

Parent specification:

- [Audio Export and Headless Execution](audio-export-and-headless-execution.md)

## Scope

This specification covers:

- supported command-line options
- mode-selection rules
- input file argument handling
- validation errors and help output

## Behavior

### Supported Options

The initial command-line interface must support:

- `--headless`
- `--voice=<voiceId>`
- `--speed=<multiplier>`
- `--output=<path>`
- `--output-dir=<path>`
- `--probe-file=<path>`
- `--probe-text=<phrase>` repeatable
- `--compare-dir=<path>`
- `--sentence-probe-file=<path>`
- `--help`

Positional arguments are interpreted as input file paths.

### Default Mode Rule

If none of the headless or probe mode selectors are present, the app launches in normal UI mode.

### UI Mode File Rule

If UI mode receives one or more positional input files:

- the app must preload the first supported file into the reader
- additional files may be ignored in `v1`
- the ignored-file condition should be surfaced as a nonfatal status message when practical

### Headless Mode Rule

If `--headless` is present:

- the app must not launch the normal reader UI
- positional input files are required

### Pronunciation Probe Mode Rule

If `--probe-file` or one or more `--probe-text` values are present:

- the app must enter headless pronunciation-probe mode even if `--headless` is absent
- positional input files are not allowed
- `--output` is not allowed
- `--output-dir` may be used to choose the probe-run directory
- `--compare-dir` may be used only in pronunciation-probe mode

### Sentence Probe Mode Rule

If `--sentence-probe-file` is present:

- the app must enter headless sentence-probe mode even if `--headless` is absent
- positional input files are not allowed
- `--output` is not allowed
- `--output-dir` may be used to choose the run directory

### Output Validation Rule

- `--output` may be used only when exactly one input file is supplied
- `--output-dir` may be used with one or more input files
- if neither `--output` nor `--output-dir` is supplied in headless mode, default export paths must be derived per input file

### Speed Validation Rule

`--speed` must parse as a floating-point value and be clamped to the same supported range as interactive voice speed.

### Help Rule

If `--help` is present:

- the app must print usage information
- no UI or headless export session is started

### Validation Failure Rule

If command-line options are invalid, the app must:

- print a concise error
- print usage guidance
- exit without launching the UI

### Mutual-Exclusion Rule

- `--probe-file` and `--probe-text` must not be combined
- sentence-probe mode must not be combined with phrase-probe mode
- ordinary headless export positional inputs must not be combined with either probe mode

## Constraints

- command-line parsing must not create a second source of truth for supported voice-rate behavior
- mode selection must happen before the normal UI is launched
- desktop command-line support must not break web or mobile compilation

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- the app can start in UI, headless export, pronunciation-probe, or sentence-probe mode from startup arguments
- UI mode can preload a passed file
- invalid command combinations fail clearly before app launch
