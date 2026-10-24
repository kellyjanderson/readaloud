<!-- Historical snapshot; not current authority. -->

# Architecture Index

Architecture documents define the structural truth of `Read Aloud`.

## Current Documents

- [Document Preparation and Execution Contexts](../../../acd/prepared-document-runtime.acd)
  Defines whole-document readiness, character voice residency, audio lead, execution lanes and revision ownership.
- [System Overview](../../../architecture/system-overview.md)
  Defines the major system layers, subsystem boundaries, and responsibility split.
- [Document and Speech Pipeline](../../../architecture/document-speech-pipeline.md)
  Defines the accepted target architecture for document normalization, chunk planning, speech generation, caching, and playback coordination.
- [Normalized Content and Position Mapping](../../../architecture/normalized-content-and-position-mapping.md)
  Defines how imported content becomes paired display and speech representations with stable mapping between them.
- [Speech Enrichment and Narration](../../../architecture/speech-enrichment-and-narration.md)
  Defines the structural layer that infers phrase, pause, emphasis, pronunciation, and long-form narration state before synthesis.
- [Character Dialogue Attribution and Voice Casting](../../../architecture/character-dialogue-attribution-and-voice-casting.md)
  Defines how dialogue spans become attributed speakers, stable character identities, narrator/character cast assignments, and multi-voice playback routing.
- [Pronunciation Planning and TTS Artifacts](../../../architecture/pronunciation-planning-and-tts-artifacts.md)
  Defines how pronunciation is planned against the internal speech representation and passed into the TTS layer as durable, inspectable artifacts.
- [English Pronunciation Profiles and Rule Modularity](../../../architecture/english-pronunciation-profiles-and-rule-modularity.md)
  Defines how multiple English variants and accented-English overlays are modeled through selectable pronunciation profiles, layered resources, and productive rule modules.
- [Engine Pronunciation Expression and Capability Adaptation](../../../architecture/engine-pronunciation-expression-and-capability-adaptation.md)
  Defines how app-owned pronunciation artifacts are translated into engine-expressible inputs through explicit capability modeling, adapter translation, and fallback traceability.
- [Speech Runtime Messaging Boundary](../../../architecture/speech-runtime-messaging-boundary.md)
  Defines the official concurrency boundary between Flutter UI/control code and the long-lived speech runtime, including command/event ownership and native queue policy.
- [Playback Orchestration and Synthesis Boundaries](../../../architecture/playback-orchestration-and-synthesis-boundaries.md)
  Defines how enriched speech becomes generated chunks, how chunk boundaries are managed, and how playback sessions are coordinated.
- [Spoken Text Highlighting and Reading Focus](../../../architecture/spoken-text-highlighting-and-reading-focus.md)
  Defines how playback progress maps back into visible highlighted text and how the reader surface follows playback.
- [Audio Export and Headless Execution](../../../architecture/audio-export-and-headless-execution.md)
  Defines how the app saves spoken audio and runs the same speech pipeline without the normal UI for command-line and automation workflows.
