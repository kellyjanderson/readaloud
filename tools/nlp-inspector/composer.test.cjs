"use strict";

// Run with Node 20 and a local Chrome installation:
// node --experimental-websocket --test tools/nlp-inspector/composer.test.cjs
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {spawn} = require("node:child_process");
const {mkdtemp, readFile, rm} = require("node:fs/promises");
const {createServer} = require("node:http");
const {tmpdir} = require("node:os");
const {join} = require("node:path");
const {setTimeout: sleep} = require("node:timers/promises");
const {test} = require("node:test");

const chromePath = process.env.CHROME_PATH ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

async function waitFor(probe, description) {
  for (let attempt = 0; attempt < 100; attempt++) {
    const result = await probe();
    if (result) return result;
    await sleep(30);
  }
  throw new Error("Timed out waiting for " + description);
}

async function connectDebugger(port) {
  const url = "http://127.0.0.1:" + port + "/json/list";
  const [page] = await (await fetch(url)).json();
  const socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, {once: true});
    socket.addEventListener("error", reject, {once: true});
  });
  let sequence = 0;
  const pending = new Map();
  socket.addEventListener("message", ({data}) => {
    const response = JSON.parse(data);
    const waiter = pending.get(response.id);
    if (!waiter) return;
    pending.delete(response.id);
    if (response.error) waiter.reject(new Error(response.error.message));
    else waiter.resolve(response.result);
  });
  socket.addEventListener("close", () => {
    for (const waiter of pending.values()) waiter.reject(new Error("Browser closed."));
    pending.clear();
  });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++sequence;
    pending.set(id, {resolve, reject});
    socket.send(JSON.stringify({id, method, params}));
  });
  const evaluate = async (expression) => {
    const result = await send("Runtime.evaluate", {expression, returnByValue: true, awaitPromise: true});
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
    return result.result.value;
  };
  return {send, evaluate};
}

