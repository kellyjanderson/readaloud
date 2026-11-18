const byId = (id) => document.getElementById(id);
const file = byId('file'), source = byId('source'), run = byId('run'), stop = byId('stop');
const previous = byId('previous'), next = byId('next'), position = byId('position');
const preview = byId('preview'), quotes = byId('quotes'), entities = byId('entities');
const status = byId('status'), progress = byId('progress'), save = byId('save');
const legend = byId('legend'), layers = byId('layers'), key = byId('speaker-key');
const speakerColors = [
  { fill: '#b6d8ff', line: '#175ba0' }, // Blue
  { fill: '#ffd0a0', line: '#994400' }, // Orange
  { fill: '#d9c3f5', line: '#633397' }, // Purple
  { fill: '#b0e5d0', line: '#006f58' }, // Teal
  { fill: '#f6b8c3', line: '#ac2547' }, // Rose
  { fill: '#f6e28f', line: '#756000' }, // Gold
];
const neutralSpeaker = { fill: '#d8dde5', line: '#4c5769' };
const limits = { window: 6500, fileBytes: 8 * 1024 * 1024 };
let passages = [''], index = 0, name = '', revision = 0, request = null, result = null;
let highlighted = [], selected = null;
const baselineFill = '#e0e2e5';
const activeLayers = new Set(['dialogue', 'mention', 'evidence']);
for (const [type, label] of Object.entries({
  dialogue: 'Dialogue fill', mention: 'Person mentions (dotted)',
  evidence: 'Speaker evidence (underline)', baseline: 'Baseline quotes (gray)',
})) {
  const control = document.createElement('input');
  control.type = 'checkbox';
  control.checked = activeLayers.has(type);
  const wrapper = document.createElement('label');
  wrapper.append(control, label);
  layers.append(wrapper);
  control.addEventListener('change', () => {
    if (control.checked) activeLayers.add(type);
    else activeLayers.delete(type);
    renderHighlight();
  });
}

function updateControls() {
  run.disabled = request !== null || !source.value.trim();
  stop.disabled = request === null;
  previous.disabled = index === 0;
  next.disabled = index === passages.length - 1;
  save.disabled = result === null;
  position.textContent = name || passages.length > 1
    ? `${name || 'Pasted text'} · passage ${index + 1} of ${passages.length}` : '';
}
function report(message, error = false, counts = null) {
  status.textContent = message;
  status.parentElement.classList.toggle('error', error);
  progress.hidden = !counts;
  if (counts?.total > 0) {
    progress.max = counts.total;
    progress.value = counts.completed;
  } else progress.removeAttribute('value');
}
function clearResult() {
  revision++;
  request?.abort();
  request = null;
  result = null;
  selected = null;
  highlighted = [];
  legend.hidden = true;
  preview.replaceChildren();
  quotes.replaceChildren();
  entities.replaceChildren();
  byId('coverage').textContent = '';
  byId('summary').textContent = 'Quote ranges and proposed speakers will appear here.';
}
function splitPassages(text) {
  const result = [];
  let cursor = 0;
  while (text.length - cursor > limits.window) {
    const cap = cursor + limits.window;
    const minimum = cursor + Math.floor(limits.window / 2);
    const paragraph = text.lastIndexOf('\n\n', cap - 2);
    const line = text.lastIndexOf('\n', cap - 1);
    const space = text.lastIndexOf(' ', cap - 1);
    let end = paragraph >= minimum ? paragraph + 2 : line >= minimum ? line + 1
      : space >= minimum ? space + 1 : cap;
    if (/[\uD800-\uDBFF]/u.test(text[end - 1])) end--;
    result.push(text.slice(cursor, end));
    cursor = end;
  }
  result.push(text.slice(cursor));
  return result;
}
function showPassage() {
  clearResult();
  byId('editor').open = true;
  source.value = passages[index];
  byId('source-panel').scrollTop = 0;
  byId('output').scrollTop = 0;
  report('Ready to analyze this passage.');
  updateControls();
}
file.addEventListener('change', async () => {
  const selectedFile = file.files[0];
  file.value = '';
  if (!selectedFile) return;
  clearResult();
  updateControls();
  const owner = revision;
  report('Opening text file…');
  try {
    if (selectedFile.size > limits.fileBytes) throw Error('Choose a UTF-8 file of 8 MB or less.');
    const text = new TextDecoder('utf-8', { fatal: true }).decode(await selectedFile.arrayBuffer());
    if (revision !== owner) return;
    passages = splitPassages(text.replace(/\r\n?/g, '\n'));
    index = 0;
    name = selectedFile.name;
    showPassage();
  } catch (error) {
    if (revision === owner) report(`Could not open text file. ${error.message}`, true);
  }
});
previous.addEventListener('click', () => { index--; showPassage(); });
next.addEventListener('click', () => { index++; showPassage(); });
source.addEventListener('input', () => {
  clearResult();
  passages[index] = source.value;
  report('Ready to analyze this passage.');
  updateControls();
});
stop.addEventListener('click', () => {
  clearResult();
  report('Analysis canceled.');
  updateControls();
});

