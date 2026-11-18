# Read Aloud User Tests

Build the standalone runner on an Apple Silicon Mac with Xcode.

```sh
tools/human_acceptance_native/build.sh "/absolute/handoff/Read Aloud User Tests.app"
```

Put the coordinator's `native-session.json` beside the resulting app. Double-click
**Read Aloud User Tests.app** in Finder. Use **Open Session…** to choose another
session. A tester can start a case with its prepared document, follow the steps,
record their judgment, and quit the test app from the runner. The runner records
closure when macOS reports that the launched process exited. A case can be skipped
without starting it.

The runner saves observations to the session's results file. **Results → Show
Results Folder** opens its directory. **Export Results…** writes a portable schema
3 report. **Import Results…** accepts a schema 3 native or browser export for the
same candidate and fixtures. If entries conflict, choose which values to retain.
Before importing, the runner saves a backup beside its results file. Browser
storage stays in the browser.

## Coordinator checks

```sh
tools/human_acceptance_native/test.sh
"/absolute/handoff/Read Aloud User Tests.app/Contents/MacOS/ReadAloudUserTests" \
  --validate "/absolute/handoff/native-session.json"
```

Validation checks session structure, the QA bundle identifier, the candidate
manifest and App.framework SHA-256 values, and provided files. It does not open
Read Aloud. For a native smoke run, start the runner with
`--session /absolute/handoff/native-smoke-session.json` and specify a disposable
results path in that session. Keep the alternate session beside the fixtures so
its DOCX recovery actions can find the working sample.

The session grants access to the exact QA bundle, declared local document
arguments, and the `READALOUD_TTS_ENGINE` and `HF_HUB_OFFLINE` launch settings.
Read Aloud uses its QA bundle container. Start refuses any already-running copy
with the same bundle identifier so every case starts with its own arguments.
Recovery actions verify the provided DOCX bytes and atomically replace only
`fixtures/imports/recovery-working.docx` in the handoff.

AppKit holds process ownership and UI state on the main thread. A serial file
operation queue validates packages and fixtures and handles explicit file
operations. Each request checks its identity on return, and streaming hash
validation checks a deadline between reads. Launch and Quit display a timeout
while retaining the process operation pending a macOS callback or confirmed exit.
The serial results writer keeps one active atomic write and a single latest
snapshot. Runner shutdown requests normal Quit for its owned app and waits for
the results write. The coordinator still verifies the native launch, intake,
engine, and normal Quit against the exact candidate.
