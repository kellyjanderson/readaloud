## Progressive analysis and automatic casting R13

November 4, 2026 Pacific. Amendment to Character contract R2 and plan R12, based
on `b3d16b9`. Proposed behavior, not implementation or native acceptance.

### Findings and evidence limits

The user reports that the current City of Births and Deaths cast is female so far,
but automatic choices were all male, and recalls fast character extraction followed
by more expensive parsing. Preserve these as product regression reports; their
exact installed build, saved state and emitted audio have not been reproduced.

Current source contains gender-aware selection: `CastVoiceAssignmentService`
prefers matching `CastEntry.inferredGender`, then balances other preferences.
Explicit overrides and saved choices take precedence. Fish defaults to the male
`library_fishadrian`; its catalog declares seven female and six male references,
plus the shared synthetic catalog's fifteen of each. Catalog labels/counts do not
prove installed availability or perceived voice identity. Unknown character cues,
saved intent, wrong attribution, playback fallback or reference realization must
be distinguished before claiming the City cause. Do not erase user choices as a fix.

`DocumentImportService` currently runs normalization, annotations, heuristic
attribution, cast consolidation/identity extraction and route construction in
sequence per fragment. The registry accumulates evidence, but this path does not
schedule an independent inexpensive discovery pass followed by a deeper provider.
`CharacterCastRegistryService` currently creates characters from attributed
dialogue, not an independent early mention-discovery stream. The retained
`character-identity-extraction-pass-ordering` specification describes separate
passes but requires a full-document scan; it is historical intent, not proof that
the recalled behavior exists now. R13 supersedes that full-document barrier and
quote-attribution prerequisite for provisional character discovery. Identity facts
still attach to stable character entities, never arbitrary name strings.

Bounded checks on this source: 15 existing registry/assignment tests passed with
`tools/flutter test test/cast_voice_assignment_service_test.dart
test/character_cast_registry_service_test.dart --reporter expanded` on arm64.
These do not reproduce the private City report or validate running-app speech.

### Two analysis passes, one Character owner

1. **Fast discovery:** incrementally extract candidate entities/aliases, obvious
   speaker tags and inexpensive attached identity/pronoun cues from acquired text.
   Publish provisional stable characters promptly, even before difficult dialogue
   attribution is resolved. Recognized names are candidates, not invented facts.
   Establish initial voice matches from available evidence. Do not wait for EOF,
   a neural model load or complete cast discovery before first speech.
2. **Deeper refinement:** analyze bounded source windows using the qualified
   provider for coreference, difficult speakers, aliases and contextual attributes.
   Prioritize the next unread region, then use spare capacity to improve later
   material. Reuse normalized text and first-pass evidence; do not re-import the
   book or reconstruct its characters. Neither pass must finish the entire work
   before the other can advance. ModernBookNLP is a candidate, not a prerequisite
   for the first pass or Fish playback.

Both publish CharacterAnalysisDelta into the R2 repository writer. Add per-range
analysis coverage/version and provenance identifying fast, refined, unresolved or
failed results; do not equate first-pass EOF with complete deep analysis. Persist
valid coverage/evidence in .radoc so reopening skips completed work independently
for each pass. Merge/split preserves IDs/redirects and explicit selections.

Automatic selection consumes the latest admitted character evidence and compatible
voice metadata. Reliable female cues must not lose to list order, narrator contrast
or preference for an unused male voice when compatible female choices exist.
Unknown/conflicting cues remain explicit. An automatic provisional choice is not
saved as user intent: stronger evidence can refine it. Preserve an already suitable
choice to avoid reshuffling the cast whenever another character appears. Explicit
user selections remain authoritative regardless of gender; Reset restores automatic
policy. Record selection reason and effective binding for diagnosis.

New automatic choices affect future uncommitted speech at a safe boundary. Do not
change the voice midway through an utterance, replay heard audio or overwrite a
captured active scene. Existing requested/effective coordination owns this transition.

### Ownership and scheduling

The preparation supervisor owns fast work and schedules bounded refinement through
the qualified analysis worker; the existing runtime admission owner gives playback
and imminent preparation priority over deeper analysis. Reuse platform/library
worker and backpressure facilities; no second scheduler/event bus or unlimited
per-character tasks. Queue windows and evidence projections are bounded; measured
limits are recorded by #113 before dispatch. UI receives immutable snapshots only.

Every result carries work/source revision, range, pass/provider version and analysis
epoch. The repository single writer rejects stale successes and failures. A late
fast result cannot replace newer refined evidence; model conclusions do not outrank
explicit corrections. Cancellation stops admission promptly, invalidates publication
and reaps owned workers under the existing timeout/shutdown contract. Deep failure
retains valid fast results, with honest retry/status. Track per-pass completed source
units and known totals; waiting for playback demand is not a spinning progress bar.

### Reuse Fish where supported

Fish documents native multi-speaker scenes, reference voices, expressive inline
directions and long-content generation. Use these for performance and delivery
instead of rebuilding them in Read Aloud. Its published inference interface maps
speaker tags to reference audio/transcripts. I found no documented structured
book-character/coreference/gender-extraction output in those interfaces; this is
an evidence limit, not proof the model cannot help. Any Fish-based analysis or
automatic casting capability must pass the same held-out structured-output oracle
before replacing an analysis component. [Fish overview](https://speech.fish.audio/)
and [inference contract](https://speech.fish.audio/inference/).

The pinned MLX Audio 0.6.3 implementation already accepts reference lists, caches
encoded references/system prefixes and retains first/latest chunk history within
a generation call. Its four-entry reference-set cache is not a four-character
product limit. Read Aloud currently sends one reference per request; wider native
scene use is an adapter gap. Reuse the library rather than duplicate these caches
or its internal chunk/history policy. Cross-call continuity is not established by
within-call history. [Pinned MLX source](https://raw.githubusercontent.com/Blaizzy/mlx-audio/v0.6.3/mlx_audio/tts/models/fish_drama3/drama3.py).

Verify feature support in the actual Apple Silicon backend; the official Fish
runtime's documented NVIDIA requirement does not establish MLX capability parity.
Native editing/director-revision capabilities are recorded reuse candidates, not
new release features. All shared Character data remains engine independent.

### Existing-plan ownership and acceptance

R12 unit A: #125 owns fast discovery/common analysis deltas and regression tests;
#126 owns persistent characters, matching/selection provenance and migration;
#127 owns deeper-provider qualification. Unit B/#111 owns Fish-native references,
scene realization and emitted-voice proof. Unit C/#113/#119 owns bounded scheduling
and honest pass progress. Other units and native dependencies remain unchanged.

Required shared scenarios: provisional cast before delayed deep completion;
female cues to automatic female references through both catalog and actual speech;
City's reported all-female passage without manual workarounds; mixed and unknown
casts; later evidence improving automatic choice without erasing explicit male
selection; exhausted matching pool; shuffled catalog; split/whole equivalence;
reopen/cache loss; late fast/deep results, replacement/cancel and stalled provider;
no mid-utterance change; no unnecessary reanalysis or model reload. Use synthetic
public fixtures and private City labels/audio. Test clear narrator fallback rather
than silently treating it as a correct character voice. Match counts alone do not
qualify five usable choices or voice identity. Keep external-launch timing and
responsiveness/continuity gates. Reconcile architecture only after implementation.
