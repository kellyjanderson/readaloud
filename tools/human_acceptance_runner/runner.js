(() => {
  const scenarios = window.HUMAN_ACCEPTANCE_SCENARIOS;
  const key = 'readaloud-human-acceptance-v1';
  const defaults = { metadata: {}, results: {}, active: scenarios[0]?.id };
  let state;
  let storageAvailable = true;
  let loadWarning = '';
  try {
    const saved = localStorage.getItem(key);
    if (saved) {
      try { state = { ...defaults, ...JSON.parse(saved) }; }
      catch { state = defaults; loadWarning = 'Saved session could not be read; a new session is ready.'; }
    } else state = defaults;
  } catch { state = defaults; storageAvailable = false; }
  if (!state.metadata || typeof state.metadata !== 'object' || Array.isArray(state.metadata)) state.metadata = {};
  if (!state.results || typeof state.results !== 'object' || Array.isArray(state.results)) state.results = {};
  if (!scenarios.some((test) => test.id === state.active)) state.active = defaults.active;
  const byId = new Map(scenarios.map((test) => [test.id, test]));
  const $ = (id) => document.getElementById(id);
  const safeText = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const resultsFor = (id) => state.results[id] || { outcome: '', notes: '', evidence: '', appClosed: false, updatedAt: '' };
  const fixtureAbsolute = (relative) => decodeURIComponent(new URL(`../../${relative}`, new URL('.', location.href)).pathname);
  const persist = () => {
    try {
      localStorage.setItem(key, JSON.stringify(state));
      storageAvailable = true;
    $('save-status').textContent = 'Saved on this device';
    } catch {
      storageAvailable = false;
      $('save-status').textContent = 'Autosave unavailable — export results before closing this page';
    }
    renderNav();
  };
  const done = (test) => {
    const result = resultsFor(test.id);
    const executionRecorded = !['pass', 'fail'].includes(result.outcome) || Boolean(result.startedAt);
    return Boolean(result.outcome && executionRecorded && (!test.app || result.appClosed));
  };
  const renderNav = () => {
    $('test-list').innerHTML = scenarios.map((test) => {
      const result = resultsFor(test.id);
      const status = done(test) ? result.outcome : result.outcome ? 'close app' : 'pending';
      const dot = result.outcome === 'pass' && done(test) ? 'passed' : ['fail', 'blocked'].includes(result.outcome) && done(test) ? 'failed' : result.outcome ? 'blocked' : 'pending';
      const locked = state.runningCaseId && state.runningCaseId !== test.id;
      return `<li><button class="case-link" data-case="${safeText(test.id)}" aria-current="${state.active === test.id ? 'step' : 'false'}" ${locked ? 'disabled title="Close the active test app before moving to another case"' : ''}><span class="dot ${dot}" aria-hidden="true"></span><span class="case-name">${safeText(test.title)}</span><span class="case-result">${safeText(status)}</span></button></li>`;
    }).join('');
    const complete = scenarios.filter(done).length;
    $('progress-count').textContent = `${complete} / ${scenarios.length} recorded`;
    document.querySelectorAll('[data-case]').forEach((button) => { button.onclick = () => { state.active = button.dataset.case; persist(); renderCase(); $('case-title').focus(); }; });
  };
  const renderCase = () => {
    const test = byId.get(state.active) || scenarios[0];
    if (!test) return;
    const result = resultsFor(test.id);
    const fixture = test.fixturePath ? fixtureAbsolute(test.fixturePath) : '';
    $('case-content').innerHTML = `
      <div class="case-title-row">
        <div><p class="case-kicker">${safeText(test.group)} · ${safeText(test.id)}</p><h2 id="case-title" tabindex="-1">${safeText(test.title)}</h2><p class="case-description">${safeText(test.description)}</p></div>
        <span class="risk-label">${safeText(test.risk)}</span>
      </div>
      <div class="start-row"><p>${state.runningCaseId === test.id ? 'This test is active. Quit the app and verify its process has exited before leaving this case.' : 'Start the case before launching Read Aloud. Other cases stay locked until this app session is closed.'}</p><button class="button secondary" id="start-test" ${state.runningCaseId ? 'disabled' : ''}>${state.runningCaseId === test.id ? 'Test in progress' : 'Start this test'}</button></div>
      <details class="launch-help"><summary>How to launch this exact app build</summary><ol><li>In Finder, press <kbd>⌘</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd> and paste the app path recorded in Session Setup.</li><li>Open that app bundle, then confirm its build identity before testing.</li><li>Open the document through Read Aloud's normal File → Open Document flow.</li></ol></details>
      ${fixture ? `<h3>Fixture to open in the app</h3><div class="fixture"><code>${safeText(fixture)}</code><button id="copy-fixture" type="button">Copy path</button></div>` : ''}
      <div class="test-grid">
        <div><h3>Before you start</h3><ul class="steps">${test.prepare.map((step) => `<li>${safeText(step)}</li>`).join('')}</ul><h3>Test steps</h3><ol class="steps">${test.steps.map((step) => `<li>${safeText(step)}</li>`).join('')}</ol></div>
        <aside><div class="expect"><h3>Expected result</h3><ul class="steps">${test.expected.map((item) => `<li>${safeText(item)}</li>`).join('')}</ul></div></aside>
      </div>
      <section class="result-area" aria-labelledby="record-heading">
        <h3 id="record-heading">Record this test</h3>
        <fieldset style="border:0;padding:0;margin:0"><legend class="sr-only">Test outcome</legend><div class="result-options">${[['pass','Pass'],['fail','Fail'],['blocked','Blocked'],['not-run','Not run']].map(([value,label]) => `<label class="result-option"><input type="radio" name="outcome" value="${value}" ${result.outcome === value ? 'checked' : ''}><span>${label}</span></label>`).join('')}</div></fieldset>
        <div class="result-fields"><label>What happened? <textarea id="result-notes" placeholder="Observed behavior, timing, or blocker">${safeText(result.notes)}</textarea></label><label>Evidence paths or references <textarea id="result-evidence" placeholder="Capture, log, screenshot, or issue link">${safeText(result.evidence)}</textarea></label></div>
        <div class="close-check"><input id="app-closed" type="checkbox" ${result.appClosed ? 'checked' : ''}><label for="app-closed"><strong>App is closed.</strong> If I launched Read Aloud, I chose Read Aloud → Quit (⌘Q), then confirmed the process exited in Activity Monitor. If I did not launch it, I confirmed this test build is not running. Required before this result counts as recorded.</label></div>
        <div class="runner-footer"><p id="record-help" role="status" aria-live="polite">${done(test) ? 'Result recorded.' : ['pass','fail'].includes(result.outcome) && !result.startedAt ? 'Start the test before recording Pass or Fail.' : 'Quit Read Aloud and verify its process is gone before confirming this case.'}</p><button class="button primary" id="next-case" ${done(test) ? '' : 'disabled'}>${test.id === scenarios.at(-1).id ? 'Export session results' : 'Save and open next test'}</button></div>
      </section>`;
    if ($('copy-fixture')) $('copy-fixture').addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(fixture); $('copy-fixture').textContent = 'Copied'; }
      catch { $('copy-fixture').textContent = 'Select path above'; $('record-help').textContent = 'Clipboard access is unavailable here; select the fixture path and copy it manually.'; }
    });
    $('start-test').addEventListener('click', () => {
      if (state.runningCaseId) return;
      state.runningCaseId = test.id;
      state.results[test.id] = { ...resultsFor(test.id), appClosed: false, startedAt: new Date().toISOString() };
      persist(); renderCase(); $('start-test').focus();
    });
    const update = (patch) => { state.results[test.id] = { ...resultsFor(test.id), ...patch, updatedAt: new Date().toISOString() }; persist(); renderCase(); };
    document.querySelectorAll('input[name="outcome"]').forEach((input) => input.addEventListener('change', () => { const value = input.value; update({ outcome: value }); document.querySelector(`input[name="outcome"][value="${value}"]`)?.focus(); }));
    $('result-notes').addEventListener('input', (event) => { state.results[test.id] = { ...resultsFor(test.id), notes: event.target.value }; persist(); });
    $('result-evidence').addEventListener('input', (event) => { state.results[test.id] = { ...resultsFor(test.id), evidence: event.target.value }; persist(); });
    $('app-closed').addEventListener('change', (event) => {
      if (event.target.checked && state.runningCaseId === test.id) state.runningCaseId = null;
      const checked = event.target.checked;
      update({ appClosed: checked, closedAt: checked ? new Date().toISOString() : '' });
      $('app-closed').focus();
    });
    $('next-case').addEventListener('click', () => {
      if (!done(test)) return;
      const index = scenarios.findIndex((entry) => entry.id === test.id);
      if (index === scenarios.length - 1) { $('export-session').click(); return; }
      state.active = scenarios[Math.min(index + 1, scenarios.length - 1)].id;
      persist(); renderCase(); $('case-title').focus(); window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  };
  const bindMetadata = () => {
    for (const [id, field] of [['build-path','buildPath'], ['source-revision','sourceRevision'], ['tester','tester'], ['device','device']]) {
      $(id).value = state.metadata[field] || '';
      $(id).oninput = (event) => { state.metadata[field] = event.target.value; persist(); };
    }
  };
  $('export-session').addEventListener('click', () => {
    const report = { schema: 1, exportedAt: new Date().toISOString(), session: state.metadata, cases: scenarios.map((test) => ({ id: test.id, title: test.title, status: done(test) ? resultsFor(test.id).outcome : 'incomplete', ...resultsFor(test.id) })) };
    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob); const anchor = document.createElement('a');
    anchor.href = url; anchor.download = `readaloud-acceptance-${new Date().toISOString().replace(/[:.]/g,'-')}.json`; anchor.click(); window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  });
  $('reset-session').addEventListener('click', () => {
    if (state.runningCaseId) { window.alert('Quit Read Aloud and confirm its process has exited before resetting this active test session.'); return; }
    if (!window.confirm('Reset all saved test results and session details on this device? Export first if you need a copy.')) return;
    try { localStorage.removeItem(key); } catch { storageAvailable = false; }
    state = { ...defaults, metadata: {}, results: {} }; bindMetadata(); renderNav(); renderCase();
  });
  bindMetadata(); renderNav(); renderCase();
  if (loadWarning) $('save-status').textContent = loadWarning;
  else if (!storageAvailable) $('save-status').textContent = 'Autosave unavailable — export results before closing this page';
})();
