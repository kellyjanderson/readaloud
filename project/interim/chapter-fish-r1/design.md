# Chapter analysis and Fish Audio Drama 3 scene inputs

Revision 1. The current release includes the repositioning of ModernBookNLP and the use of its linguistic metadata to choose the scene blocks submitted to Fish. [Design #158](https://github.com/kellyjanderson/readaloud/issues/158) · [Release #122](https://github.com/kellyjanderson/readaloud/issues/122)

## Problem and intended behavior

Today a prepared speech fragment and its predecessor tail constrain the context sent to MBNLP. Quote matches can refine existing heuristic dialogue ranges, but a correct provider span that the heuristics missed cannot become a spoken character turn. Short renderer chunks also divide clauses or reporting tags that give Fish the context to perform a line.

Opening an original document with MBNLP enabled starts an incremental pass through all available chapters. Store each chapter's complete analysis and coverage before releasing that chapter to direction, casting and scene compilation. While Fish works on the first chapter, MBNLP processes the next one. A seek prioritizes the requested chapter and preserves completed coverage. Pausing speech leaves analysis eligible. Closing the document cancels the pass.

## Units and ownership

- The importer produces source-mapped text with original punctuation, paragraphs and chapter boundaries. The analysis worker owns one active chapter request per document plus the next priority. It persists exact input identity, model identity, raw evidence, decisions and coverage by source revision. Chapter inputs may cross import fragments.
- Prefer an intact chapter. If capacity requires smaller inputs, preserve whole words, sentences and complete quotations, including continued speech. Reconcile overlapping interiors with preceding and following context. An indivisible over-budget unit gets an explicit unresolved outcome. Normalize repeated limits before adding safeguards.
- The reading track covers the speakable text in source order. Use quote and speaker-mention spans, coreference and explicit speech tags. Distinguish a character mentioned from one speaking. Documented raw evidence can correct boundaries established by early heuristics. Authored corrections retain priority.
- The scene planner consumes admitted chapter metadata and selected voices. Use sentences, paragraphs, syntactic attachments, reporting clauses and continuation across speech tags to compose Fish requests. Preserve words, punctuation, ordering and source anchors. An interrupted utterance can have character/narrator/character spans in one Fish scene. Backend-qualified size and reference limits govern rendering.
- Reuse existing off-UI worker, cancellation, memory admission, captured-scene and offline-book owners. Reject stale success and failure by source revision and owner. Use real completed-work progress, actionable over-budget states and existing worker timeouts and shutdown. On edit, invalidate affected context, track and rendered scenes. Playback and export consume the same decisions.

## Release acceptance and outstanding decision

Trace a source chapter across fragments through to emitted voices. Test narration misclassified by the old route, paragraph-separated replies, pronoun references, interrupted speech, continued dialogue, oversized units and a late result after seek or cancellation. Check cold source open, valid analysis reopen, portable audio, re-render after edit and offline playback. Compare like-for-like renderings around joins with the same cast and text, and listen for unintended resets, gaps and missing words. The separate handoff tool permits exploratory compositions; acceptance uses the ordinary app and target hardware. [Handoff app #159](https://github.com/kellyjanderson/readaloud/issues/159)

The sample chapter took 11.24 seconds for inference plus 4.99 seconds for cold model verification/load. Uncached, chapter-gated rendering conflicts with the two-second launch goal and ten-second first-load limit on that observation. Record actual open, Play, chapter publication and emitted-audio times. Release planning must reconcile the measured conflict explicitly. This revision grants no timing waiver.

Reconcile document speech processing, character attribution, playback and export architecture after implementation. Mobile inference, viewpoint casting, authoring and named-voice verification have separate design issues. Earlier release-candidate listening results retain their original identities.
