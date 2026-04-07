# Branding, Design, and UX Recommendations — 2026-04-07

## Purpose

This document captures a design-review pass across the current `Read Aloud` UI from brand, interaction-design, and UX perspectives.

It is a recommendation document, not a feature specification.

Its role is to:

- record the current design read
- identify high-leverage UX and brand problems
- recommend a coherent direction for future UI refinement

## Product And Brand Read

The product definition is unusually clear:

- calm
- dependable
- personal
- private and local-first
- built around long-form listening rather than document management

That is a strong brand foundation.

The current UI does not yet express that foundation consistently.

Today the product feels split between several visual personalities:

- a warm paper-reader metaphor
- a dark technical shell
- library-management surfaces
- diagnostic or prototype-like status treatments

The result is not that the product feels bad in every moment.

The result is that the product does not yet feel like one intentional brand.

## High-Level Recommendation

The north star should be:

- reader first
- studio second

`Read Aloud` should feel like a trusted reading companion with strong voice controls, not like a speech-lab tool that also happens to read documents.

That means:

- primary surfaces should feel editorial and calm
- advanced tooling should stay secondary
- diagnostics should not shape the visual personality of the app
- voice sophistication should feel guided rather than technical

## Current Design Findings

### What Is Working

- The product direction toward a simplified reading surface is correct.
- Follow-along behavior makes the app feel more alive and useful.
- Multi-voice reading is becoming meaningfully differentiated.
- The move away from a large in-surface title banner was the right correction.

### What Is Not Working Yet

- Visual hierarchy is inconsistent across surfaces.
- Some dialogs and feedback surfaces still fail basic readability or contrast standards.
- The brand palette is not cohesive enough to feel deliberate.
- Status and debug information still compete too directly with primary reading.
- Voice-management surfaces expose useful power, but not yet with enough clarity or ease of comparison.

## Voice Management Recommendations

### Recommendation

The voice-management dialog should behave more like a curated casting surface and less like a generic form.

Each surfaced voice choice should show:

- voice name
- quality rank
- gender when known
- locale
- short description when available
- preview action

Longer metadata can remain behind the information affordance, but the user should not need to open a secondary layer just to answer:

- Is this voice high quality?
- Is it male, female, or neutral?
- What kind of voice is it?
- What does it sound like?

### Preview Behavior

Add an explicit preview button next to each surfaced voice choice.

Recommendation:

- short deterministic sample
- only one preview playing at a time
- visible playing state
- does not commit assignment

This is one of the highest-value UI additions in the current app because it turns casting from guesswork into comparison.

### Row Hierarchy

Recommended row hierarchy:

1. name
2. quality rank and gender
3. locale and install or assignment state
4. short one-line description
5. preview and information actions

This keeps the rows scannable while still making comparison possible.

## Transport Control Review

### Your Idea

Your proposal is:

- one unified transport control
- about 10 percent taller
- back on the left
- play, pause, or processing state in the center
- forward on the right
- optional thin separators between the center and side actions

### Critical Review

This is a strong direction if it is treated as one visual control group, not as one literal undifferentiated button.

The idea solves several current problems:

- the transport feels more intentional
- the controls stop looking like three unrelated widgets
- the primary action stays centered
- the bottom bar becomes calmer and less noisy

The main risks are:

- ambiguous hit targets if it behaves like one button instead of three clear segments
- accidental jumps if the side actions are too easy to hit
- reduced clarity if the center state is not visibly dominant

### Recommendation

Pursue this as a segmented transport capsule.

That means:

- one shared visual container
- three independent hit targets
- the center region wider and more visually dominant
- back and forward visually quieter than the center action
- thin separators are good if they stay subtle

Recommended weighting:

- center segment is the primary action
- side segments are secondary actions
- total control height can increase by roughly 10 to 14 percent

The processing state should appear only in the center segment.

If playback is preparing, the center segment can communicate that clearly while the side segments either remain available or become intentionally muted according to playback-policy rules.

