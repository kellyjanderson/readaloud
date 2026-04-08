# US-English Starter Voice Set And Auto-Cast Preference

Status: final

## Overview

This specification defines the curated bundled Kokoro starter voices and the default regional preference used by automatic cast assignment.

## Backlink

Parent specifications:

- [Character Cast Registry and Voice Assignment](character-cast-registry-and-voice-assignment.md)
- [Voice Library Metadata and Information Surfacing](voice-library-metadata-and-information-surfacing.md)

## Scope

This specification covers:

- the bundled starter voice set shipped with the app
- the default narrator voice within that starter set
- the app-owned gender/role metadata needed to surface that set coherently
- preference for US-English voices during automatic cast assignment when multiple regional voices are available

## Behavior

The bundled Kokoro starter set must be a curated American English set.

The starter set must contain exactly:

- two female voices
- two male voices
- one neutral voice

The set should be chosen from the highest-quality currently available US-English Kokoro voices that the app bundles locally.

If the upstream American-English Kokoro catalog does not provide an explicit neutral option, the app may curate one bundled US-English voice into the neutral starter role using app-owned metadata, as long as:

- the choice is deterministic
- the choice is documented in app-owned voice metadata
- the result is surfaced consistently to the UI and auto-cast policy

The default narrator voice should come from that same bundled US-English starter set and should prefer the strongest-quality narrator-suitable voice in the set.

When automatic cast assignment has multiple plausible voices available across different English regional sets, it should prefer US-English voices before falling back to other regional English voices.

This regional preference applies to automatic assignment only. Explicit user narrator choice and explicit cast overrides still take precedence.

## Constraints

- the shipped starter voices must all be real bundled assets, not only catalog entries
- automatic regional preference must remain deterministic
- user overrides and stored document choices must still outrank locale preference
- the app must not silently claim upstream metadata that it does not own; any curated starter-role metadata must remain app-owned

## Acceptance

- a fresh install exposes a bundled starter set of five US-English voices
- that starter set contains two female voices, two male voices, and one neutral voice in app-owned metadata
- the default narrator voice comes from that starter set
- when both US-English and other English regional voices are available, automatic cast assignment prefers US-English voices when other selection factors are comparable
