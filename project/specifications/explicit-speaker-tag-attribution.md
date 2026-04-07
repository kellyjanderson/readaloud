# Explicit Speaker Tag Attribution

Status: final

## Overview

This specification defines authoritative same-sentence speaker attribution from explicit quote-tag patterns.

## Backlink

Parent specification:

- [Quoted Dialogue Speaker Context Scanning](quoted-dialogue-speaker-context-scanning.md)

## Scope

This specification covers:

- quote and speaker tag in the same sentence
- `name + speech verb` patterns
- `speech verb + name` patterns
- action words that remain clearly attached to the same speaker tag

## Behavior

When quoted text and a speaker tag appear in the same sentence, that attribution is authoritative.

Supported patterns include at least:

- `Jennifer said, "..."`
- `"..." said John.`
- `"..." John said.`
- `Jennifer turned and said, "..."`
- `"..." Elliot replied sarcastically.`

This rule must outrank weaker adjacent, paragraph, alternation, pronoun, and persistence heuristics.

## Constraints

- the name and speech/action phrase must be clearly attached to the quoted utterance
- the parser must not drift to a different speaker when one same-sentence tag is already explicit

## Acceptance

- same-sentence explicit speaker tags are treated as authoritative
- clear `name + speech verb` and `speech verb + name` patterns attribute the quote directly
