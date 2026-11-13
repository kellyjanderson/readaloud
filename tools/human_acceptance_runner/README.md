# Read Aloud final user test session

The release coordinator collects the user judgments for S11 under [release #122](https://github.com/kellyjanderson/readaloud/issues/122). The cases cover cancellation during initial speech preparation, installed-model switching in S7, preparation recovery and keyboard use in S8, quick dialogue in S3, and saved audio books in S6, including complete endings. Run the cancellation case first so other tests have not already warmed the speech model. Each case names its source issue so the coordinator can route the findings.

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
    },
    'model-workflow': {
      sha256: '<64 lowercase hex characters>',
      instructions: 'Name the isolated test profile and its two qualified installed model choices, the short reading document, and the exact recoverable-error document and retry steps. Specify larger text and reduced-motion settings and how to restore the test profile.'
    }
  }
};
```

Use a saved, fully rendered book with distinct voices and marked expressive delivery for the first listening case. Use a portable copy with an editable Character and a working replacement voice for the second. Keep the supplied book intact and save changes to a new copy. The coordinator verifies the hashes and qualifies opening time, emitted audio continuity, Save responsiveness, offline reuse, and affected-scene regeneration before handing over the session. The browser records the supplied identity in the report.

The `model-workflow` hash identifies a supplied manifest/instruction fixture, not model weights. Qualify both installed choices and the recovery path against the exact candidate in an isolated profile before supplying it; include explicit model identities and document filenames in its instructions. Keep the user's normal preferences and model cache intact. These two cases are residual S11 human checks, not claims of native S7/S8 acceptance. If the isolated fixture is unavailable or unqualified, leave those cases unrun until the coordinator supplies it.

## Run the session

1. Open `index.html` in a local browser. Use the app path shown on the page to open the supplied Read Aloud build.
2. Select **Start this test**, then follow the case with its passage or audio book.
3. Choose **It worked for me**, **I noticed a problem**, or **Skip this test**. Add a short note when useful.
4. Quit Read Aloud with **⌘Q** and confirm **Read Aloud is closed** before moving on.
5. Download the results and return the JSON to the release coordinator. Skipped and incomplete cases are identified in the report.

Results are saved in the browser for this candidate. A different package or source revision starts a separate session. Earlier RC2 notes found in the same browser storage are exported separately with their original source revision.

## Final combined session (S11)

Run this session only after the remaining implementation slices and automated/native
checks are ready. The coordinator collects results here once; no intermediate
listening pass is required. The case list also covers transport/following text,
explicit versus Automatic voice selection, shared import adapters, exported audio
and sustained long-book listening. Skips and unlistened intervals stay untested.

The handoff copy of `candidate.js` must additionally name and hash these fixture
manifests. Do not fill them with placeholders or a hash of unrelated content:

- `import-workflow`: matching cleared DOCX/EPUB/HTML/text inputs, title/heading/list
  reference and exact final words, file hashes and steps for incremental reading.
- `export-workflow`: qualified book, marked scene ranges, expected voices and
  export/player instructions; identify original and newly exported files.
- `long-book`: local-only book identity/hash, sustained interval and final-chapter
  route, recurring voice checks and reopen instructions. Private City manuscript
  text and raw recordings remain local; the public report uses locations and
  descriptions rather than manuscript quotations.

All fixture IDs required by the case list are checked before the session opens.
Package/source identity remains exact; a new candidate starts a new session.
This runner collects human observations; it does not certify M3 hardware, measured
startup/response bounds, native PCM parity, notices or release publication.
