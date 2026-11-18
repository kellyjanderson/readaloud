import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { access, readFile, rm } from 'node:fs/promises';
import { mkdtempSync } from 'node:fs';
import { createServer } from 'node:http';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const runtime = join(homedir(), 'Library/Application Support/ReadAloudProviderQA/runtime');
const python = process.env.NLP_INSPECTOR_PYTHON || join(runtime, 'venv/bin/python');
const assets = process.env.NLP_INSPECTOR_ASSETS || join(runtime, 'assets');
await access(python);
await access(join(assets, 'runtime.json'));

const port = Number(process.env.NLP_INSPECTOR_PORT || 8769);
const origin = `http://127.0.0.1:${port}`;
const workerPath = fileURLToPath(new URL('../../assets/modernbooknlp_worker.py', import.meta.url));
const staticFiles = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/inspector.mjs': ['inspector.mjs', 'text/javascript; charset=utf-8'],
};
const pages = Object.fromEntries(await Promise.all(
  Object.entries(staticFiles).map(async ([path, [file, type]]) =>
    [path, { type, bytes: await readFile(new URL(file, import.meta.url)) }]),
));
let active = null;

function fail(response, code, error) {
  response.writeHead(code, { 'Content-Type': 'application/json' });
  response.end(JSON.stringify({ error }));
}

function analyze(response, source) {
  if (active) return fail(response, 409, 'The previous analysis is still stopping. Try again.');
  const id = randomUUID();
  const scratch = mkdtempSync(join(tmpdir(), 'nlp-inspector-'));
  const child = spawn(python, ['-u', '-B', workerPath, assets, '--serve'],
    { env: { ...process.env, TMPDIR: scratch } });
  active = child;
  const stop = () => child.kill('SIGKILL');
  response.on('close', stop);
  let timedOut = false;
  const deadline = setTimeout(() => {
    timedOut = true;
    stop();
  }, 120_000);
  response.writeHead(200, { 'Content-Type': 'application/x-ndjson; charset=utf-8' });
  response.flushHeaders();
  const emit = (value) => response.write(JSON.stringify(value) + '\n');
  let line = '';
  let final = false;
  child.stdout.setEncoding('utf8').on('data', (chunk) => {
    line += chunk;
    if (line.length > 2 * 1024 * 1024) return stop();
    const records = line.split('\n');
    line = records.pop();
    for (const record of records) {
      try {
        const value = JSON.parse(record);
        if (value.requestId !== id) continue;
        if (value.type !== 'progress') final = true;
        emit(value);
      } catch {
        stop();
      }
    }
  });
  child.stderr.resume();
  let spawnError;
  child.on('error', (error) => { spawnError = error.message; });
  child.stdin.on('error', (error) => { spawnError ||= error.message; });
  child.on('close', async () => {
    clearTimeout(deadline);
    try {
      await rm(scratch, { recursive: true, force: true });
    } catch (error) {
      console.error('Could not remove worker scratch directory:', error.message);
    }
    active = null;
    response.off('close', stop);
    if (response.destroyed) return;
    if (!final) {
      emit({ ok: false, error: timedOut ? 'Analysis timed out after two minutes.'
        : spawnError || 'The model exited before producing a result.' });
    }
    response.end();
  });
  child.stdin.end(JSON.stringify({
    schema: 1, requestId: id, ownerId: 'nlp-inspector', workId: 'local-text-window',
    sourceRevision: createHash('sha256').update(source).digest('hex'),
    analysisRevision: 0, sequence: 0, text: source,
  }) + '\n');
}

const server = createServer(async (request, response) => {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Content-Security-Policy',
    "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'");
  if (request.headers.host !== `127.0.0.1:${port}`) return fail(response, 403, 'Use the local inspector URL.');
  const page = pages[request.url];
  if (request.method === 'GET' && page && Object.hasOwn(pages, request.url)) {
    response.writeHead(200, { 'Content-Type': page.type });
    return response.end(page.bytes);
  }
  if (request.method !== 'POST' || request.url !== '/analyze') return fail(response, 404, 'Page unavailable.');
  if (request.headers.origin !== origin || request.headers['content-type'] !== 'text/plain; charset=utf-8') {
    return fail(response, 403, 'Open the local inspector to analyze text.');
  }
  if (active) return fail(response, 409, 'The previous analysis is still stopping. Try again.');
  try {
    const length = Number(request.headers['content-length']);
    if (length > 64 * 1024) return fail(response, 413, 'Choose a smaller passage.');
    const chunks = [];
    let bytes = 0;
    for await (const chunk of request) {
      bytes += chunk.length;
      if (bytes > 64 * 1024) return fail(response, 413, 'Choose a smaller passage.');
      chunks.push(chunk);
    }
    const source = Buffer.concat(chunks).toString('utf8');
    if (!source.trim() || source.length > 16_384 || !source.isWellFormed()) {
      return fail(response, 400, 'Choose a nonempty passage up to 16,384 UTF-16 units.');
    }
    analyze(response, source);
  } catch (error) {
    if (!response.destroyed && !response.headersSent) fail(response, 400, error.message);
  }
});
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => {
    active?.kill('SIGKILL');
    server.close();
    server.closeAllConnections();
  });
}
server.listen(port, '127.0.0.1', () => console.log(`NLP Inspector listening at ${origin}`));
