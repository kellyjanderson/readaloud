# Reading and voice choices

The reader separates document preparation, voice-resource preparation and audio buffering. A visible document or prepared range does not mean speech is ready. Preparation can publish ranges progressively, while playback still waits for prepared voices and enough finalized audio ahead. Short documents may start when all their remaining audio is ready. Progress and cancellation/retry feedback describe preparation work; they do not promise a particular time to first speech or uninterrupted playback.

## Progress and activity

Current preparation appears above the document, without a download popup. A percentage means measured work; when a total is unavailable, the app describes the current stage instead of showing a spinning bar. Finishing means the counted work has ended but readiness has not yet been confirmed.

Choose **Activity** for stage counts and diagnostic detail. Active work stays above completed items, which fade away after a few seconds. Failures remain visible with retry controls. **Cancel document** cancels document preparation; model selection/download is controlled separately in Settings.

Select text in the output area to copy a passage, or choose **Copy** to copy the full current message and stage diagnostics, including details outside the visible scroll area. Speech startup messages in Settings are selectable too.

After a synthesis failure, press **Play** to retry from the retained reading position. Completed cached audio remains reusable; incomplete rendered audio is retained separately and is not treated as a completed passage.

Downloaded models remain in Application Support and are reused by normal development and release builds. A rebuild does not clear them. Interrupted downloads reuse completed files and resume remaining work; loading a saved model into memory is a separate step. Intentionally isolated test apps with a different bundle identifier have separate macOS storage.

## Current and Pending voices

The character list includes speakers discovered across all prepared sections, even when the reader is still showing an earlier section. It updates as preparation advances and retains explicit assignments. The discovery summary distinguishes partial preparation from completed analysis. More characters can appear as you listen or scroll; heuristic detection can still miss or misidentify speakers, so completed analysis is not a guarantee of a complete cast.

Narrator and character choices are remembered when you reopen the same unchanged document, including a book whose preparation has not finished. Choosing a voice explicitly keeps that choice even if it matches the current automatic assignment. Use **Use Automatic Assignment** to return that role to automatic selection. Reset is remembered across reopening and is not undone by an older imported choice. If another engine cannot use a selected voice, a compatible fallback is used while the original choice is retained for returning to its engine.

