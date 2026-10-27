# Read Aloud human test session

Open `index.html` in a local browser. The runner shows one short, user-facing test at a time. It includes the exact story passage for each case; the tester copies it into Read Aloud with **File → Paste Text**, tries the app, and records a plain-language judgment.

## How to run a session

1. Open the prefilled Read Aloud app from Finder. The page shows the app path and has a **Copy path** button.
2. Select **Start this test**. Copy the story passage shown on the page, paste it into Read Aloud, and follow the simple steps.
3. Choose **It worked for me**, **I noticed a problem**, or **Skip this test**. Add a short note if useful.
4. Quit Read Aloud with **Read Aloud → Quit** or **⌘Q**. When its window is gone, confirm **I quit Read Aloud**. The next test stays locked until then.
5. After the final case, download the results and send them to the person coordinating the test.

The session is about how reading, voices and playback feel to the person using Read Aloud. It does not ask the tester to measure timings, inspect logs, analyze audio files, or diagnose defects. Those checks belong to engineering. The page cannot launch the native app itself, so it gives the app path and launch instructions.

## Provided passages

The runner includes the five frozen, reviewed RC2 prose passages P0–P4 from `test/fixtures/rc2_prose/text/` (352–378 words each). They cover narrator-only reading and stories with one through four speaking characters. The text shown to the tester is the same text covered by the source-level attribution fixtures; the production app receives only the passage text, never the expected cast list.

The cases follow the user-facing part of RC2 acceptance in [issue #83](https://github.com/kellyjanderson/readaloud/issues/83) and the voice-choice report in [issue #78](https://github.com/kellyjanderson/readaloud/issues/78). Technical timing, continuity, `.radoc` integrity and resource checks remain engineering acceptance work.