function baseline(text) {
  const speech = /“[^”]+”|«[^»]+»|"[^"]+"/gu;
  const verb = '(?:said|asked|replied|answered|whispered|shouted|murmured|added|called)';
  const person = '([\\p{Lu}][\\p{L}’\'-]*)';
  const after = new RegExp(`^[, .!?—–-]*${person}\\s+${verb}\\b|^[, .!?—–-]*${verb}\\s+${person}\\b`, 'u');
  const before = new RegExp(`\\b${person}\\s+${verb}\\s*[, :—–-]*$`, 'u');
  return [...text.matchAll(speech)].map((match) => {
    const start = match.index, end = start + match[0].length;
    const trailing = after.exec(text.slice(end, end + 100).split('\n', 1)[0]);
    const leading = before.exec(text.slice(Math.max(0, start - 100), start).split('\n').at(-1));
    return { start, end, speaker: trailing?.[1] ?? trailing?.[2] ?? leading?.[1] ?? null };
  });
}

function rows(tsv) {
  if (!tsv) return [];
  const [header, ...data] = tsv.trimEnd().split('\n');
  const keys = header.split('\t');
  return data.map((line) => Object.fromEntries(line.split('\t').map((value, i) => [keys[i], value])));
}

function swatch(style, label) {
  const item = document.createElement('span');
  const sample = document.createElement('span');
  sample.className = 'swatch';
  sample.style.background = style.fill;
  sample.style.borderBottomColor = style.line;
  sample.setAttribute('aria-hidden', 'true');
  item.append(sample, label);
  return item;
}

function renderHighlight(scroll = false) {
  if (!result) return;
  const { text } = result;
  const startMap = new Map(), endMap = new Map();
  for (const span of highlighted) {
    if (!activeLayers.has(span.type) || span.start < 0 || span.end > text.length || span.start >= span.end) continue;
    for (const [map, offset] of [[startMap, span.start], [endMap, span.end]]) {
      if (!map.has(offset)) map.set(offset, []);
      map.get(offset).push(span);
    }
  }
  const offsets = [...new Set([0, text.length, ...startMap.keys(), ...endMap.keys()])].sort((a, b) => a - b);
  const fragment = document.createDocumentFragment(), active = new Set();
  for (let i = 0; i + 1 < offsets.length; i++) {
    const start = offsets[i];
    for (const span of endMap.get(start) ?? []) active.delete(span);
    for (const span of startMap.get(start) ?? []) active.add(span);
    const value = text.slice(start, offsets[i + 1]);
    if (!active.size) {
      fragment.append(value);
      continue;
    }
    const mark = document.createElement('mark');
    const unique = new Set();
    for (const span of active) {
      mark.dataset[span.type] = '';
      if (span.quoteIndex === selected) mark.classList.add('selected');
      unique.add(span.label);
    }
    mark.title = [...unique].join(' · ');
    const fills = [...new Set([...active].map((span) => span.fill).filter(Boolean))];
    if (fills.length) {
      const mixed = [1, 3, 5].map((offset) => Math.round(
        fills.reduce((sum, color) => sum + parseInt(color.slice(offset, offset + 2), 16), 0) / fills.length,
      ).toString(16).padStart(2, '0'));
      mark.style.backgroundColor = '#' + mixed.join('');
    }
    const underlines = [...new Set([...active].map((span) => span.line).filter(Boolean))];
    if (underlines.length > 1) {
      const stops = underlines.map((line, i) =>
        line + ' ' + 100 * i / underlines.length + '% ' + 100 * (i + 1) / underlines.length + '%');
      mark.style.backgroundImage = 'linear-gradient(to right, ' + stops.join(', ') + ')';
      mark.dataset.multiEvidence = '';
    } else if (underlines.length === 1) {
      mark.style.textDecorationColor = underlines[0];
    }
    mark.textContent = value;
    fragment.append(mark);
  }
  preview.replaceChildren(fragment);
  if (scroll) {
    const target = preview.querySelector('.selected[data-dialogue]');
    if (!target) return;
    const panel = byId('source-panel');
    const viewport = panel.getBoundingClientRect();
    const quote = target.getBoundingClientRect();
    if (quote.top < viewport.top || quote.bottom > viewport.bottom) {
      panel.scrollTop += quote.top - viewport.top - 8;
    }
  }
}

