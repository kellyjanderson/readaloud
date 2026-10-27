(() => {
  const scenarios = window.HUMAN_ACCEPTANCE_SCENARIOS;
  const passages = new Map(window.HUMAN_ACCEPTANCE_PASSAGES.map((passage) => [passage.id, passage]));
  const key = 'readaloud-human-acceptance-v2';
  const appPath = '/tmp/readaloud-rc2-final-9ed4532/build/macos/Build/Products/Release/read_aloud.app';
  const sourceRevision = '9ed45329215b8858959eef15509fc2eaf9f1b69f';
  const defaults = { tester: '', results: {}, active: scenarios[0]?.id };
  let state;
  let storageAvailable = true;
  try { state = { ...defaults, ...JSON.parse(localStorage.getItem(key) || '{}') }; }
  catch { state = defaults; storageAvailable = false; }
  if (!state.results || typeof state.results !== 'object' || Array.isArray(state.results)) state.results = {};
  if (!scenarios.some((test) => test.id === state.active)) state.active = defaults.active;

  const byId = new Map(scenarios.map((test) => [test.id, test]));
  const $ = (id) => document.getElementById(id);
  const safeText = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const resultFor = (id) => state.results[id] || { outcome: '', notes: '', appClosed: false, startedAt: '', closedAt: '' };
  const finished = (test) => {
    const result = resultFor(test.id);
    return Boolean(result.outcome && (result.outcome === 'skip' || result.startedAt) && result.appClosed);
  };
  const save = () => {
    try {
      localStorage.setItem(key, JSON.stringify(state));
      storageAvailable = true;
      $('save-status').textContent = 'Saved on this device';
    } catch {
      storageAvailable = false;
      $('save-status').textContent = 'Download your results before closing this page';
    }
    renderList();
  };

  function renderList() {
    $('test-list').innerHTML = scenarios.map((test) => {
      const result = resultFor(test.id);
      const status = finished(test) ? ({ worked: 'Done', problem: 'Problem noted', skip: 'Skipped' })[result.outcome] : result.outcome ? 'Close app' : 'Ready';
      const dot = finished(test) ? (result.outcome === 'worked' ? 'passed' : result.outcome === 'problem' ? 'failed' : 'pending') : 'pending';
      const locked = state.runningCaseId && state.runningCaseId !== test.id;
      return `<li><button class="case-link" data-case="${safeText(test.id)}" aria-current="${state.active === test.id ? 'step' : 'false'}" ${locked ? 'disabled title="Finish and close the active test before moving on"' : ''}><span class="dot ${dot}" aria-hidden="true"></span><span class="case-name">${safeText(test.title)}</span><span class="case-result">${safeText(status)}</span></button></li>`;
    }).join('');
    $('progress-count').textContent = `${scenarios.filter(finished).length} / ${scenarios.length}`;
    document.querySelectorAll('[data-case]').forEach((button) => {
      button.onclick = () => { state.active = button.dataset.case; save(); renderCase(); $('case-title').focus(); };
    });
  }

  function renderCase() {
    const test = byId.get(state.active) || scenarios[0];
    if (!test) return;
    const passage = passages.get(test.passageId);
    const result = resultFor(test.id);
    $('case-content').innerHTML = `
      <div class="case-title-row"><div><p class="case-kicker">TEST ${scenarios.findIndex((item) => item.id === test.id) + 1} OF ${scenarios.length}</p><h2 id="case-title" tabindex="-1">${safeText(test.title)}</h2><p class="case-description">${safeText(test.question)}</p></div></div>
      <div class="start-row"><p>${state.runningCaseId === test.id ? 'This test is underway. Quit Read Aloud when you are finished.' : 'Start this test, then open Read Aloud and follow the steps below.'}</p><button class="button secondary" id="start-test" ${state.runningCaseId ? 'disabled' : ''}>${state.runningCaseId === test.id ? 'Test in progress' : 'Start this test'}</button></div>
      <h3>What to do</h3><ol class="steps">${test.steps.map((step) => `<li>${safeText(step)}</li>`).join('')}</ol>
      <section class="passage-card" aria-labelledby="passage-heading"><div class="passage-heading"><div><p class="eyebrow">PASSAGE PROVIDED</p><h3 id="passage-heading">${safeText(passage.label)}</h3><p>Copy this passage, then paste it into Read Aloud with File → Paste Text.</p></div><button class="button secondary" id="copy-passage" type="button">Copy passage</button></div><label class="sr-only" for="passage-text">Passage text</label><textarea id="passage-text" readonly spellcheck="false">${safeText(passage.text)}</textarea></section>
      <div class="expect"><h3>What to look for</h3><p>${safeText(test.expected)}</p></div>
      <section class="result-area" aria-labelledby="record-heading"><h3 id="record-heading">Your judgment</h3>
        <fieldset class="judgment-options"><legend class="sr-only">How did it go?</legend>${[['worked','It worked for me'],['problem','I noticed a problem'],['skip','Skip this test']].map(([value,label]) => `<label class="result-option"><input type="radio" name="outcome" value="${value}" ${result.outcome === value ? 'checked' : ''}><span>${label}</span></label>`).join('')}</fieldset>
        <label class="notes-label">What stood out? <span class="optional">Optional</span><textarea id="result-notes" placeholder="A short note in your own words">${safeText(result.notes)}</textarea></label>
        <div class="close-check"><input id="app-closed" type="checkbox" ${result.appClosed ? 'checked' : ''}><label for="app-closed"><strong>Read Aloud is closed.</strong> If you opened it, choose Read Aloud → Quit (⌘Q) and make sure its window is gone. If you skipped this test, leave the app closed.</label></div>
        <div class="runner-footer"><p id="record-help" role="status" aria-live="polite">${finished(test) ? 'Your result is saved.' : result.outcome && !result.appClosed ? 'Quit Read Aloud before continuing.' : 'Your result is saved on this device.'}</p><button class="button primary" id="next-case" ${finished(test) ? '' : 'disabled'}>${test.id === scenarios.at(-1).id ? 'Download my results' : 'Continue to next test'}</button></div>
      </section>`;

    $('start-test').addEventListener('click', () => {
      if (state.runningCaseId) return;
      state.runningCaseId = test.id;
      state.results[test.id] = { ...resultFor(test.id), appClosed: false, startedAt: new Date().toISOString() };
      save(); renderCase(); $('start-test').focus();
    });
    $('copy-passage').addEventListener('click', async () => {
      const passageBox = $('passage-text');
      try {
        await navigator.clipboard.writeText(passage.text);
        $('copy-passage').textContent = 'Copied';
      } catch {
        passageBox.focus(); passageBox.select();
        $('copy-passage').textContent = 'Text selected';
        $('record-help').textContent = 'Press ⌘C to copy the selected passage, then paste it into Read Aloud.';
      }
    });
    document.querySelectorAll('input[name="outcome"]').forEach((input) => input.addEventListener('change', () => {
      state.results[test.id] = { ...resultFor(test.id), outcome: input.value, updatedAt: new Date().toISOString() };
      save(); renderCase(); document.querySelector(`input[name="outcome"][value="${input.value}"]`)?.focus();
    }));
    $('result-notes').addEventListener('input', (event) => {
      state.results[test.id] = { ...resultFor(test.id), notes: event.target.value };
      save();
    });
    $('app-closed').addEventListener('change', (event) => {
      const closed = event.target.checked;
      if (closed && state.runningCaseId === test.id) state.runningCaseId = null;
      state.results[test.id] = { ...resultFor(test.id), appClosed: closed, closedAt: closed ? new Date().toISOString() : '' };
      save(); renderCase(); $('app-closed').focus();
    });
    $('next-case').addEventListener('click', () => {
      if (!finished(test)) return;
      const index = scenarios.findIndex((item) => item.id === test.id);
      if (index === scenarios.length - 1) { downloadResults(); return; }
      state.active = scenarios[index + 1].id;
      save(); renderCase(); $('case-title').focus(); window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  function downloadResults() {
    const report = {
      schema: 2,
      exportedAt: new Date().toISOString(),
      tester: state.tester,
      app: { path: appPath, sourceRevision },
      results: scenarios.map((test) => ({ id: test.id, title: test.title, passage: passages.get(test.passageId).label, result: finished(test) ? resultFor(test.id).outcome : 'incomplete', notes: resultFor(test.id).notes, appClosed: resultFor(test.id).appClosed }))
    };
    const url = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' }));
    const link = document.createElement('a');
    link.href = url; link.download = `read-aloud-human-test-${new Date().toISOString().slice(0, 10)}.json`; link.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  $('build-path').value = appPath;
  $('tester').value = state.tester || '';
  $('tester').addEventListener('input', (event) => { state.tester = event.target.value; save(); });
  $('copy-build-path').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(appPath); $('copy-build-path').textContent = 'Copied'; }
    catch { $('build-path').focus(); $('build-path').select(); $('copy-build-path').textContent = 'Path selected'; }
  });
  $('export-session').addEventListener('click', downloadResults);
  $('reset-session').addEventListener('click', () => {
    if (state.runningCaseId) { window.alert('Quit Read Aloud before resetting this test session.'); return; }
    if (!window.confirm('Clear the saved results from this browser?')) return;
    try { localStorage.removeItem(key); } catch { storageAvailable = false; }
    state = { ...defaults, results: {} }; $('tester').value = ''; renderList(); renderCase();
  });
  renderList(); renderCase();
  if (!storageAvailable) $('save-status').textContent = 'Download your results before closing this page';
})();
