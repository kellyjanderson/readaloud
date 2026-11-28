## ACD-A2 — Local attribution provider boundary and ModernBookNLP gate

> Fixed published R1 snapshot, captured November 4, 2026 Pacific.
> [Source design/plan](https://github.com/kellyjanderson/readaloud/issues/124#acd-a2--local-attribution-provider-boundary-and-modernbooknlp-gate) · [package provenance](README.md) · [lifecycle](../README.md).
> GitHub owns current execution state; this snapshot is not an implementation or acceptance claim.

Design revision R1. Basis: [A2 source findings](https://github.com/kellyjanderson/readaloud/issues/124#a2--modernbooknlp-local-provider-evaluation), pinned upstream `84f1f34f6f0ec7c6e9c558b4371e61ea2354d95b`. This design selects a local evaluation boundary; it does not claim ModernBookNLP is the best model or already works on Apple GPU.

### Interface and execution
Define a data-only `AttributionProvider` request carrying work/source/analysis revisions, bounded source spans/text, candidate character IDs and a bounded context checkpoint. Response contains attributed spans, unknowns, confidence provenance, entity/alias evidence, provider/model digests and updated context. No voice assignment mutation, playback calls, native tensors or UI objects cross this boundary. The repaired heuristic is the initial provider and fallback with visible provenance; neural results may refine future unplayed spans under a new analysis revision, never override explicit user corrections or the captured active scene.

Run the neural provider in a separately managed Python child/environment, not inside the MLX TTS environment. One active request and one replaceable pending demand; bounded text/token context must be measured and enforced before promotion. Cancellation invalidates results immediately and terminates/reaps a noncooperative child through ACD-R1; no in-band cancel queued behind inference. Resource admission accounts for both provider and TTS memory. Speech preparation cannot wait for whole-book NLP.

Application-owned acquisition supplies pinned QA, encoder/tokenizer, entity/coreference and spaCy artifacts through the same verified download store contract as ACD-M1. Constructors must not trigger invisible home-directory downloads. Qualify CPU first; verify the hard-coded CUDA autocast correction and actual MPS operator coverage before advertising Apple acceleration. Record package/model licenses and dependency footprint; a source license alone is insufficient.

### Promotion decision, compatibility and proof
Compare repaired heuristics, ModernBookNLP joint scoring and, if justified, direct scoring on fixed independent public held-out cases plus private City labels. Freeze labels before tuning. Report per-case/per-category accuracy, abstention/coverage, incorrect confident attribution, entity/alias errors, cold/warm latency, incremental startup and whole-process-tree memory. Promotion requires corrected boundary oracles, no regression in mandatory explicit-tag/user-correction cases, improved held-out attribution without hiding errors as blanket abstention, and compliance with bounded reading and physical memory policy. If these fail, retain the repaired provider and publish the measured blocker; do not replace it merely because a paper score is higher.

Dependencies: ACD-A1 baseline and ACD-C1 identity contract; acquisition/process mechanisms reuse ACD-M1/R1. First implementation is a bounded provider spike and a decision receipt, then production integration only on passing evidence. No downloaded weights or application changes are part of this documentation revision. Reconcile character architecture, runtime messaging and MLX/provider setup after actual integration.

### Source and reconciliation anchors

Pinned existing owners, not implementation of this ACD. Additional exact locations and test matrices remain in the linked review findings.

- [lib/src/services/speaker_attribution_service.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/services/speaker_attribution_service.dart)
- [lib/src/models/character_cast_registry.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/models/character_cast_registry.dart)
- [lib/src/services/reader_document_repository.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/services/reader_document_repository.dart)
- [project/architecture/character-dialogue-attribution-and-voice-casting.md](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/project/architecture/character-dialogue-attribution-and-voice-casting.md)
- [test/rc2_cast_inference_test.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/test/rc2_cast_inference_test.dart)
