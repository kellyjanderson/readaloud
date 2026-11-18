const ids = [
  "blocks", "block-guide", "blocks-empty", "block-count", "composition", "composition-empty",
  "composition-status", "item-count", "voice-status", "retry-voices", "drop-target", "drop-tail",
  "render", "cancel-render", "render-status", "render-progress", "audio", "request-preview", "receipt",
];
const ui = Object.fromEntries(ids.map((id) => [id, document.getElementById(id)]));

const maxItems = 16;
const dragType = "application/x-readaloud-block";
let source = null;
let voices = [];
let items = [];
let nextItemId = 0;
let localDrag = null;
let revealSourceBlock;
let currentAudioUrl = null;

// Each lane owns at most one outstanding request. Replacing the controller
// invalidates both success and failure before transport cancellation starts.
const requests = new Map();
function begin(lane) {
  cancel(lane);
  const request = new AbortController();
  requests.set(lane, request);
  return request;
}

function cancel(lane) {
  const request = requests.get(lane);
  requests.delete(lane);
  request?.abort();
}

function owns(lane, request) {
  return requests.get(lane) === request;
}

async function api(path, signal, data) {
  const options = {signal};
  if (data !== undefined) {
    options.method = "POST";
    options.headers = {"Content-Type": "application/json"};
    options.body = JSON.stringify(data);
  }
  const response = await fetch(path, options);
  const value = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(typeof value?.error === "string" ? value.error : "Request failed (HTTP " + response.status + ").");
  }
  if (!value) throw new Error("The server returned an unreadable response.");
  return value;
}

function status(id, message, state = "") {
  ui[id].textContent = message;
  ui[id].dataset.state = state;
}

function renderRequest() {
  return {
    sourceId: source.sourceId,
    items: items.map(({blockId, voiceId}) => ({blockId, voiceId})),
  };
}

function syncRenderControls() {
  const busy = requests.has("render");
  ui.render.disabled = busy || !source || !items.length || !voices.length ||
    items.some(({voiceId}) => !voices.some(({id}) => id === voiceId));
  ui["cancel-render"].disabled = !busy;
  ui["render-progress"].hidden = !busy;
  ui["request-preview"].textContent = source
    ? JSON.stringify(renderRequest(), null, 2)
    : "Analyze a passage to start a render request.";
}

function discardAudio() {
  currentAudioUrl = null;
  if (ui.audio.hasAttribute("src")) {
    ui.audio.pause();
    ui.audio.removeAttribute("src");
    ui.audio.load();
  }
  ui.audio.hidden = true;
  ui.receipt.textContent = "A completed render will appear here.";
}

