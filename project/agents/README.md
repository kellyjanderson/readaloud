# Project Agent Rules

This folder is the canonical place for `Read Aloud`-specific agent rules.

Use this folder for durable project-specific instructions that affect how agents should operate in this repository, but that do not belong in product, architecture, specification, planning, or research documents.

Examples include:

- project-specific coding rules
- project-specific debugging workflows
- project-specific release or QA procedures
- project-specific document maintenance rules

## Audio Change Verification Rule

For pronunciation, synthesis, and other speech-output fixes, agents must verify that a code change produced a real audio change before claiming the fix had effect.

Use the pronunciation probe and audio comparison workflow when working on these issues.

The rule is:

1. capture a baseline audio run for the target phrase or phrases
2. make the code change
3. capture a second run for the same phrases
4. compare the before and after audio outputs

If the before and after output is identical, the change did not materially affect synthesis and should not be treated as a successful fix.

For this project, prefer the existing headless pronunciation probe path and compare PCM hashes or equivalent waveform-level analysis rather than relying only on code inspection or casual listening.

When reporting work on pronunciation or TTS behavior, agents should state whether:

- the emitted audio changed
- the emitted audio did not change
- or audio change verification was not completed

Do not present a pronunciation fix as successful if audio change verification has not been performed or if the compared output remained identical.

## Relationship to `agents/`

The root [`agents/`](../../agents/index.md) folder defines repository-wide agent process and workflow guidance.

This `project/agents/` folder defines additional rules that are specific to `Read Aloud`.

The intended hierarchy is:

1. shared agent process in `agents/`
2. project-specific agent rules in `project/agents/`
3. project product and system documents in the other `project/` folders

Project-specific rules should supplement or narrow the shared agent guidance for this project. They should not restate architecture, specifications, or planning content that already belongs elsewhere.

## Usage

Agents should check this folder before beginning substantial work on the project.

If a new project-specific operating rule is discovered, it should be recorded here rather than improvised in chat history.
