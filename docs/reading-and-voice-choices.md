# Reading and voice choices

The reader separates document preparation, voice-resource preparation and audio buffering. A visible document does not mean speech is ready. Play becomes eligible after document preparation; playback waits for prepared voices and enough finalized audio ahead. Short documents may start when all their remaining audio is ready.

## Current and Pending voices

Open **Character Voices** to manage narrator/cast assignments, or **Voice options** in single-voice mode. Assignment fields show requested choices. The footer keeps **Current** playback choices separate from **Pending** intent and reports preparing, applying or failure. Automatic speaker routing follows the prepared cast; it is separate from editing a voice assignment. Attribution remains heuristic, and selecting a voice does not correct a mistaken speaker attribution.

Changing a voice during active playback records pending intent and leaves current audio playing. Choose **Apply and replay current chunk** when ready to change playback. The app stops, prepares and buffers the latest choices, then replays from the current audible chunk's start. Some words may repeat. This is an explicit replay/rebuffer operation; seamless replacement of the future audio queue is not promised.

If playback is paused, the next **Play** applies pending choices from the retained chunk start and can repeat part of that chunk. Pause/resume without a voice edit retains ordinary resume behavior. A newer jump/navigation replaces the retained replay anchor, so applying pending choices does not undo your later navigation. During initial buffering, rapid edits automatically supersede older choices; there is no additional Apply step before the first audio. **Current** changes only after the current engine request is acknowledged. A failed change keeps its requested intent visible; use **Retry voice change** or choose another voice.

Voice preview is a separate action and pauses reader playback when needed. Installing an optional voice downloads it for local use; it does not establish correct speaker attribution or perceptual quality.

## Saving audio and feedback

A new **Save Audio** request is refused while voice choices are pending. Apply the choices first, then save. An export already dispatched uses its captured document/voice context; it does not silently incorporate later requested choices. Resource replacement cancels and drains incompatible export work.

Voice Management scrolls its voice list while keeping assignment feedback separate. **Close voice management** returns to the reader. Reader status messages remain underneath modal dialogs; after closing a dialog, **Dismiss status message** removes the retained message. The named actions have bounded native UI evidence; native Escape dismissal is not yet verified.

## Verification boundary

This guide describes P4 source behavior in production lineage `295677e`. Source tests, bounded earlier native resource/playback evidence and the [modal/status smoke](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395513249) support different parts of the implementation. The [accepted native resource/cache cases](https://github.com/kellyjanderson/readaloud/issues/53#issuecomment-6395918850) establish stale binding rejection, content changes, publication validation and balanced native resource closure on a bounded fixture. Automated assignment replay/startup/pin observations are recorded, but human listening, supplemental failures, export-input/frame acceptance and terminal P4 acceptance remain pending in [P4](https://github.com/kellyjanderson/readaloud/issues/53) and [FINAL](https://github.com/kellyjanderson/readaloud/issues/54). No installed-release acceptance is implied. `.radoc` files are write-only inspection exports; reopening them is not supported by a reload decoder.
