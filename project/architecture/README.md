# Architecture Index

Architecture documents define the structural truth of `Read Aloud`.

## Current Documents

- [System Overview](system-overview.md)
  Defines the major system layers, subsystem boundaries, and responsibility split.
- [Document and Speech Pipeline](document-speech-pipeline.md)
  Defines the accepted target architecture for document normalization, chunk planning, speech generation, caching, and playback coordination.
- [Normalized Content and Position Mapping](normalized-content-and-position-mapping.md)
  Defines how imported content becomes paired display and speech representations with stable mapping between them.
- [Speech Enrichment and Narration](speech-enrichment-and-narration.md)
  Defines the structural layer that infers phrase, pause, emphasis, pronunciation, and long-form narration state before synthesis.
- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)
  Defines how pronunciation is planned against the internal speech representation and passed into the TTS layer as durable, inspectable artifacts.
- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)
  Defines how multiple English variants and accented-English overlays are modeled through selectable pronunciation profiles, layered resources, and productive rule modules.
- [Engine Pronunciation Expression and Capability Adaptation](engine-pronunciation-expression-and-capability-adaptation.md)
  Defines how app-owned pronunciation artifacts are translated into engine-expressible inputs through explicit capability modeling, adapter translation, and fallback traceability.
- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)
  Defines the official concurrency boundary between Flutter UI/control code and the long-lived speech runtime, including command/event ownership and native queue policy.
- [Playback Orchestration and Synthesis Boundaries](playback-orchestration-and-synthesis-boundaries.md)
  Defines how enriched speech becomes generated chunks, how chunk boundaries are managed, and how playback sessions are coordinated.
- [Audio Export and Headless Execution](audio-export-and-headless-execution.md)
  Defines how the app saves spoken audio and runs the same speech pipeline without the normal UI for command-line and automation workflows.
