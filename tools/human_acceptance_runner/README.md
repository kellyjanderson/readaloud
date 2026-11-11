# Read Aloud final user test session

The release coordinator collects the user judgments for S11 under [release #122](https://github.com/kellyjanderson/readaloud/issues/122). The current cases cover quick dialogue in S3 and listening to and editing saved audio books in S6. Add other residual listening or usability cases to `scenarios.js` as their slices identify them. Each case names its source issue so the coordinator can route the findings.

## Prepare the session

After engineering qualification, copy this runner into the handoff folder with the exact packaged candidate and the audio book fixtures. Fill in `candidate.js` in that copy. The runner waits for the app path, full source commit, candidate package SHA-256, and a SHA-256 and instructions for each audio book fixture.

```js
window.HUMAN_ACCEPTANCE_CANDIDATE = {
  appPath: '/absolute/path/to/Read Aloud.app',
  sourceRevision: '<40 lowercase hex characters>',
  packageSha256: '<64 lowercase hex characters>',
  fixtures: {
    'expressive-book': {
      sha256: '<64 lowercase hex characters>',
      instructions: 'Give the book filename and identify the scenes and delivery to listen for.'
    },
    'editable-book': {
      sha256: '<64 lowercase hex characters>',
      instructions: 'Give the book filename, exchange, character and suggested replacement voice.'
    }
  }
};
```

Use a saved, fully rendered book with distinct voices and marked expressive delivery for the first listening case. Use a portable copy with an editable Character and a working replacement voice for the second. Keep the supplied book intact and save changes to a new copy. The coordinator verifies the hashes and qualifies opening time, emitted audio continuity, Save responsiveness, offline reuse, and affected-scene regeneration before handing over the session. The browser records the supplied identity in the report.

## Run the session

1. Open `index.html` in a local browser. Use the app path shown on the page to open the supplied Read Aloud build.
2. Select **Start this test**, then follow the case with its passage or audio book.
3. Choose **It worked for me**, **I noticed a problem**, or **Skip this test**. Add a short note when useful.
4. Quit Read Aloud with **⌘Q** and confirm **Read Aloud is closed** before moving on.
5. Download the results and return the JSON to the release coordinator. Skipped and incomplete cases are identified in the report.

Results are saved in the browser for this candidate. A different package or source revision starts a separate session. Earlier RC2 notes found in the same browser storage are exported separately with their original source revision.
