# Historical separate-turn Fish book metadata

These JSON records come from an ordinary signed Fish 8-bit rendering of the
public synthetic `../s3_dialogue.txt` fixture on November 17, 2026. The source
package was `fish8-dialogue-baseline.radoc` (SHA-256
`ab69650d699a32ed3f32ab34e2f89faee67b416ffcf2896073c94de070da4941`).
The machine-specific source ID is replaced with `synthetic-s3-dialogue`, and the
voice catalog is reduced to the three used voices. The seven original scene
dependencies/provenance and prepared document remain structurally unchanged:
raw turns/bindings and published scene turns are empty, but provenance retains
each actual binding and prepared attribution retains canonical cast ownership.

Tests replace audio with distinct short deterministic PCM payloads, update WAV
format/frame metadata, and let the package writer rebuild member checksums.
They prove selective admission, regeneration, preservation and save/reopen;
they do not prove speech, boundaries, emitted-audio continuity or listening.
No model weights, native speech audio or private manuscript text is included.