test("browser composes ordered voiced blocks and discards superseded work", {timeout: 15000}, async (t) => {
  const profiles = await mkdtemp(join(tmpdir(), "readaloud-block-ui-"));
  let renderCount = 0;
  let analysisPending;
  let renderPending;
  let lastRequest;
  let renderAccept;
  let lastAnalysis;
  const blocks = [
    {id: "a", start: 0, end: 13, text: "Once in town.", kind: "Narration"},
    {id: "b", start: 14, end: 21, text: "«Hello»", kind: "Dialogue", speaker: "Ada"},
  ];
  const voices = [{id: "v1", label: "Voice one"}, {id: "v2", label: "Voice two"}];
  const files = new Map([
    ["/", ["index.html", "text/html"]],
    ["/composer.css", ["composer.css", "text/css"]],
    ["/composer.mjs", ["composer.mjs", "text/javascript"]],
    ["/inspector.mjs", ["inspector.mjs", "text/javascript"]],
  ]);
  const server = createServer(async (request, response) => {
    const file = files.get(request.url);
    if (file) {
      response.setHeader("Content-Type", file[1]);
      return response.end(await readFile(join(__dirname, file[0])));
    }
    const json = (payload, status = 200) => {
      response.writeHead(status, {"Content-Type": "application/json"});
      response.end(JSON.stringify(payload));
    };
    if (request.url === "/api/voices") return json({voices});
    if (request.url === "/test.wav") {
      // One sample of mono PCM16, sufficient for the native player's metadata path.
      const wave = Buffer.from("524946462600000057415645666d74201000000001000100401f0000803e00000200100064617461020000000000", "hex");
      response.writeHead(200, {"Content-Type": "audio/wav", "Content-Length": wave.length});
      return response.end(wave);
    }
    if (request.method !== "POST") return json({error: "Unknown route"}, 404);
    let body = "";
    for await (const part of request) body += part;
    if (request.url === "/analyze") {
      lastAnalysis = body;
      response.writeHead(200, {"Content-Type": "application/x-ndjson"});
      response.write(JSON.stringify({type: "progress", message: "Analyzing tokens",
        total: 5, completed: 4, unit: "tokens"}) + "\n");
      const finish = (sourceId) => response.end(JSON.stringify({
        ok: true, sourceId, blocks, tokenCount: 5, inferenceSeconds: 1.2,
        quotes: [{startUtf16: 14, endUtf16: 21, entityId: 0}],
        entities: [{entityId: 0, mentions: [{text: "Ada", proper: true, startUtf16: 0, endUtf16: 3}]}],
        linguisticArtifacts: {files: {quotes: "", tokens: ""}},
      }) + "\n");
      if (body === "Obsolete") {
        analysisPending = () => finish("obsolete");
        return;
      }
      return finish("sample");
    }
    const payload = JSON.parse(body);
    if (request.url === "/api/render") {
      lastRequest = payload;
      renderAccept = request.headers.accept;
      renderCount++;
      const result = {
        audioUrl: "/test.wav",
        turns: payload.items.map(({blockId, voiceId}) => ({
          text: blocks.find(({id}) => id === blockId).text,
          voiceId,
        })),
      };
      if (renderCount === 2) return json({error: "Fish budget refused the render."}, 422);
      if (renderCount === 4) return json(result);
      response.writeHead(200, {"Content-Type": "application/x-ndjson; charset=utf-8"});
      const record = (event) => JSON.stringify(event) + "\n";
      const finish = () => response.end(record({type: "result", ...result}));
      response.write(record({type: "progress", stage: "synthesis", message: "Synthesizing",
        completed: 1, total: 2, unit: "turns"}));
      if (renderCount === 1) {
        renderPending = finish;
        return;
      }
      response.write(record({type: "progress", stage: "encoding", message: "Encoding WAV"}));
      return finish();
    }
    return json({error: "Unknown route"}, 404);
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const browser = spawn(chromePath, [
    "--headless", "--no-first-run", "--no-default-browser-check",
    "--remote-debugging-port=0", "--user-data-dir=" + profiles, "about:blank",
  ], {stdio: "ignore"});
  const exited = once(browser, "exit").catch(() => {});
  let driver;
  t.after(async () => {
    if (driver) await driver.send("Browser.close").catch(() => {});
    else browser.kill();
    await exited;
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
    await rm(profiles, {recursive: true, force: true});
  });
  const activePortFile = join(profiles, "DevToolsActivePort");
  const port = await waitFor(async () => (await readFile(activePortFile, "utf8").catch(() => "")).split("\n")[0], "Chrome debugger");
  driver = await connectDebugger(port);
  const {send, evaluate} = driver;
  await send("Page.navigate", {url: "http://127.0.0.1:" + server.address().port});
  const wait = (code) => waitFor(() => evaluate(code), code);
  await wait('document.querySelector("#voice-status")?.textContent.includes("Choose a Fish voice")');

  const input = (text, start = 0, end = 0) => evaluate(`
    document.querySelector("#source").value = ${JSON.stringify(text)};
    document.querySelector("#source").dispatchEvent(new Event("input"));
    document.querySelector("#source").setSelectionRange(${start}, ${end});
    document.querySelector("#run").click();
  `);
  await input("Obsolete");
  await waitFor(() => analysisPending, "first analysis request");
  await wait('document.querySelector("#progress").value === 4');
  await input("Prefix Once in town. «Hello» Suffix", 7, 28);
  await wait('document.querySelector("#blocks").children.length === 2');
  assert.equal(lastAnalysis, "Once in town. «Hello»");
  analysisPending();
  assert.match(await evaluate('document.querySelector("#blocks").textContent'), /Window offsets 14–21«Hello»/);
  assert.match(await evaluate('document.querySelector("#blocks").textContent'), /Dialogue · Ada/);
  assert.equal(await evaluate('document.querySelector("#preview").textContent'), "Once in town. «Hello»");
  assert.equal(await evaluate('document.querySelector("#preview [data-dialogue]").textContent'), "«Hello»");
  assert.equal(await evaluate('document.querySelector("#legend").hidden'), false);
  await evaluate('document.querySelector("#blocks button").click()');
  assert.equal(await evaluate('[...document.querySelectorAll("#preview [data-composition-block]")].map((mark) => mark.textContent).join("")'), "Once in town.");

  await evaluate('document.querySelector("#blocks button[data-add-block]").focus()');
  await send("Input.dispatchKeyEvent", {type: "rawKeyDown", key: " ", code: "Space", windowsVirtualKeyCode: 32});
  await send("Input.dispatchKeyEvent", {type: "keyUp", key: " ", code: "Space", windowsVirtualKeyCode: 32});
  await wait('document.querySelector("#composition").children.length === 1');
  await evaluate(`
    const transfer = new DataTransfer();
    const drag = (selector, type) => document.querySelector(selector)
      .dispatchEvent(new DragEvent(type, {bubbles: true, cancelable: true, dataTransfer: transfer}));
    drag("#blocks li:last-child", "dragstart");
    drag("#composition li:first-child", "dragover");
    drag("#composition li:first-child", "drop");
    document.querySelector("#composition li:first-child select").value = "v2";
    document.querySelector("#composition li:first-child select").dispatchEvent(new Event("change"));
    document.querySelector("#render").click();
  `);
  await waitFor(() => renderPending, "first render request");
  assert.equal(renderAccept, "application/x-ndjson");
  await wait('document.querySelector("#render-status").textContent === "Synthesizing · 1 of 2 turns"');
  assert.equal(await evaluate('document.querySelector("#render-progress").position'), 0.5);
  assert.deepEqual(lastRequest.items, [{blockId: "b", voiceId: "v2"}, {blockId: "a", voiceId: "v1"}]);
  assert.equal(await evaluate('document.querySelector("#render-progress").hidden'), false);
  await evaluate('document.querySelector("[aria-label=\'Move item 1 down\']").click()');
  assert.equal(await evaluate('document.querySelector("#render-progress").hidden'), true);
  renderPending();
  await evaluate('document.querySelector("#render").click()');
  await wait('document.querySelector("#render-status").textContent.includes("Fish budget refused")');
  assert.equal(await evaluate('document.querySelector("#audio").hidden'), true);

  await evaluate('document.querySelector("#render").click()');
  await wait('document.querySelector("#audio").readyState >= 1');
  assert.equal(await evaluate('document.querySelector("#audio").paused'), true);
  assert.deepEqual(JSON.parse(await evaluate('document.querySelector("#request-preview").textContent')), {
    sourceId: "sample",
    items: [{blockId: "a", voiceId: "v1"}, {blockId: "b", voiceId: "v2"}],
  });
  assert.deepEqual(JSON.parse(await evaluate('document.querySelector("#receipt").textContent')).turns, [
    {text: "Once in town.", voiceId: "v1"},
    {text: "«Hello»", voiceId: "v2"},
  ]);
  assert.equal(await evaluate('document.querySelector("#composition li:last-child select").value'), "v2");
  await evaluate('document.querySelector("#render").click()');
  await wait('document.querySelector("#audio").readyState >= 1');
  assert.equal(renderCount, 4);
  assert.equal(JSON.parse(await evaluate('document.querySelector("#receipt").textContent')).audioUrl, "/test.wav");
  await send("Emulation.setDeviceMetricsOverride", {width: 320, height: 680, deviceScaleFactor: 1, mobile: true});
  assert.equal(await evaluate('document.documentElement.scrollWidth === document.documentElement.clientWidth'), true);
  await evaluate('document.querySelector("[aria-label=\'Remove item 2\']").click()');
  assert.equal(await evaluate('document.querySelector("#audio").hidden'), true);
});
