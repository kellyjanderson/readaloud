# Fish continuity and sandbox export evidence

November 16, 2026 Pacific. Refs #152, #110 R23/R25 and release #122.
This receipt supersedes the earlier locked-screen limitation only for the
specific observations below. It does not certify a later candidate or close
the release. Private manuscripts, recordings and model files remain local.

The ordinary signed arm64 QA app at `9f69510d9d0d4536004e331aed89b4a005d394c3`
(build `33c59264-dd21-4ade-84a1-f6c9067f7626`) used Fish Drama 3 8-bit / Adrian
on Apple M5 Max, 128 GiB, macOS 27.0.1. The latest local Chapter 1 fifth draft
and Chapter 2 first draft were copied without edits from writing commit
`1db5886b3cff8b8d0931f1920ff01ddd6a63232c`; combined input SHA-256 is
`80e89a213cb5c62af2b6dcaa239ec85a67057e7ec359b989bb3310c28f4b3b73`.

The 1,860-second CoreAudio process tap contains **1,841.286854 seconds of
contiguous matching audio across 351 complete scenes**, source words 124–5733.
Minimum active correlation is 0.991002099; maximum absolute external join is
0.020833 ms. Tap timing reports zero dropped buffers, pool overflows, device
overloads, discontinuities, format changes or callback stalls. The prefix and
incomplete tail are uncredited. This is warm partial-book software-output
continuity, not startup, whole-book completion, semantic/voice quality,
physical-speaker or human listening proof. An earlier Kokoro smoke is excluded.
Advancing text, Chapter 2, Pause/Play, import and the notices screen were observed.
Normal Quit and app/worker exit were verified.
[Durable acoustic evidence](https://github.com/kellyjanderson/readaloud/issues/152#issuecomment-6932091405).

The same ordinary build revealed sandbox refusal when audio assembly created a
temporary directory beside the SavePanel-selected file. Foundation replacement
staging and two sequential coordinated publication scopes repair that defect.
Signed Flutter/Fish native tests at `a6fa96efb3bfb1722d08829e0d0734e96a666545`
use the ordinary ReadAloudApp, controller and native FilePicker with a bounded
diagnostic observer. A genuinely new external WAV/JSON pair and explicit
overwrite each passed: five chunks / 1,173,271 frames / 44.1 kHz mono PCM16,
exactly equal to ordered production source PCM, with correct sidecar metadata.
The JSON is the final pair commit marker; the native stage was released.

With JSON coordination deliberately held, a complete WAV existed before Quit
while JSON remained absent. Normal Quit cancelled the pending coordination and
rolled back the WAV; native stage release was logged 378 ms after the Quit
request. App/worker exit was verified while the separate coordination holder
was still alive, then the holder was released. The 378 ms measures stage release,
not app-exit latency. Two earlier held runs prove timeout/rollback only.
All test apps were normally quit and their owned processes verified absent.
[Durable native evidence](https://github.com/kellyjanderson/readaloud/issues/152#issuecomment-6934921294).

Sanitized native source is integrated as `26d0e65`; cache-layout repair and
bounded long-capture audit are integrated as `0780f70` and `b17f8a8`.
The integration passes 1,321 Flutter tests / four optional skips, clean
`tools/flutter analyze lib test tools`, 31 protocol/cache tests, 36 capture
tests, 17 native publication scenarios (2 Ruby tests / 11 assertions), and
filesystem replay/portable-clone checks (2 tests / 14 assertions). These are
source/tool results, distinct from native evidence at the exact commits above.
Root-wide vendored-example analysis retains its earlier 73 diagnostics.

The first-launch two-second goal miss, unavailable physical M3, final ordinary
candidate/package qualification, one combined human session and seven existing
distribution blockers remain explicit. No Actions, paid execution, main merge,
release publication or acceptance waiver occurred. Raw receipts are retained
under the aggregate worktree's ignored `tmp/s11/`; selected identities and limits
are in [native-checks.json](native-checks.json).
