# Follow-Along Reading Surface

## Purpose

Define the visible reader behavior for highlighting the text currently being spoken and following playback without making the reading surface feel jumpy or crowded.

## Primary Behavior

When playback is active, the reading surface should:

- highlight the text currently being spoken
- keep the active reading region visible
- preserve a clean reading experience rather than visibly chasing every phoneme-sized update

## Highlight Precision

Preferred order:

1. current spoken word
2. current spoken phrase or segment
3. current visible block

The UI should use the highest-confidence available mapping.

## Visual Hierarchy

The spoken highlight should be visually obvious but not noisy.

The active spoken range should receive the strongest emphasis.

Surrounding context should remain readable and calm.

Across supported appearance modes, the reading pane must preserve strong text-to-surface contrast.

In dark mode specifically:

- the reading surface should be a very dark gray
- reading text should be much lighter than the surface
- highlight styling must not turn the active text into a low-contrast wash

## Reading Focus Motion

Automatic viewport movement should:

- follow playback when the active region approaches the edge of the comfortable reading area
- avoid recentering on every word
- preserve visual stability during continuous playback

## User Control Rule

If the user manually scrolls while playback is running, the interface should temporarily yield control of the viewport.

It should not fight the user by snapping back immediately.

The app may offer a simple way to re-center on the active spoken range.

## Pause Behavior

When playback pauses:

- the spoken highlight remains visible on the last spoken range
- the viewport stops auto-following

When playback resumes:

- follow behavior resumes from the current spoken range

## Relationship To Other UI Docs

- [UI System Overview](ui-system-overview.md)
- [Primary Surface and Complexity Layering](primary-surface-and-complexity-layering.md)