function compositionChanged() {
  cancel("render");
  discardAudio();
  const message = items.length ? "Ready to render the composition." : "Add blocks to prepare an audition.";
  status("render-status", voices.length || !items.length ? message : "Load voices to render the composition.");
  syncRenderControls();
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function button(label, name, handleClick) {
  const node = element("button", "", label);
  node.type = "button";
  node.setAttribute("aria-label", name);
  node.addEventListener("click", handleClick);
  return node;
}

function blockCard(block, position) {
  const card = element("li", "block");
  const heading = element("div", "block-header");
  const name = position === undefined ? "Block " + block.number : position + ". Block " + block.number;
  heading.append(element("span", "", name));
  const attribution = [block.kind, block.speaker].filter(Boolean).join(" · ");
  if (attribution) heading.append(element("span", "", attribution));
  const offsets = "Window offsets " + block.start + "–" + block.end;
  card.append(heading, element("p", "provenance", offsets), element("p", "excerpt", block.text));
  return card;
}

function showBlocks() {
  const blocks = source ? [...source.blocks.values()] : [];
  ui["blocks-empty"].hidden = blocks.length > 0;
  ui["blocks-empty"].textContent = source ? "No source blocks were returned." : "Analyze a passage to see its blocks.";
  ui["block-count"].textContent = blocks.length + (blocks.length === 1 ? " block" : " blocks");
  const cards = document.createDocumentFragment();
  for (const block of blocks) {
    const card = blockCard(block);
    card.dataset.blockId = block.id;
    const controls = element("div", "controls");
    const reveal = button("Show in source", "Show block " + block.number + " in source", () => revealSourceBlock(block));
    const add = button("Add", "Add block " + block.number, () => addBlock(block.id));
    add.dataset.addBlock = "";
    controls.append(reveal, add);
    card.append(controls);
    makeDraggable(card, {blockId: block.id});
    cards.append(card);
  }
  ui.blocks.replaceChildren(cards);
  syncAddControls();
}

function syncAddControls() {
  const atLimit = items.length >= maxItems;
  for (const card of ui.blocks.children) {
    card.draggable = !atLimit;
    card.querySelector("[data-add-block]").disabled = atLimit;
  }
  const guide = ui["block-guide"];
  guide.textContent = atLimit ? "Composition is full (" + maxItems + " items). Remove an item to add another." :
    "Use Show in source to locate a block. Use Add or drag to compose.";
}

function showComposition(focusItemId, focusAction) {
  const cards = document.createDocumentFragment();
  let focusTarget;
  items.forEach((item, index) => {
    const block = source.blocks.get(item.blockId);
    const card = blockCard(block, index + 1);
    card.dataset.itemId = item.id;
    card.draggable = true;
    makeDraggable(card, {itemId: item.id});

    const voice = element("select");
    voice.setAttribute("aria-label", "Voice for item " + (index + 1) + ", block " + block.number);
    for (const entry of voices) {
      const option = element("option", "", entry.label);
      option.value = entry.id;
      voice.append(option);
    }
    if (!voices.length) voice.append(element("option", "", "Voices unavailable"));
    voice.disabled = !voices.length;
    if (voices.length) voice.value = item.voiceId;
    voice.addEventListener("change", () => {
      item.voiceId = voice.value;
      compositionChanged();
    });

    const label = element("label", "", "Voice");
    label.append(voice);
    const controls = element("div", "controls");
    const up = button("Up", "Move item " + (index + 1) + " up", () => moveItem(item.id, index - 1, "up"));
    const down = button("Down", "Move item " + (index + 1) + " down", () => moveItem(item.id, index + 1, "down"));
    const remove = button("Remove", "Remove item " + (index + 1), () => removeItem(index));
    up.disabled = index === 0;
    down.disabled = index === items.length - 1;
    controls.append(label, up, down, remove);
    card.append(controls);
    cards.append(card);
    if (item.id === focusItemId) {
      const requested = {up, down, remove}[focusAction];
      focusTarget = requested && !requested.disabled ? requested : remove;
    }
  });
  ui.composition.replaceChildren(cards);
  ui["composition-empty"].hidden = items.length > 0;
  ui["item-count"].textContent = items.length + (items.length === 1 ? " item" : " items");
  focusTarget?.focus();
}

function addBlock(blockId, index = items.length) {
  if (!source?.blocks.has(blockId) || items.length >= maxItems) return;
  items.splice(index, 0, {id: ++nextItemId, blockId, voiceId: voices[0]?.id ?? ""});
  showComposition();
  const focusedAddBecameDisabled = items.length === maxItems && ui.blocks.contains(document.activeElement);
  syncAddControls();
  if (focusedAddBecameDisabled) ui.composition.children[index].querySelector(".controls button:last-child").focus();
  compositionChanged();
  status("composition-status", "Added block " + source.blocks.get(blockId).number + " at item " + (index + 1) + ".");
}

function moveItem(itemId, index, focusAction) {
  const from = items.findIndex(({id}) => id === itemId);
  if (from < 0 || from === index || index < 0 || index >= items.length) return;
  const [item] = items.splice(from, 1);
  items.splice(index, 0, item);
  showComposition(focusAction ? itemId : undefined, focusAction);
  compositionChanged();
  status("composition-status", "Moved item " + (from + 1) + " to position " + (index + 1) + ".");
}

function removeItem(index) {
  items.splice(index, 1);
  const next = items[Math.min(index, items.length - 1)];
  showComposition(next?.id, "remove");
  syncAddControls();
  if (!next) ui.blocks.querySelector("[data-add-block]")?.focus();
  compositionChanged();
  status("composition-status", "Removed item " + (index + 1) + ".");
}

function makeDraggable(card, data) {
  card.addEventListener("dragstart", (event) => {
    if (!card.draggable || !source || !event.dataTransfer) return;
    localDrag = {sourceId: source.sourceId, ...data};
    event.dataTransfer.setData(dragType, JSON.stringify(localDrag));
    event.dataTransfer.effectAllowed = data.itemId === undefined ? "copy" : "move";
    ui["drop-tail"].hidden = false;
  });
  card.addEventListener("dragend", finishDrag);
}

function finishDrag() {
  localDrag = null;
  ui["drop-tail"].hidden = true;
  clearDropHighlight();
}

function clearDropHighlight() {
  ui["drop-target"].querySelector(".drop-active")?.classList.remove("drop-active");
}

function dropDestination(target) {
  return target.closest(".block[data-item-id]") ?? (items.length ? ui["drop-tail"] : ui["composition-empty"]);
}

ui["drop-target"].addEventListener("dragover", (event) => {
  if (!localDrag || !event.dataTransfer?.types.includes(dragType)) return;
  event.preventDefault();
  event.dataTransfer.dropEffect = localDrag.itemId === undefined ? "copy" : "move";
  clearDropHighlight();
  dropDestination(event.target).classList.add("drop-active");
});

ui["drop-target"].addEventListener("dragleave", (event) => {
  if (!ui["drop-target"].contains(event.relatedTarget)) clearDropHighlight();
});

ui["drop-target"].addEventListener("drop", (event) => {
  if (!localDrag || !event.dataTransfer?.types.includes(dragType)) return;
  event.preventDefault();
  const data = localDrag;
  const destination = dropDestination(event.target);
  const target = items.findIndex(({id}) => String(id) === destination.dataset.itemId);
  finishDrag();
  if (data.sourceId !== source?.sourceId) return;
  if (data.itemId === undefined) {
    addBlock(data.blockId, target < 0 ? items.length : target);
  } else {
    moveItem(data.itemId, target < 0 ? items.length - 1 : target);
  }
});

async function loadVoices() {
  const request = begin("voices");
  ui["retry-voices"].hidden = true;
  status("voice-status", "Loading Fish voices…");
  try {
    const result = await api("/api/voices", request.signal);
    if (!owns("voices", request)) return;
    if (!Array.isArray(result.voices) || !result.voices.length) throw new Error("The service returned no Fish voices.");
    voices = result.voices;
    for (const item of items) {
      if (!voices.some(({id}) => id === item.voiceId)) item.voiceId = voices[0].id;
    }
    status("voice-status", "Choose a Fish voice for each item.");
    showComposition();
    compositionChanged();
  } catch (error) {
    if (!owns("voices", request)) return;
    status("voice-status", error.message, "error");
    ui["retry-voices"].hidden = false;
  } finally {
    if (owns("voices", request)) requests.delete("voices");
  }
}

ui["retry-voices"].addEventListener("click", loadVoices);

ui.render.addEventListener("click", async () => {
  if (ui.render.disabled) return;
  const request = begin("render");
  discardAudio();
  status("render-status", "Waiting for Fish Drama 3 to render " + items.length + (items.length === 1 ? " item…" : " items…"));
  syncRenderControls();
  try {
    const result = await api("/api/render", request.signal, renderRequest());
    if (!owns("render", request)) return;
    if (typeof result.audioUrl !== "string" || !result.audioUrl) throw new Error("The render returned no audio URL.");
    const audioUrl = new URL(result.audioUrl, window.location.href);
    if (audioUrl.origin !== window.location.origin) throw new Error("The render returned a nonlocal audio URL.");
    currentAudioUrl = audioUrl.href;
    ui.receipt.textContent = JSON.stringify(result, null, 2);
    ui.audio.src = currentAudioUrl;
    ui.audio.hidden = false;
    status("render-status", "Render complete. Loading the audition…");
  } catch (error) {
    if (owns("render", request)) status("render-status", error.message, "error");
  } finally {
    if (owns("render", request)) {
      requests.delete("render");
      syncRenderControls();
    }
  }
});

ui.audio.addEventListener("loadedmetadata", () => {
  if (currentAudioUrl && ui.audio.currentSrc === currentAudioUrl) {
    status("render-status", "Audio ready. Use the player to listen.");
  }
});

ui.audio.addEventListener("error", () => {
  if (currentAudioUrl && ui.audio.currentSrc === currentAudioUrl && ui.audio.error) {
    status("render-status", "Could not load audition audio. Render the composition again to retry.", "error");
  }
});

ui["cancel-render"].addEventListener("click", () => {
  cancel("render");
  status("render-status", "Render canceled.");
  syncRenderControls();
  ui.render.focus();
});

function showAnalysis(analysis) {
  source = analysis && {
    sourceId: analysis.sourceId,
    blocks: new Map(analysis.blocks.map((block, index) => [block.id, {...block, number: index + 1}])),
  };
  items = [];
  finishDrag();
  showBlocks();
  showComposition();
  compositionChanged();
}

export function createComposer({ revealBlock }) {
  revealSourceBlock = revealBlock;
  window.addEventListener("pagehide", () => {
    for (const lane of requests.keys()) cancel(lane);
    discardAudio();
  });
  window.addEventListener("pageshow", (event) => {
    if (!event.persisted) return;
    compositionChanged();
    if (!voices.length) loadVoices();
  });
  loadVoices();
  return { showAnalysis };
}
