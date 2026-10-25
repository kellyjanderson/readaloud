# Reading and voice choices

The reader separates document preparation, voice-resource preparation and audio buffering. A visible document does not mean speech is ready. Play becomes eligible after document preparation; playback waits for prepared voices and enough finalized audio ahead. Short documents may start when all their remaining audio is ready.

## Current and Pending voices

Open **Character Voices** to manage narrator/cast assignments, or **Voice options** in single-voice mode. Assignment fields show requested choices. The footer keeps **Current** playback choices separate from **Pending** intent and reports preparing, applying or failure. Automatic speaker routing follows the prepared cast; it is separate from editing a voice assignment. Attribution remains heuristic, and selecting a voice does not correct a mistaken speaker attribution.

Changing a voice during active playback records pending intent and leaves current audio playing. Choose **Apply and replay current chunk** when ready to change playback. The app stops, prepares and buffers the latest choices, then replays from the current audible chunk's start. Some words may repeat. This is an explicit replay/rebuffer operation; seamless replacement of the future audio queue is not promised.

If playback is paused, the next **Play** applies pending choices from the retained chunk start and can repeat part of that chunk. Without a voice edit, Play resumes from the saved reading word by rebuilding playback; it does not promise continuation at the exact paused audio sample. A newer jump/navigation replaces the retained replay anchor, so applying pending choices does not undo your later navigation. During initial buffering, rapid edits automatically supersede older choices; there is no additional Apply step before the first audio. **Current** changes only after the current engine request is acknowledged. A failed change keeps its requested intent visible; use **Retry voice change** or choose another voice.

Voice preview is a separate action and pauses reader playback when needed. Installing an optional voice downloads it for local use; it does not establish correct speaker attribution or perceptual quality.

## Saving audio and feedback

A new **Save Audio** request is refused while voice choices are pending. Apply the choices first, then save. An export already dispatched uses its captured document/voice context; it does not silently incorporate later requested choices. Resource replacement cancels and drains incompatible export work.

Voice Management scrolls its voice list while keeping assignment feedback separate. **Close voice management** returns to the reader. Reader status messages remain underneath modal dialogs; after closing a dialog, **Dismiss status message** removes the retained message. The named actions have bounded native UI evidence; native Escape dismissal is not yet verified.

## Verification boundary

This guide describes source at `e18c81d`: the `295677e` P4 behavior plus optional export-assembler injection at `843f6b5` (default unchanged) and a probe-only repair at `e18c81d`. Source tests and native evidence support different claims. The [accepted resource/cache cases](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395918850) establish content identity, publication validation and balanced native closure. The [assignment295 automated observations](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395976458) remain usable, but that run later [failed its listening timeout](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396083722); it is not an overall pass.

The [supplemental native run](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6396165816) passed paused pending Play, injected failure/retry, stale startup failure, export cancellation/drain and A/B/A emitted-PCM comparisons, ending with zero native resources and pins. It was muted and performed no actual UI actions. Input during active export remains blocked, and human listening is still unverified. Frame timing and PCM equality do not establish input latency or audible quality. [P4](https://github.com/kellyjanderson/readaloud/issues/53) and [FINAL](https://github.com/kellyjanderson/readaloud/issues/54) remain open; no installed-release acceptance is implied. `.radoc` files are write-only inspection exports; reopening them is not supported by a reload decoder.