Open **Character Voices** to manage narrator/cast assignments, or **Voice options** in single-voice mode. Assignment fields show requested choices. The footer keeps **Current** playback choices separate from **Pending** intent and reports preparing, applying or failure. Automatic speaker routing follows the prepared cast; it is separate from editing a voice assignment. Attribution remains heuristic, and selecting a voice does not correct a mistaken speaker attribution. The current selector may expose only one available choice for a character; the user-reported limitation is tracked for a future release in [issue #78](https://github.com/kellyjanderson/readaloud/issues/78).

Choosing a narrator or character voice applies it automatically. During playback, the app stops, prepares and buffers the latest choice, then replays from the current audible chunk’s start. Some words may repeat. There is no Apply button; replacement still takes time and is not guaranteed to be seamless.

If playback is paused, the next **Play** applies pending choices from the retained chunk start and can repeat part of that chunk. Without a voice edit, Play resumes from the saved reading word by rebuilding playback; it does not promise continuation at the exact paused audio sample. A newer jump/navigation replaces the retained replay anchor, so applying pending choices does not undo your later navigation. During initial buffering, rapid edits automatically supersede older choices; there is no additional Apply step before the first audio. **Current** changes only after the current engine request is acknowledged. A failed change keeps its requested intent visible; use **Retry voice change** or choose another voice.

Voice preview is a separate action and pauses reader playback when needed. Installing an optional voice downloads it for local use; it does not establish correct speaker attribution or perceptual quality.

## Saving audio and feedback

**Save Audio** prepares the selected voices automatically, including while paused; you do not need to start playback first. An export already dispatched uses its captured document/voice context; it does not silently incorporate later requested choices. Resource replacement cancels and drains incompatible export work.

A complete multi-range checkpoint can supply whole-document audio export, including ranges already consumed by playback. A partially prepared or corrupt checkpoint cannot be saved as a complete book. Export reconstructs the complete prepared graph before planning audio; it does not rerun source analysis.

Voice Management scrolls its voice list while keeping assignment feedback separate. **Close voice management** returns to the reader. Reader status messages remain underneath modal dialogs; after closing a dialog, **Dismiss status message** removes the retained message. The named actions have bounded native UI evidence; native Escape dismissal is not yet verified.

## Opening and reusing documents

The normal **Open Document** picker accepts `.radoc` v1 and v2 files alongside supported source formats. A valid file opens as a document without running ordinary source-import analysis. A malformed or unsupported `.radoc` is refused with guidance to re-export it using a compatible Read Aloud version; the current document is retained.

Read Aloud automatically saves prepared ranges and can reuse a complete checkpoint for unchanged captured text/bytes or a local macOS file with matching filesystem revision metadata. File checks resolve symlinks and use file identity plus high-resolution modification/change times; they do not hash the whole book before opening it. Changed/unavailable metadata causes a miss or retry. This is local filesystem trust, not a portable cryptographic identity. Callback-provided input without a stable revision still misses conservatively; hashing an already-captured input still reads that input before lookup. Partial checkpoints are not complete books. Corruption invalidates the cached generation, and Retry rebuilds from the preserved original source.

Complete-checkpoint `.radoc` export is available through the controller/repository API; this slice adds no save-document UI. Such files open through the normal picker and retain prepared text, speech direction, attribution evidence and explicit cast voice choices. A fresh preference store restores the saved choices; existing local choices take precedence over an older file. Invalid assignment data is refused before changing the document or preferences. External asset files and native synthesis resources are not embedded or restored merely by exporting the graph.

## Verification boundary

RC2 UI and document-intake behavior is integrated through PR #99 on the feature branch; its focused widget coverage includes selection controls and `.radoc` picker success/refusal. The exact John/Maria example exposed a comma-terminated dialogue-tag attribution bug; PR #77 fixes that case and its focused import tests pass. The current status and remaining scope for the [single-choice voice selector report #78](https://github.com/kellyjanderson/readaloud/issues/78) are maintained in its issue block. These source changes and automated checks do not establish acoustic acceptance on the current integrated app build.

The [supplemental native run](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396165816) passed paused pending Play, injected failure/retry, stale startup failure, export cancellation/drain and A/B/A emitted-PCM comparisons, ending with zero native resources and pins. Its controlled assembly wait and frame callbacks do not establish CPU-load responsiveness or input latency. The user listened to an earlier app build and reported John missing from the cast; current integrated-binary A/B/A human listening remains outstanding. Long-run memory stability and permanently hung-native teardown also remain open. [P4](https://github.com/kellyjanderson/readaloud/issues/53) and [FINAL](https://github.com/kellyjanderson/readaloud/issues/54) remain open; no installed-release acceptance is implied.

The picker restore path for `.radoc` is separate from the instrumented `radoc-v2` artifact codec: that codec decodes and re-encodes an immutable inspection snapshot, not the picker’s `ReaderDocument` restore operation. Neither restores native engine resources. RC2 implementation and automated evidence are recorded under [design #83](https://github.com/kellyjanderson/readaloud/issues/83), [persistence #90](https://github.com/kellyjanderson/readaloud/issues/90), and [picker intake #101](https://github.com/kellyjanderson/readaloud/issues/101). Native app, launch timing, release and human audio acceptance remain open; see [FINAL #54](https://github.com/kellyjanderson/readaloud/issues/54).

## Where character choices are stored

Character definitions and selected voices are stored per work in Application Support:
`works/<SHA-256 of the stable work ID>/characters.json`. The file includes its readable
`workId`, character labels and choices. On sandboxed macOS this is under
`~/Library/Containers/com.kellyjanderson.readAloud/Data/Library/Application Support/com.kellyjanderson.readAloud/`.
Existing preference data migrates automatically on first launch of this version.
Global appearance, engine/default voice, bookmarks and last reading position remain
app preferences; models and downloaded voices are separate.

For a fresh character/voice test, quit the app, back up and remove only that work's
`characters.json`, leave `works/migration.json` intact, and reopen the original source.
Other works are unaffected. Opening an exported `.radoc` can restore its embedded
choices. This reset does not delete the prepared-document cache or last reading
position, so it is distinct from a full preparation test. The older build predating
this migration still stores work records in its preference collection.
