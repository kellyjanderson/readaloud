import http from 'node:http';
import { createHash, randomUUID } from 'node:crypto';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const maxBodyBytes = 256 * 1024;
const maxEntries = 8;
const failure = (status, message) => Object.assign(new Error(message), { status });

async function readBody(req) {
  let length = 0;
  const chunks = [];
  for await (const chunk of req) {
    length += chunk.length;
    if (length > maxBodyBytes) throw failure(413, 'The request exceeds the lab input limit.');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

async function readJson(req) {
  if (req.headers['content-type']?.split(';')[0] !== 'application/json') throw failure(415, 'Send application/json.');
  const text = await readBody(req);
  try {
    const value = JSON.parse(text);
    if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  } catch {}
  throw failure(400, 'Expected a JSON object.');
}

export async function startLab(engine, { port = 0 } = {}) {
  const workspace = await mkdtemp(join(tmpdir(), 'readaloud-block-handoff-'));
  const sources = new Map();
  const audio = new Map();
  const jobs = new Set();
  let active = false;
  let closing = false;
  let origin;

  async function handle(req, res) {
    const controller = new AbortController();
    const abort = () => { if (!res.writableEnded) controller.abort(); };
    res.once('close', abort);
    const json = (status, value) => {
      if (res.destroyed) return;
      res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      res.end(JSON.stringify(value));
    };
    res.setHeader('x-content-type-options', 'nosniff');
    res.setHeader('content-security-policy', "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; media-src 'self'; base-uri 'none'; frame-ancestors 'none'");
    try {
      if (closing) throw failure(503, 'Lab is shutting down.');
      if (req.headers.host !== new URL(origin).host ||
          (req.headers.origin && req.headers.origin !== origin)) throw failure(403, 'Use the local lab origin.');
      const path = new URL(req.url, origin).pathname;
      if (req.method === 'GET' && path === '/api/voices') {
        json(200, { voices: await engine.listVoices() });
        return;
      }
      if (req.method === 'GET' && path.startsWith('/audio/')) {
        const filename = audio.get(path);
        if (!filename) throw failure(404, 'Audio expired. Render this composition again.');
        const { size } = await stat(filename);
        res.writeHead(200, { 'content-type': 'audio/wav', 'content-length': size, 'cache-control': 'no-store' });
        const stream = createReadStream(filename);
        stream.on('error', e => res.destroy(e));
        res.on('close', () => stream.destroy());
        stream.pipe(res);
        return;
      }
      if (req.method === 'GET') {
        const files = {
          '/': ['index.html','text/html'],
          '/inspector.mjs': ['inspector.mjs','text/javascript'],
          '/composer.mjs': ['composer.mjs','text/javascript'],
          '/composer.css': ['composer.css','text/css']
        };
        if (!Object.hasOwn(files,path)) throw failure(404, 'Unknown file.');
        const [name, type] = files[path];
        const bytes = await readFile(join(root,name));
        res.writeHead(200, { 'content-type': type + '; charset=utf-8', 'cache-control':'no-store' });
        res.end(bytes);
        return;
      }
      const interactive = path === '/analyze';
      if (req.method !== 'POST' || !['/analyze','/api/analyze','/api/render'].includes(path)) throw failure(404, 'Unknown endpoint.');
      if (interactive && (req.headers.origin !== origin || req.headers['content-type']?.split(';')[0] !== 'text/plain')) {
        throw failure(403, 'Open the local inspector to analyze text.');
      }
      const body = interactive ? {text:await readBody(req)} : await readJson(req);
      if (active) throw failure(409, 'Another model operation is running. Retry when it finishes.');
      if (controller.signal.aborted || closing) return;
      active = true;
      jobs.add(controller);
      try {
        if (interactive || path === '/api/analyze') {
          const { text } = body;
          if (typeof text !== 'string' || !text.trim()) throw failure(400, 'Provide source text.');
          if (!text.isWellFormed() || text.length > 16384) throw failure(400, 'Choose a passage up to 16,384 UTF-16 units.');
          if (interactive) {
            res.writeHead(200, { 'content-type':'application/x-ndjson; charset=utf-8', 'cache-control':'no-store' });
            res.flushHeaders();
          }
          const onProgress = event => { if (interactive && !res.destroyed) res.write(JSON.stringify(event) + '\n'); };
          const result = await engine.analyzeText(text, {signal:controller.signal, onProgress});
          controller.signal.throwIfAborted();
          const blocks = new Map();
          for (const b of result.blocks) {
            if (!b.id || blocks.has(b.id) || !Number.isSafeInteger(b.start) || !Number.isSafeInteger(b.end) ||
                b.start < 0 || b.end <= b.start || b.end > text.length || text.slice(b.start,b.end) !== b.text) {
              throw new Error('Analysis produced an invalid source block.');
            }
            blocks.set(b.id,b);
          }
          const sourceId = createHash('sha256').update(JSON.stringify([text,result.blocks])).digest('hex');
          sources.delete(sourceId);
          sources.set(sourceId, blocks);
          if (sources.size > maxEntries) sources.delete(sources.keys().next().value);
          if (interactive) res.end(JSON.stringify({...result.raw, sourceId, blocks:result.blocks}) + '\n');
          else json(200, {...result, sourceId});
          return;
        }
        const blocks = sources.get(body.sourceId);
        if (!blocks) throw failure(409, 'Analyze the source again before submitting this composition.');
        if (!Array.isArray(body.items) || !body.items.length || body.items.length > 16) throw failure(400, 'Choose 1 to 16 ordered blocks.');
        const choices = new Set((await engine.listVoices()).map(v => v.id));
        const turns = body.items.map(item => {
          const block = blocks.get(item?.blockId);
          if (!block || !choices.has(item.voiceId)) throw failure(400, 'Select a source block and a listed voice for every turn.');
          return { text:block.text, voiceId:item.voiceId };
        });
        const id = randomUUID();
        const outputPath = join(workspace, id + '.wav');
        const url = '/audio/' + id + '.wav';
        try {
          const streamProgress = req.headers.accept === 'application/x-ndjson';
          if (streamProgress) {
            res.writeHead(200, { 'content-type':'application/x-ndjson; charset=utf-8', 'cache-control':'no-store' });
            res.flushHeaders();
          }
          const onProgress = event => {
            if (streamProgress && !res.destroyed) res.write(JSON.stringify(event) + '\n');
          };
          const receipt = await engine.renderComposition({ turns, outputPath, signal:controller.signal, onProgress });
          controller.signal.throwIfAborted();
          const file = await stat(outputPath);
          if (!file.isFile() || file.size <= 44) throw new Error('Fish returned no audio samples.');
          audio.set(url, outputPath);
          if (audio.size > maxEntries) {
            const [old, filename] = audio.entries().next().value;
            audio.delete(old);
            await rm(filename, {force:true});
          }
          const result = {...receipt, sourceId:body.sourceId, items:body.items, turns, audioUrl:url};
          if (streamProgress) res.end(JSON.stringify({...result,type:'result'}) + '\n');
          else json(200, result);
        } catch (e) {
          audio.delete(url);
          await rm(outputPath, {force:true});
          throw e;
        }
      } finally {
        jobs.delete(controller);
        active = false;
      }
    } catch (e) {
      const error = e.message || String(e);
      if (res.headersSent) {
        if (!res.destroyed) res.end(JSON.stringify({ok:false,error}) + '\n');
      } else json(e.status || 422, {error});
    } finally {
      res.off('close', abort);
    }
  }

  const pending = new Set();
  const server = http.createServer((req,res) => {
    const job = handle(req,res);
    pending.add(job);
    job.finally(() => pending.delete(job)).catch(() => res.destroy());
  });
  try {
    await new Promise((accept,reject) => {
      server.once('error', reject);
      server.listen(port, '127.0.0.1', accept);
    });
  } catch (e) {
    await rm(workspace,{recursive:true,force:true});
    throw e;
  }
  origin = 'http://127.0.0.1:' + server.address().port;
  return {
    origin,
    async close() {
      closing = true;
      for (const job of jobs) job.abort();
      const stopped = new Promise(resolve => server.close(resolve));
      server.closeAllConnections();
      await Promise.allSettled([...pending, stopped]);
      await rm(workspace, {recursive:true, force:true});
    }
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const engine = await import('./engine.mjs');
  const lab = await startLab(engine, {port:Number(process.env.NLP_INSPECTOR_PORT ?? 8769)});
  console.log('NLP Inspector listening at ' + lab.origin);
  let stopping;
  const stop = () => { stopping ??= lab.close().catch(e => {console.error(e); process.exitCode=1;}); };
  process.once('SIGINT',stop);
  process.once('SIGTERM',stop);
}
