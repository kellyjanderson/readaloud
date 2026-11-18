#!/usr/bin/env node
// Coordinator tooling: prepare a local manifest; never include private fixtures in Git.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const os = require('node:os');

async function sha256(file) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

async function main() {
  const [input, output] = process.argv.slice(2);
  if (!input || process.argv.length > 4) throw Error('Usage: node tools/prepare_native_user_tests.js HANDOFF_DIRECTORY [OUTPUT_JSON]');
  const root = path.resolve(input);
  const destination = path.resolve(output || path.join(root, 'native-session.json'));
  const handoff = JSON.parse(fs.readFileSync(path.join(root, 'handoff.json'), 'utf8'));
  const packageManifestPath = path.join(root, 'app', 'candidate.json');
  if (await sha256(packageManifestPath) !== handoff.packageSha256) throw Error('Packaged app manifest differs from qualified handoff');
  const candidate = JSON.parse(fs.readFileSync(packageManifestPath, 'utf8'));
  if (candidate.build.inputs.source.commit !== handoff.sourceRevision) throw Error('Source revision mismatch');
  const bundle = candidate.build.bundle;
  if (!/^com\.kellyjanderson\.readAloud\.qa\.[a-f0-9]{32}$/.test(bundle.bundle_identifier)) throw Error('Only a qualified QA profile may be prepared');
  const profile = path.join(os.homedir(), 'Library', 'Containers', bundle.bundle_identifier);
  if (!fs.existsSync(path.join(profile, '.com.apple.containermanagerd.metadata.plist')) || !fs.statSync(path.join(profile, 'Data')).isDirectory()) {
    throw Error('The coordinator must initialize and qualify this QA profile before preparing the user session');
  }
  const stagedInputs = path.join(profile, 'Data', 'Library', 'Application Support', bundle.bundle_identifier, 'qualification', 'native-user-tests-' + handoff.packageSha256.slice(0, 16));
  const binary = bundle.files.find(file => file.path === 'Contents/Frameworks/App.framework/Versions/A/App');
  if (!binary) throw Error('Candidate has no qualified App.framework binary');
  const binaryPath = path.join(handoff.appPath, binary.path);
  if (await sha256(binaryPath) !== binary.sha256) throw Error('Packaged app binary differs from qualified candidate');
  const context = vm.createContext({window: {}});
  for (const file of ['scenarios.js', 'passages.js']) {
    vm.runInContext(fs.readFileSync(path.join(__dirname, 'human_acceptance_runner', file), 'utf8'), context, {timeout: 1000});
  }
  const passages = new Map(context.window.HUMAN_ACCEPTANCE_PASSAGES.map(passage => [passage.id, passage]));
  const generated = path.join(root, 'fixtures', 'native-inputs');
  fs.mkdirSync(generated, {recursive: true});
  for (const passage of passages.values()) {
    fs.writeFileSync(path.join(generated, passage.id + '.txt'), passage.text + '\n');
  }
  const manifests = {'model-workflow': 'model-workflow.json', 'import-workflow': 'import-workflow.json', 'export-workflow': 'export-workflow.json', 'long-book': 'long-book.json'};
  const qualified = {};
  for (const [id, name] of Object.entries(manifests)) {
    const manifest = path.join(root, 'fixtures', name);
    if (await sha256(manifest) !== handoff.fixtures[id].sha256) throw Error('Qualified fixture manifest changed: ' + name);
    qualified[id] = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  }
  const expectedFiles = {
    ...qualified['import-workflow'].files,
    [qualified['import-workflow'].reference]: qualified['import-workflow'].referenceSha256,
    [qualified['export-workflow'].book]: qualified['export-workflow'].bookSha256,
    [qualified['export-workflow'].referenceAudio]: qualified['export-workflow'].referenceAudioSha256,
    [qualified['long-book'].book]: qualified['long-book'].sha256,
    [qualified['model-workflow'].preparationDocument]: qualified['model-workflow'].preparationSha256,
    [qualified['model-workflow'].recoveryInvalid]: qualified['model-workflow'].recoveryInvalidSha256,
    [qualified['model-workflow'].recoveryValid]: qualified['model-workflow'].recoveryValidSha256
  };
  const file = async (label, relative) => {
    const absolute = path.join(root, 'fixtures', relative);
    const actual = await sha256(absolute);
    if (expectedFiles[relative] && expectedFiles[relative] !== actual) throw Error('Qualified input changed: ' + relative);
    return {label, path: absolute, sha256: actual};
  };
  const workshop = await file('Short sample document', 'imports/workshop.txt');
  const large = await file('Long preparation sample', 'imports/preparation-large.txt');
  const invalid = await file('Recoverable error sample', 'imports/recovery-invalid.docx');
  const valid = await file('Replacement for the error sample', 'imports/recovery-valid.docx');
  invalid.label = valid.label = 'Coordinator reference (no action needed)';
  const working = await file('Document to open for the recovery test', 'imports/recovery-working.docx');
  // This disposable input is deliberately replaced by the two setup actions.
  delete working.sha256;
  const shortBook = await file('Short audio book', 'books/fish8-final-dialogue.radoc');
  const baseline = await file('Reference audio', 'audio/dialogue-baseline.wav');
  const fullBook = await file('Chapter 1 and Chapter 2 audio book', 'books/city-chapters-1-2-complete.radoc');
  const imports = await Promise.all(['txt', 'html', 'epub', 'docx'].map(extension => file('Sample document (.' + extension + ')', 'imports/workshop.' + extension)));
  const steps = {
    'cancel-first-play': ['Click Start Test. Read Aloud opens the sample document for you.', 'Press Play promptly. While it is preparing speech, use Cancel pending Play.', 'Wait for preparation to settle, then press Play again and listen. If preparation finishes before you can cancel, record that and skip this case.', 'Use Quit Read Aloud here when finished. Record what you observed.'],
    'installed-model-switch': ['Click Start Test. The correct test app and short sample document open automatically. No profile setup is needed.', 'Open Read Aloud’s Settings. Choose Fish Audio Drama 3 · 8-bit. If Load selected speech engine appears, click it. Wait for Active: this means the model is ready to read.', 'Close Settings, press Play and listen briefly. Pause before switching models.', 'Reopen Settings and choose Fish Audio Drama 3 · 4-bit. Use Load selected speech engine if shown. Watch its status until Active. Changing models should not start speech.', 'Close and reopen Settings. Check that 4-bit is still selected and Active. Close Settings, press Play and listen briefly, then pause.', 'Return to Settings, choose Fish Audio Drama 3 · 8-bit and wait for Active. If either model asks for a download, shows an error or never becomes ready, record what you see; do not download or repair anything.', 'Use Quit Read Aloud here and record whether the controls and model status were clear. You do not need to decide which model sounds better.'],
    'preparation-recovery-keyboard': ['Click Start Test. Read Aloud opens the long preparation sample for you. Make its window narrow; in Reader Options choose larger text, using 1.5× if offered.', 'Use Tab to move between controls and Space to activate them. Open Activity, use Cancel document, and then Retry. Check that cancelled work does not unexpectedly start speech.', 'To try a recoverable error, click Prepare error sample here. Use Show in Finder for Document to open for the recovery test below. In Read Aloud choose File → Open Document, drag the revealed recovery-working.docx into the chooser, and open it. Look for the error and Retry document. Open Activity and use its Copy control to copy the problem; paste it into the notes here.', 'Click Repair sample here. Return to Read Aloud and activate Retry document using Tab and Space. The repaired document should now open normally. The runner changes only this disposable sample; the supplied originals stay intact.', 'Do not change your macOS Reduced Motion setting for this test. If it is already enabled, note whether Activity rows disappear without a fade; otherwise skip that observation.', 'Use Quit Read Aloud, then Start Test to reopen the app and check whether it remembers your Activity choice. Use Quit Read Aloud when finished and record any controls you could not reach with the keyboard.'],
    'fast-two-speaker-dialogue': ['Click Start Test. The two-person conversation opens automatically.', 'Press Play and listen through the conversation. Listen for voices changing at the right time and for skipped, repeated or cut-off words.', 'Use Quit Read Aloud, then record what you heard.'],
    'fast-three-speaker-dialogue': ['Click Start Test. The three-person conversation opens automatically.', 'Press Play and listen through the conversation. Check whether you can keep track of the three people.', 'Use Quit Read Aloud, then record what you heard.'],
    'saved-book-expression': ['Click Start Test. The supplied short audio book opens automatically. Press Play and listen to the whole exchange.', 'Listen to Mara’s first quiet request, Mira’s urgent exclamation, Mara’s final instruction and the narrator’s ending. Narrator: Adrian; Mara: Freya; Mira: Hannah.', 'Use Quit Read Aloud and Start Test to reopen the same book. Listen again and check that the voices remain consistent.', 'Use Quit Read Aloud and record what you heard.'],
    'edited-book-voice': ['Click Start Test. The supplied short audio book opens automatically. Listen to the exchange.', 'In Settings select Fish Audio Drama 3 · 8-bit. If necessary use Load selected speech engine, and wait for Active.', 'Open the Character voice controls. Change only Mara from Freya to Adrian. Narrator Adrian and Mira Hannah should keep their voices. Listen again.', 'Choose File → Save Audio Book and save a new copy in the session’s results folder. Use Results → Show Results Folder to find it. Keep the supplied book unchanged.', 'Open your saved copy through File → Open Document, listen, then use Quit Read Aloud and record whether the voice change was preserved.'],
    'reading-controls-and-voice-reset': ['Click Start Test. The three-person conversation opens automatically. Press Play.', 'Pause, move to another sentence, resume and change reading speed. Check whether the highlighted text follows what you hear.', 'Open Characters, choose a different voice for one character, and listen. Return that character to Automatic and listen again.', 'Use Quit Read Aloud. Record any mismatch between words, highlighting, the displayed voice choice and the voice you heard.'],
    'import-layout-and-ending': ['Click Start Test. The plain-text sample opens automatically. It contains 26 words; the final sentence is “The final lamp went dark.” The title is “Signals at the workshop”, followed by “Checking the lamps”, “We checked the workshop before closing.”, “Check the red lamp.” and “Check the green lamp.”', 'For each HTML, EPUB and DOCX sample below, use Show in Finder. In Read Aloud choose File → Open Document, drag the revealed file into the chooser and open it.', 'For each format, press Play promptly. Scroll through the document and check the headings, list and ending. Record missing or repeated text or confusing differences. Do not wait for all preparation to finish before requesting Play.', 'Use Quit Read Aloud when finished.'],
    'exported-audio-listening': ['Click Start Test. The short audio book opens automatically. Press Play and listen to the complete exchange.', 'In Settings select Fish Audio Drama 3 · 8-bit and use Load selected speech engine if shown. Wait for Active.', 'Choose File → Save Audio. Save a new WAV with a new name in the results folder; keep supplied files unchanged.', 'Use Results → Show Results Folder. Select your WAV in Finder and press Space to play it with Quick Look. Compare it with the app and supplied reference audio, including the final words.', 'Use Quit Read Aloud and record gaps, clicks, different voices, repeated or missing words, or an incomplete ending.'],
    'long-book-final-pass': ['Click Start Test. The complete Chapter 1 and Chapter 2 audio book opens automatically. It plays without loading a speech model.', 'Press Play and listen from the opening through the first 30 minutes, then through the remaining Chapter Two ending. The full reading is 40 minutes 11.5 seconds. Any interval you skip stays untested.', 'At a convenient boundary, pause, use Quit Read Aloud, then Start Test to reopen the book. Check the restored position and recurring voices before continuing.', 'Record the chapter/location and a description of any problem. Do not paste private manuscript text into your notes.', 'Use Quit Read Aloud when finished.']
  };
  const cases = [];
  for (const test of context.window.HUMAN_ACCEPTANCE_SCENARIOS) {
    let files;
    if (test.passageId) files = [await file(passages.get(test.passageId).label, 'native-inputs/' + test.passageId + '.txt')];
    else if (test.id === 'installed-model-switch') files = [workshop];
    else if (test.id === 'preparation-recovery-keyboard') files = [large, working, invalid, valid];
    else if (test.id === 'import-layout-and-ending') files = [...imports, await file('Expected sample text and structure', 'imports/reference.json')];
    else if (test.id === 'long-book-final-pass') files = [fullBook];
    else files = test.id === 'exported-audio-listening' ? [shortBook, baseline] : [shortBook];
    const fixture = handoff.fixtures[test.fixtureId];
    if (manifests[test.fixtureId]) files.push(await file('Coordinator reference (no action needed)', manifests[test.fixtureId]));
    // Positional argv does not grant sandbox file access. Copy only the launch
    // input into this already OS-created QA container; never fabricate a profile.
    const launchCopy = path.join(stagedInputs, test.id, path.basename(files[0].path));
    fs.mkdirSync(path.dirname(launchCopy), {recursive: true});
    fs.copyFileSync(files[0].path, launchCopy, fs.constants.COPYFILE_FICLONE);
    if (await sha256(launchCopy) !== files[0].sha256) throw Error('Staged input differs: ' + test.id);
    const launchFile = {...files[0], path: launchCopy};
    files = [launchFile, ...files.slice(1)];
    cases.push({
      id: test.id, title: test.title, issue: test.issue,
      question: test.question, steps: steps[test.id], expected: test.expected,
      arguments: ['--', launchCopy],
      environment: {READALOUD_TTS_ENGINE: 'fish_drama3_8bit', HF_HUB_OFFLINE: '1'}, files,
      ...(test.id === 'preparation-recovery-keyboard' ? {setupActions: [
        {label: 'Prepare error sample', sourcePath: invalid.path, targetPath: working.path, sha256: invalid.sha256},
        {label: 'Repair sample', sourcePath: valid.path, targetPath: working.path, sha256: valid.sha256}
      ]} : {}),
      ...(fixture ? {fixtureId: test.fixtureId, fixtureSha256: fixture.sha256} : {}),
      ...(test.passageId ? {clipboardText: passages.get(test.passageId).text} : {})
    });
    if (!cases.at(-1).steps) throw Error('Missing native instructions: ' + test.id);
  }
  const session = {
    schema: 1, title: 'Read Aloud user tests', resultsPath: path.join(root, 'results', 'native-user-tests.json'),
    candidate: {appPath: handoff.appPath, bundleIdentifier: bundle.bundle_identifier,
      sourceRevision: handoff.sourceRevision, packageSha256: handoff.packageSha256,
      packageManifestPath, binaryPath, binarySha256: binary.sha256}, cases
  };
  fs.mkdirSync(path.dirname(destination), {recursive: true});
  fs.writeFileSync(destination, JSON.stringify(session, null, 2) + '\n');
  console.log('Prepared ' + cases.length + ' native cases: ' + destination);
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
