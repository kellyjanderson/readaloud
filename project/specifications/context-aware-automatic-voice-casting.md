# Context-Aware Automatic Voice Casting

Status: final

## Overview

This specification defines the higher-quality automatic casting policy that uses cast metadata and available voice metadata to choose narrator and character voices more intelligently.

## Backlink

Parent specification:

- [Character Cast Registry and Voice Assignment](character-cast-registry-and-voice-assignment.md)

## Scope

This specification covers:

- narrator-first automatic casting
- use of extracted character identity metadata when available
- contrast from narrator voice when possible
- deterministic fallback when evidence is missing

## Behavior

Automatic casting must remain deterministic within one document version, but it must do more than cycle through voices arbitrarily.

The narrator automatic voice should default to the currently selected primary voice unless an explicit override exists.

For character roles, automatic casting should prefer voices using this order:

1. installed voices that match the cast entry's extracted gender identity label when that label is explicit, strong, and usable for casting
2. within that set, voices that remain audibly distinct from the narrator voice when possible
3. remaining installed voices using stable quality and locale ordering
4. narrator or default fallback when no distinct match is available

When a cast entry has no usable explicit identity label, automatic casting may still prefer voices that preserve audible contrast from the narrator before falling back to arbitrary reuse.

When multiple character entries share the same usable identity label, the policy should distribute available compatible voices before reusing one voice for every character when the installed pool allows that distinction.

The resulting automatic assignments must remain visible to the override workflow rather than being hidden inside playback-only state.

## Constraints

- automatic casting must use only app-owned cast and voice metadata
- the policy must remain deterministic for the same document version and installed voice set
- the policy must never require live playback state to choose a cast voice
- when evidence is absent, fallback must stay stable and explicit rather than pretending a semantic match exists
- casting must not infer cis identity from pronouns, names, or descriptors alone

## Acceptance

- narrator and character automatic assignments are derived from cast and voice metadata rather than arbitrary cycling alone
- characters with strong extracted identity evidence prefer matching voice metadata when compatible voices are installed
- the policy still produces stable assignments when no gender evidence exists
- the running app can surface more plausible narrator-versus-character defaults before any user override
