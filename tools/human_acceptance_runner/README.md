# Read Aloud human test session

Open `index.html` in a local browser. The runner shows one short, user-facing test at a time. It provides two dialogue-heavy passages; the tester copies one into Read Aloud with **File → Paste Text**, listens to quick speaker changes, and records a plain-language judgment.

## How to run a session

1. Open the prefilled Read Aloud app from Finder. The page shows the app path and has a **Copy path** button.
2. Select **Start this test**. Copy the story passage shown on the page, paste it into Read Aloud, and follow the simple steps.
3. Choose **It worked for me**, **I noticed a problem**, or **Skip this test**. Add a short note if useful.
4. Quit Read Aloud with **Read Aloud → Quit** or **⌘Q**. When its window is gone, confirm **I quit Read Aloud**. The next test stays locked until then.
5. After the final case, download the results and send them to the person coordinating the test.

The session is about whether fast dialogue is comfortable to follow. It does not ask the tester to measure timings, inspect logs, analyze audio files, or diagnose defects. Those checks belong to engineering. The page cannot launch the native app itself, so it gives the app path and launch instructions.

## Provided passages

The two short, original passages focus on rapid back-and-forth between two speakers and quick turns among three speakers. Dialogue dominates the text, with brief narration only to establish context. The passages are supplied in `passages.js` and do not need to be authored by the tester.

The cases target the residual human judgment in RC2: whether quick speaker changes sound understandable. The earlier completed human-case notes remain in browser storage and are included in the next results download. The voice-choice and follow-along cases have been removed from the human flow.

The objective checks are suitable for engineering automation: test the visible voice controls and follow-along state with UI/controller checks; compare emitted speech with the known transcript and speaker-turn map to detect missing/repeated words, misplaced turn changes, gaps and inconsistent voice routing. ASR and acoustic measurements can flag many defects, but they do not establish whether the voices feel natural or whether the experience is comfortable to follow. The repository does not yet prove that this whole matrix is automated; the two human cases remain focused on that final listening judgment.