function renderResult() {
  const { text, model } = result;
  const speakers = new Set(model.quotes.map((turn) => turn.entityId).filter((id) => id != null));
  const styles = new Map([...speakers].map((id, i) => [id, speakerColors[i] ?? neutralSpeaker]));
  const people = new Map(model.entities.map((entity) => {
    const names = [...new Set(entity.mentions.filter((mention) => mention.proper).map((mention) => mention.text))];
    return [entity.entityId, { ...entity, label: names.slice(0, 3).join(' / ') || entity.mentions[0]?.text || 'Unnamed person',
      style: styles.get(entity.entityId) }];
  }));
  const files = model.linguisticArtifacts.files;
  const rawQuotes = rows(files.quotes);
  const tokens = new Map(rows(files.tokens).map((row) => [row.token_ID_within_document, row]));
  const codepoints = [0];
  for (const character of text) codepoints.push(codepoints.at(-1) + character.length);
  const simple = baseline(text);
  result.baseline = simple;
  const band = (type, start, end, label, style = {}, quoteIndex) =>
    highlighted.push({ type, start, end, label, ...style, quoteIndex });
  for (const item of simple) band('baseline', item.start, item.end, `Baseline quote · ${item.speaker || 'unknown'}`, { fill: baselineFill });
  key.replaceChildren();
  for (const person of people.values()) {
    const label = `${person.label} (#${person.entityId})`;
    if (person.style) key.append(swatch(person.style, label));
    const card = document.createElement('article');
    const heading = document.createElement('strong');
    heading.textContent = label;
    const mentions = document.createElement('p');
    mentions.textContent = person.mentions.map((m) => `${m.text} [${m.startUtf16}–${m.endUtf16}]`).join(' · ');
    card.append(heading, mentions);
    entities.append(card);
    for (const m of person.mentions) band('mention', m.startUtf16, m.endUtf16,
      `Person mention · ${label}`);
  }
  model.quotes.forEach((turn, i) => {
    const person = people.get(turn.entityId);
    const label = person ? `${person.label} (#${person.entityId})` : 'Unknown';
    const raw = rawQuotes[i];
    const evidenceStart = codepoints[Number(tokens.get(raw?.mention_start)?.byte_onset)];
    const evidenceEnd = codepoints[Number(tokens.get(raw?.mention_end)?.byte_offset)];
    const style = person?.style ?? neutralSpeaker;
    band('dialogue', turn.startUtf16, turn.endUtf16, `Dialogue · ${label}`, { fill: style.fill }, i);
    if (Number.isInteger(evidenceStart) && Number.isInteger(evidenceEnd) && evidenceEnd > evidenceStart) {
      band('evidence', evidenceStart, evidenceEnd, `Speaker evidence for quote ${i + 1} · ${label}`, { line: style.line }, i);
    }
    const baselineMatches = simple.filter((item) => item.start < turn.endUtf16 && item.end > turn.startUtf16);
    const baselineLabel = baselineMatches.length === 1 ? baselineMatches[0].speaker || 'Quote found, speaker unknown'
      : baselineMatches.length ? 'Multiple overlapping quotes' : 'No overlapping quote';
    const card = document.createElement('article');
    const button = document.createElement('button');
    button.textContent = text.slice(turn.startUtf16, turn.endUtf16);
    button.setAttribute('aria-label', `Quote ${i + 1}, ${label}. ${button.textContent}`);
    button.addEventListener('click', () => {
      selected = i;
      activeLayers.add('dialogue');
      layers.querySelector('input').checked = true;
      renderHighlight(true);
    });
    const facts = document.createElement('dl');
    for (const [title, value] of [
      ['Model speaker', label], ['Evidence', raw?.mention_phrase || 'None supplied'],
      ['Simple baseline', baselineLabel], ['UTF-16 range', `${turn.startUtf16}–${turn.endUtf16}`],
    ]) {
      const dt = document.createElement('dt'), dd = document.createElement('dd');
      dt.textContent = title;
      dd.textContent = value;
      facts.append(dt, dd);
    }
    card.append(button, facts);
    quotes.append(card);
  });
  const baselineOnly = simple.filter((item) => !model.quotes.some((turn) =>
    item.start < turn.endUtf16 && item.end > turn.startUtf16));
  for (const item of baselineOnly) {
    const card = document.createElement('article');
    card.textContent = `Baseline only · ${text.slice(item.start, item.end)} · ${item.speaker || 'Unknown speaker'} · ${item.start}–${item.end}`;
    quotes.append(card);
  }
  if (model.quotes.some((turn) => !people.has(turn.entityId))) {
    key.append(swatch(neutralSpeaker, 'Unknown speaker'));
  }
  byId('summary').textContent = model.quotes.length
    ? `${speakers.size} model speaker IDs across ${people.size} person clusters. Colors blend where highlights overlap.`
    : 'The model found no dialogue in this passage.';
  byId('coverage').textContent = `${model.quotes.length} model quotes · ${simple.length} baseline quotes`;
  legend.hidden = false;
  renderHighlight();
}

