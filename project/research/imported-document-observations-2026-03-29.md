# Imported Document Observations — 2026-03-29

Last updated: March 29, 2026
Status: Active research notes

## Observed Behavior

- The bundled sample document plays more cleanly than imported files.
- Imported files under roughly `1500` words still show noticeably heavier playback startup and resource usage.
- The current system behaves better when the speech text has already been curated.

## Evidence From The Current Codebase

- Importers primarily emit `displayHtml` plus a single `speakableText` string.
- `ReaderDocument` currently stores a flat speech field and coarse word spans.
- Kokoro phonemization, inference, and wav generation are currently part of the main application runtime path.

## Interpretation

- The sample path is not representative of the real imported-document workload.
- Imported formats need normalization before they reach chunk planning.
- Chunking from flattened strings discards too much context for good pronunciation and cadence.
- `async` alone is not enough for heavy speech work; CPU-heavy tasks still need a worker path.

## Working Conclusions

- The project needs a normalized speech representation, not just a flat string.
- Chunk planning should be segment-aware and sentence-aware.
- Future highlighting should be designed into the model now.
- Imported-document playback quality and performance should be solved through the same architectural change.
