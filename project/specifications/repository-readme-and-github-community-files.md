# Repository Readme And GitHub Community Files

Status: final

## Purpose

Define the required repository-facing onboarding and community-health files that make the project understandable and operable from the GitHub surface.

## Requirements

The repository must include a root `README.md` that:

- explains what `Read Aloud` is
- states current release or beta status
- states current platform validation status
- documents local setup and build entrypoints
- explains the external Kokoro model dependency and required local file path
- links to project architecture, specification, planning, and research docs
- links to contribution and community guidance

The repository must include contributor-facing community files:

- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `SECURITY.md`
- `SUPPORT.md`

The repository must include GitHub workflow surface files:

- issue templates for bugs and feature requests
- a pull request template

## Branch And Workflow Alignment

Contributor guidance must reflect the repository branch policy:

- bug-fix work is issue-linked
- feature work is specification-linked
- implementation work should not proceed directly on `main`
- pull requests are required even when formal review is not

## External Model Dependency

Because the Kokoro ONNX model is treated as an external dependency rather than a normal checked-in source asset, the repository must include durable setup guidance describing:

- the required filename
- the required local path
- that the model should not be committed to normal git history
- trusted or intended upstream source locations

## Visibility Goal

A new collaborator landing on the GitHub repository page should be able to answer:

- what this project is
- what platforms are currently supported
- how to build it
- how to obtain the missing model dependency
- how to contribute correctly
- how to file bugs or feature requests