run.addEventListener('click', async () => {
  const start = source.selectionStart, end = source.selectionEnd;
  const text = start === end ? source.value : source.value.slice(start, end);
  if (!text.trim() || text.length > 16_384) {
    report('Select a nonempty passage up to 16,384 UTF-16 units.', true);
    return;
  }
  clearResult();
  const owner = revision;
  const controller = new AbortController();
  request = controller;
  report('Starting local model…', false, {});
  updateControls();
  try {
    const response = await fetch('/analyze', { method: 'POST', body: text, signal: controller.signal,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
    if (!response.ok) throw Error((await response.json()).error);
    let buffer = '', model = null;
    for await (const chunk of response.body.pipeThrough(new TextDecoderStream())) {
      if (revision !== owner) return;
      buffer += chunk;
      const lines = buffer.split('\n');
      buffer = lines.pop();
      for (const line of lines) {
        const event = JSON.parse(line);
        if (event.type === 'progress') {
          const count = event.total == null ? '' : ` · ${event.completed} of ${event.total} ${event.unit}`;
          report(event.message + count + '…', false, event);
        } else if (event.ok) model = event;
        else throw Error(event.error);
      }
    }
    if (revision !== owner) return;
    if (!model) throw Error('The model returned no result.');
    result = { fileName: name, passage: index + 1, selectionOffset: start === end ? 0 : start,
      text, model };
    renderResult();
    byId('editor').open = false;
    report(`Analysis complete · ${model.tokenCount} tokens · ${model.inferenceSeconds.toFixed(1)} s inference.`);
  } catch (error) {
    if (revision === owner) report(error.message, true);
  } finally {
    if (revision === owner) {
      request = null;
      updateControls();
    }
  }
});

save.addEventListener('click', () => {
  const url = URL.createObjectURL(new Blob([JSON.stringify(result, null, 2)], { type: 'application/json' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = `${name || 'passage'}-nlp-${index + 1}.json`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
window.addEventListener('pagehide', () => request?.abort());
updateControls();
