/* Scenarios distilled from the current RC2 acceptance contracts in issues #83, #86, #88, #90 and #78. */
window.HUMAN_ACCEPTANCE_SCENARIOS = [
  {
    id: 'cold-first-audio', title: 'Cold launch to first audio', group: 'Startup and timing',
    description: 'Measure a cold process launch through the first emitted audio on the identified release build.',
    prepare: ['Quit Read Aloud and verify it is not running.', 'Use a fresh disposable QA profile only when the test plan provides one; never clear an existing user profile.', 'Have a 100–200 word plain-text passage ready and note whether its source/cache is cold.'],
    steps: ['Launch the exact candidate build using the path recorded above. Start a timer at the launch action.', 'Open the prepared document through File → Open Document. Record time to usable reader and time to Play becoming available.', 'Press Play and stop the timer only when actual output begins. Record each interval separately; repeat the cold run if the setup calls for multiple samples.', 'Record the exact build ID, profile/cache condition, background load and any errors. Do not use debug-build timings.'],
    expected: ['The app opens and reaches actual audio output without hidden waits.', 'The contract target is 2 seconds; record the measured value even when it misses. A failed threshold is an engineering blocker, not a human waiver.'],
    risk: 'Engineering measurement', app: true
  },
  {
    id: 'warm-launch', title: 'Warm launch and cached document', group: 'Startup and timing',
    description: 'Compare a warm launch and valid cached document reopen with the cold path.',
    prepare: ['Complete one successful cold intake using the same identified candidate and QA profile.', 'Quit Read Aloud normally and verify its process has exited before relaunching.'],
    steps: ['Launch the same build and profile; time launch to usable reader, Play readiness and first output independently.', 'Reopen the same unchanged source or valid .radoc through normal UI.', 'Record repeated samples and cache state. Do not delete caches to create a warm-run condition.'],
    expected: ['Warm reopen reuses valid preparation and avoids repeated whole-document analysis.', 'Record timing distributions and any regressions against the 2-second target.'],
    risk: 'Engineering measurement', app: true
  },
  ...[
    { id: 'p0-no-dialogue', title: 'P0 · No dialogue', fixture: 'tide.txt', speakers: 'Narrator only; no dialogue speakers. Ivo is a named non-speaker.' },
    { id: 'p1-one-speaker', title: 'P1 · One dialogue speaker', fixture: 'lantern.txt', speakers: 'Narrator plus Mara. Ellis is a named non-speaker.' },
    { id: 'p2-two-speakers', title: 'P2 · Two dialogue speakers', fixture: 'orchard.txt', speakers: 'Narrator plus Mara and Jonah. Ellis and Niko are named non-speakers.' },
    { id: 'p3-three-speakers', title: 'P3 · Three dialogue speakers', fixture: 'platform.txt', speakers: 'Narrator plus Mara, Jonah and Niko. Ellis is a named non-speaker.' },
    { id: 'p4-four-speakers', title: 'P4 · Four dialogue speakers', fixture: 'bridge.txt', speakers: 'Narrator plus Mara, Jonah, Niko and Saira. Ellis is a named non-speaker.' }
  ].map((item) => ({
    ...item, group: 'Prose attribution and casting', description: 'Open this frozen original prose fixture through normal plain-text intake, then inspect the real cast UI.',
    prepare: ['Use the fixture path shown below; do not open the oracle JSON or inject a prepared cast registry into the app.', 'Start from a cleanly quit app process.'],
    steps: ['Launch the exact candidate. Choose File → Open Document and select the fixture.', 'Wait for the relevant cast evidence to finish, while noting whether early playback is available before later speakers are analyzed.', 'Open Character Voices from the normal reader control. Inspect visible entries and selectable choices.', 'Compare the visible cast with the expected speaker set below. Check narration remains separate, and no named non-speaker appears as a dialogue speaker.', 'For P4, note when each later speaker appears relative to the dialogue and whether existing entries remain stable.'],
    expected: [item.speakers, 'Every actual speaker has one usable voice entry; no omissions, invented speakers, duplicate aliases or silent fallback on clear dialogue.', 'Narration remains separately available. For P4, later entries appear as evidence is processed, before that speaker’s dialogue is spoken.'],
    risk: 'Native UI and attribution', app: true, fixturePath: `test/fixtures/rc2_prose/text/${item.fixture}`
  })),
  {
    id: 'voice-assignment-roundtrip', title: 'Change character voices and reload', group: 'Voice assignment',
    description: 'Verify the actual voice management dialog supports distinct choices and persists bindings through playback and reload.',
    prepare: ['Use a document with at least two clearly attributed speakers.', 'Start with the app fully quit.'],
    steps: ['Launch the exact candidate and open the document through normal intake.', 'Open Character Voices. Choose two distinct supported voices for two characters and apply the changes.', 'Play dialogue from both characters and verify the intended assignments are used.', 'Save/reopen the document or use the supported .radoc round trip. Reopen Character Voices and inspect both assignments.'],
    expected: ['The dialog offers the supported voice choices for each character.', 'Distinct character-to-voice bindings survive playback and document reload.'],
    risk: 'Native UI and audio', app: true
  },
  {
    id: 'responsiveness-progress', title: 'Input response and reading progress', group: 'Responsiveness',
    description: 'Inspect reader interaction and progress under ordinary and CPU-heavy background load without inventing a numeric budget.',
    prepare: ['Use a long document (tens of pages); repeat on a full novel when available.', 'Arrange normal load and a separate representative CPU-heavy background-load run. Record what else is running.'],
    steps: ['Launch the exact candidate, open the document normally, and start playback.', 'Scroll the reading surface, seek backward/forward and use follow-along while speech continues.', 'Observe visible progress and input response. Record individual pauses/stalls and their duration when measurable, along with the triggering action.', 'Repeat the same interactions under CPU-heavy background load.'],
    expected: ['Progress remains accurate, visible and responsive to playback.', 'Record individual input/frame observations; no approved numerical input/frame budget exists, so do not invent one or claim a threshold pass.'],
    risk: 'Native UI and timing', app: true
  },
  {
    id: 'cancel-latest-intent', title: 'Cancellation and latest document intent', group: 'Preparation and cancellation',
    description: 'Check that cancellation or a newer document request prevents stale earlier work from replacing the current reader state.',
    prepare: ['Prepare two distinct long documents A and B; start with the app quit.', 'Use normal file intake only; do not inject prepared state.'],
    steps: ['Launch the exact candidate and begin opening A.', 'While A is still preparing, cancel if offered or request B using the ordinary UI.', 'Observe which document becomes current, whether controls recover, and whether late progress/errors from A appear after B.', 'Repeat with the supported cancellation/retry path if available.'],
    expected: ['The latest accepted intent remains current; cancelled or stale work cannot overwrite it or leak misleading progress/errors.', 'Record any control that is incorrectly enabled, stuck or missing its completion/failure state.'],
    risk: 'Native UI and asynchronous state', app: true
  },
  {
    id: 'continuous-playback', title: 'Live playback continuity · 30 minutes', group: 'Live audio',
    description: 'Exercise live player output under normal load for 30 minutes and retain independent capture evidence.',
    prepare: ['Use a sufficiently long document and an approved local audio capture route.', 'Confirm there is no second test app process running.', 'Have an audio analysis/review method ready; a generated WAV alone does not prove live continuity.'],
    steps: ['Launch the exact candidate, open the long document through normal intake, and begin actual live playback.', 'Capture the player output for 30 minutes under normal expected use. Note pauses, errors and device conditions.', 'Decode and compare the capture with expected text/audio spans. Inspect gaps, repeats, discontinuities, queue lead and timestamps.', 'Record exact capture path, duration, analysis summary and modality limits.'],
    expected: ['The live stream remains continuous for the full interval with no unexplained missing or repeated passages.', 'Do not pass based only on concatenated export WAVs, readiness status or ASR.'],
    risk: 'Long-running audio evidence', app: true
  },
  {
    id: 'radoc-cold-warm', title: 'Reusable .radoc cold and warm path', group: 'Persistence and export',
    description: 'Prove first preparation and valid second-run reuse, including complete multi-range checkpoint export.',
    prepare: ['Use a source document that yields multiple prepared ranges and has annotations/evidence to preserve.', 'Start with the app quit and retain the unchanged original source.'],
    steps: ['Launch the exact candidate and open the source normally. Record the cold preparation path.', 'Create or save the supported .radoc checkpoint. Verify ordered range IDs, annotations, evidence and voice overrides are present.', 'Quit and verify process exit. Relaunch the same build/profile and reopen the same .radoc through normal UI.', 'Compare warm-run analysis behavior and reopen timing. Verify content and annotations are unchanged.'],
    expected: ['The valid second run reuses preparation and avoids repeated valid analysis.', 'Complete export/reopen preserves ordered IDs, annotations, evidence and validated voice assignments; the source remains untouched.'],
    risk: 'Persistence and source integrity', app: true
  },
  {
    id: 'radoc-invalid-recovery', title: 'Partial, stale or corrupt .radoc recovery', group: 'Persistence and export',
    description: 'Check safe recovery paths using disposable copies of partial, stale and corrupt cache files.',
    prepare: ['Prepare disposable copies of each malformed/stale fixture; never alter the original document or a user cache.', 'Record the fixture paths and source revision being tested.'],
    steps: ['Launch the exact candidate and open each disposable case through normal UI.', 'Observe whether the app rejects or safely rebuilds the invalid cache without accepting partial analysis.', 'Verify the original source remains byte-for-byte unchanged and a subsequent valid reopen works.', 'Record each variant separately in notes; attach hashes or logs if available.'],
    expected: ['Stale, partial or corrupt prepared data is never treated as a valid reusable result.', 'Recovery is safe, reports the condition clearly and preserves source data.'],
    risk: 'Data recovery and source integrity', app: true
  },
  {
    id: 'notices-screen', title: 'Open Source Notices route and content', group: 'Release readiness',
    description: 'Verify the native Help route opens bundled notices and returns cleanly to the same reading session.',
    prepare: ['Launch the exact candidate with a normal document loaded.'],
    steps: ['Open Help → Open Source Notices using the app UI.', 'Inspect that bundled notices content is visible, readable and scrollable to later sections.', 'Return to the reader and verify the same document remains available.'],
    expected: ['The Help route opens the bundled notice content; content is readable and return navigation works.'],
    risk: 'Native UI', app: true
  },
  {
    id: 'human-listening', title: 'Human listening and usability', group: 'Final human gate',
    description: 'After engineering checks pass, listen to identified short excerpts and record only residual perceptual or usability issues.',
    prepare: ['Use the exact candidate and excerpts whose build identity and provenance are recorded.', 'Confirm automated/native blockers have been addressed or explicitly listed before starting.'],
    steps: ['Listen to narrator and multiple character excerpts, including transitions and challenging attribution/pronunciation cases.', 'Use the reader while audio plays: follow text, scroll, seek and change a voice only where that interaction is in scope.', 'Record specific timestamps, heard text, expected text, usability friction and device/output conditions. Avoid a generic quality score without examples.'],
    expected: ['Record the human judgment and unresolved issues explicitly. Human listening does not waive missing timing, continuity, data-integrity or native UI evidence.'],
    risk: 'Human judgment', app: true
  }
];