### Bottom-Line Judgment

Yes to one unified transport object.

No to one literal single button target.

The right implementation model is:

- one component
- three segments
- one hierarchy

## Feedback And Status Recommendations

The current status pattern still needs a major UX cleanup.

The design rule should be:

- critical user-actionable information gets surfaced
- routine runtime noise does not
- nothing should push the reading surface around

Recommendation:

- use toast-style in-app popups for critical but non-blocking feedback
- use overlays for true in-progress states
- keep routine technical errors in debug logs unless the user must act

This aligns much better with the product promise of calm and dependable reading.

## Brand Review

### Brand Strength

`Read Aloud` already has a strong conceptual brand:

- local-first
- calm
- literary
- trustworthy
- personal

That is better than many early products, because the emotional promise is already visible in the product definition.

### Brand Gap

The visual system does not yet express that promise consistently.

Right now the app uses a mix of:

- warm paper colors
- dark blue-gray shell colors
- brown or gold modal surfaces
- utility-style badges and banners

These choices are not individually wrong.

They simply do not yet read as one brand system.

### Brand Recommendation

The visual brand should move toward:

- quiet editorial
- warm but modern
- high-trust
- locally grounded rather than cloud-software generic

Recommended brand attributes:

- calm
- literate
- warm
- private
- precise

Attributes to avoid:

- loud
- overly technical
- overly playful
- dashboard-like

## Design-System Recommendations

### Color

Use one coherent palette system rather than separate moods per surface.

Recommended shape:

- one neutral reading palette
- one primary accent
- one support accent for state or emphasis

The reading surface should feel stable across modes:

- light mode: warm paper with strong ink text
- dark mode: dark charcoal reading pane with soft light text

Dialogs, banners, chips, and transport should all derive from the same token family rather than introducing their own moods.

### Typography

The app would benefit from a clearer split between:

- UI typography
- reading typography

Recommendation:

- keep UI text in a clean humanist sans
- use a more book-friendly reading face for document content when practical

Even if that typography change is deferred, the system should start thinking in those two layers now.

### Shape Language

Current rounded surfaces are directionally good.

Recommendation:

- keep rounded forms
- reduce arbitrary variety in radius and surface emphasis
- make transport, dialogs, chips, and overlays feel like members of one family

### Motion

Motion should feel calm and assistive.

Recommendation:

- short fades
- quiet state transitions
- no dramatic springy motion on primary reading interactions

## UX Recommendations

### Primary Surface

The primary reader surface should continue simplifying.

The right model is:

- document first
- transport second
- voice domain third

Everything else should justify its presence.

### Voice Domain

Voice management is currently one of the product’s differentiators.

That means it should feel:

- powerful
- easy to compare
- easy to understand

not:

- dense
- hidden
- visually washed out

### Stability

Avoid layout shifts wherever possible.

The reading surface should feel spatially stable during:

- playback
- buffering
- warning states
- document loading

### Testing Priority

From a UX-risk standpoint, the next highest-value UI work is:

1. make voice-management comparison excellent
2. stabilize the feedback hierarchy
3. unify transport into one stronger control object
4. perform a full visual-system and brand-token pass

## Recommended Two-Round Plan

### Round 1: Testing-Unblock UI Improvements

- keep the current structural surfaces
- add voice preview
- surface quality rank, gender, and short description directly
- keep contrast readable everywhere
- stop disruptive feedback from shifting layout

### Round 2: Full Brand, Design, And UX Overhaul

- unify the palette and surface token system
- redesign transport as a segmented capsule
- refine typography and spacing scale
- standardize badges, chips, overlays, and dialogs
- align the whole app to one calm editorial brand system

## Summary Recommendation

The product promise is stronger than the current visual system.

That is good news.

It means the app does not need a new identity.

It needs its current identity expressed more consistently.

The clearest path is:

- strengthen voice-management comparison
- unify transport
- reduce diagnostic visual noise
- consolidate the brand into one quiet editorial reading system
