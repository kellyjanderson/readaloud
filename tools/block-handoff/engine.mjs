import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { access, link, mkdtemp, readFile, realpath, rm, stat } from 'node:fs/promises';
import { homedir, tmpdir, totalmem } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = fileURLToPath(new URL('../..', import.meta.url));
const assets = join(repo, 'assets');
const support = join(homedir(), 'Library', 'Application Support');
const sandboxSupport = join(homedir(), 'Library', 'Containers', 'com.kellyjanderson.readAloud',
  'Data', 'Library', 'Application Support');
const mlxRoots = [sandboxSupport, join(sandboxSupport, 'com.kellyjanderson.readAloud'),
  join(support, 'com.kellyjanderson.readAloud')].map(root => join(root, 'read_aloud', 'mlx-tts'));
const nlpRuntime = join(support, 'ReadAloudProviderQA', 'runtime');
const nlpVersion = '84f1f34f6f0ec7c6e9c558b4371e61ea2354d95b';
const fishModel = 'fish_drama3';
const maxSceneTurns = 16;
const maxSceneChars = 16384;
const maxSourceChars = 16384;
const maxProtocolBytes = 2 * 1024 * 1024;
const maxFishRequestBytes = 64 * 1024;

// One process group at a time for the app's model lane. The caller owns revision
// identity and AbortSignals. No queued or resident jobs survive a request.
let active = false;
async function withEngine(signal, run) {
  signal?.throwIfAborted();
  if (active) throw new Error('A model request is already running. Cancel it or wait for it to finish.');
  active = true;
  try {
    return await run();
  } finally {
    active = false;
  }
}

async function existingPath(paths, available, message) {
  for (const path of paths) {
    if (await available(path)) return path;
  }
  throw new Error(message);
}

async function isFile(path) {
  return (await stat(path).catch(() => null))?.isFile() === true;
}

function executable(path) {
  return access(path, constants.X_OK).then(() => true, () => false);
}

function pythonProcess({ python, args, payload, staging, operation, timeout, signal, onProgress }) {
  signal?.throwIfAborted();
  return new Promise((resolveResult, reject) => {
    const child = spawn(python, ['-B', '-u', ...args], {
      cwd: staging, detached: true, stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, TMPDIR: staging, PYTHONNOUSERSITE: '1', PYTHONDONTWRITEBYTECODE: '1',
        HF_HUB_OFFLINE: '1', TRANSFORMERS_OFFLINE: '1', READALOUD_MEMORY_TELEMETRY: '0' },
    });
    let data = Buffer.alloc(0);
    let diagnostics = Buffer.alloc(0);
    let bytes = 0;
    let result;
    let failure;
    let killTimer;
    const signalGroup = name => {
      if (!child.pid) return;
      try {
        process.kill(-child.pid, name);
      } catch (error) {
        if (error.code !== 'ESRCH') failure = error;
      }
    };
    const stop = error => {
      if (failure) return;
      failure = error;
      signalGroup('SIGTERM');
      killTimer = setTimeout(() => signalGroup('SIGKILL'), 1500);
    };
    const cancel = () => stop(signal.reason ?? new DOMException('Model request cancelled.', 'AbortError'));
    const deadline = setTimeout(() => stop(new Error(`${operation} timed out. Check the local runtime or use a shorter selection.`)), timeout);
    signal?.addEventListener('abort', cancel, { once: true });
    if (signal?.aborted) cancel();
    child.stdout.on('data', chunk => {
      if (failure) return;
      try {
        bytes += chunk.length;
        if (bytes > maxProtocolBytes) throw new Error('Worker output exceeded the transport budget.');
        data = Buffer.concat([data, chunk]);
        let boundary;
        while ((boundary = data.indexOf(10)) !== -1) {
          const message = JSON.parse(data.subarray(0, boundary).toString('utf8'));
          data = data.subarray(boundary + 1);
          if (!message || typeof message !== 'object' || result) throw new Error('Unexpected worker response.');
          if (message.type === 'progress') {
            if (message.requestId !== undefined && message.requestId !== payload.requestId) {
              throw new Error('Worker progress has a different request identity.');
            }
            onProgress?.(message);
            if (failure) return;
          } else if (typeof message.ok === 'boolean') {
            result = message;
          } else {
            throw new Error('Worker omitted a final result status.');
          }
        }
      } catch (error) {
        stop(new Error(`${operation} protocol failed. ${error.message}`));
      }
    });
    child.stderr.on('data', chunk => {
      diagnostics = Buffer.concat([diagnostics, chunk]).subarray(-4096);
    });
    child.stdin.on('error', error => { if (error.code !== 'EPIPE') stop(error); });
    child.on('error', error => stop(new Error(`${operation} could not start ${python}. ${error.message}`)));
    child.on('close', (code, reason) => {
      clearTimeout(deadline);
      clearTimeout(killTimer);
      signal?.removeEventListener('abort', cancel);
      if (failure || code !== 0 || !result || data.length) {
        // If a launcher crashed between spawning and reaping its child, retire
        // every surviving member of the group before removing the staging tree.
        signalGroup('SIGKILL');
        const detail = diagnostics.toString('utf8').trim();
        reject(failure ?? new Error(`${operation} worker exited without a complete result (${reason ?? code}). ${detail}`));
      } else if (!result.ok) {
        reject(new Error(`${operation} failed. ${result.error}`));
      } else {
        resolveResult(result);
      }
    });
    child.stdin.end(`${JSON.stringify(payload)}\n`);
  });
}

function assertValidSource(text) {
  if (typeof text !== 'string' || text.length > maxSourceChars || !text.isWellFormed() || !text.trim()) {
    throw new Error(`MBNLP needs nonblank Unicode text up to ${maxSourceChars} UTF-16 units. Select a shorter passage or fix invalid text.`);
  }
}

function sentenceCuts(text, tokensTsv, tokenCount) {
  const lines = tokensTsv.trimEnd().split('\n');
  const fields = lines.shift().split('\t');
  const indices = ['paragraph_ID', 'sentence_ID', 'byte_onset', 'byte_offset', 'word'].map(name => fields.indexOf(name));
  if (indices.includes(-1) || lines.length !== tokenCount || !tokenCount) {
    throw new Error('MBNLP did not return the expected sentence and token data.');
  }
  const utf16Offset = [0];
  for (const point of text) utf16Offset.push(utf16Offset.at(-1) + point.length);
  const cuts = [];
  let previousSentence;
  let previousEnd = 0;
  for (const line of lines) {
    const values = line.split('\t');
    const [paragraph, sentence, rawStart, rawEnd, word] = indices.map(index => values[index]);
    const start = utf16Offset[Number(rawStart)];
    const end = utf16Offset[Number(rawEnd)];
    if (start === undefined || end === undefined || end <= start
        || start < previousEnd || text.slice(start, end) !== word) {
      throw new Error('MBNLP token offsets do not match the original text.');
    }
    const sentenceKey = `${paragraph}:${sentence}`;
    if (previousSentence !== undefined && sentenceKey !== previousSentence) cuts.push(previousEnd);
    previousSentence = sentenceKey;
    previousEnd = end;
  }
  return cuts;
}

function speakerNames(analysis) {
  const lines = analysis.linguisticArtifacts.files.entities.trimEnd().split('\n');
  const fields = lines.shift().split('\t');
  const indices = ['COREF', 'prop', 'cat', 'text'].map(name => fields.indexOf(name));
  if (indices.includes(-1)) throw new Error('MBNLP did not return expected person-mention types.');
  const nominals = new Map();
  for (const line of lines) {
    const columns = line.split('\t');
    const [id, kind, category, text] = indices.map(index => columns[index]);
    if (kind === 'NOM' && category === 'PER' && !nominals.has(id)) nominals.set(id, text);
  }
  return new Map(analysis.entities.map(entity => [entity.entityId,
    entity.mentions.find(mention => mention.proper)?.text ?? nominals.get(entity.entityId)]));
}

export function projectBlocks(text, analysis) {
  // Sentence changes come from the provider's tokenizer. Its typed quotation
  // ranges own dialogue boundaries, even across a provider sentence boundary.
  const cuts = sentenceCuts(text, analysis.linguisticArtifacts.files.tokens, analysis.tokenCount);
  const quotes = [...analysis.quotes].sort((a, b) => a.startUtf16 - b.startUtf16);
  const speakers = speakerNames(analysis);
  const blocks = [];
  const add = (start, end, kind, entityId) => {
    const raw = text.slice(start, end);
    const content = raw.trim();
    if (!content) return;
    start += raw.length - raw.trimStart().length;
    end = start + content.length;
    const speaker = speakers.get(entityId);
    blocks.push({ id: `${kind}-${start}-${end}`, start, end, text: content, kind,
      ...(entityId != null ? { speakerEntityId: entityId } : {}), ...(speaker ? { speaker } : {}) });
  };
  let cursor = 0;
  let cutIndex = 0;
  for (const { startUtf16: start, endUtf16: end, entityId } of quotes) {
    if (!Number.isInteger(start) || !Number.isInteger(end) || start < cursor || end <= start || end > text.length) {
      throw new Error('MBNLP returned overlapping or invalid quotation ranges. Try a shorter passage.');
    }
    while (cutIndex < cuts.length && cuts[cutIndex] < start) {
      add(cursor, cuts[cutIndex], 'narration');
      cursor = cuts[cutIndex++];
    }
    add(cursor, start, 'narration');
    add(start, end, 'dialogue', entityId);
    cursor = end;
    while (cutIndex < cuts.length && cuts[cutIndex] <= end) cutIndex++;
  }
  for (const cut of cuts.slice(cutIndex)) {
    add(cursor, cut, 'narration');
    cursor = cut;
  }
  add(cursor, text.length, 'narration');
  return blocks;
}

export async function analyzeText(text, { signal, onProgress } = {}) {
  assertValidSource(text);
  return withEngine(signal, async () => {
    const python = await existingPath([process.env.NLP_INSPECTOR_PYTHON ?? process.env.READALOUD_MODERNBOOKNLP_PYTHON
      ?? join(nlpRuntime, 'venv', 'bin', 'python')],
      executable, 'Install the ModernBookNLP runtime or set READALOUD_MODERNBOOKNLP_PYTHON to its isolated Python interpreter.');
    const root = resolve(process.env.NLP_INSPECTOR_ASSETS ?? process.env.READALOUD_MODERNBOOKNLP_ROOT ?? join(nlpRuntime, 'assets'));
    if (!await isFile(join(root, 'runtime.json'))) {
      throw new Error('Prepare the ModernBookNLP assets or set READALOUD_MODERNBOOKNLP_ROOT to the installed asset directory.');
    }
    const requestId = randomUUID();
    const sourceRevision = createHash('sha256').update(text).digest('hex');
    const payload = { schema: 1, requestId, ownerId: 'block-handoff', workId: sourceRevision,
      sourceRevision, analysisRevision: 1, sequence: 0, text };
    const staging = await mkdtemp(join(tmpdir(), 'readaloud-mbnlp-'));
    try {
      const analysis = await pythonProcess({ python: resolve(python), operation: 'ModernBookNLP',
        args: [join(assets, 'modernbooknlp_worker.py'), root, '--serve'], payload, staging,
        timeout: 120000, signal, onProgress });
      signal?.throwIfAborted();
      if (analysis.schema !== 1 || analysis.providerId !== 'modernbooknlp-joint'
          || analysis.providerVersion !== nlpVersion || !analysis.modelIdentity
          || !['requestId', 'ownerId', 'workId', 'sourceRevision', 'analysisRevision', 'sequence']
            .every(key => analysis[key] === payload[key])) {
        throw new Error('MBNLP returned a mismatched request or provider identity. Check the pinned local runtime.');
      }
      return {
        blocks: projectBlocks(text, analysis), sourceRevision, raw: analysis,
        providerId: analysis.providerId, providerVersion: analysis.providerVersion,
        adapterVersion: analysis.adapterVersion, modelIdentity: analysis.modelIdentity,
        tokenCount: analysis.tokenCount, processId: analysis.processId,
        loadSeconds: analysis.loadSeconds, inferenceSeconds: analysis.inferenceSeconds,
      };
    } finally {
      await rm(staging, { recursive: true, force: true });
    }
  });
}

async function readJson(path) {
  return JSON.parse(await readFile(path, 'utf8'));
}

function referenceCache() {
  return resolve(process.env.READALOUD_BLOCK_HANDOFF_REFERENCE_CACHE ?? mlxRoots[1]);
}

export async function listVoices() {
  const libraries = await Promise.all(['voice_library/library.json', 'fish_voice_library.json']
    .map(name => readJson(join(assets, name))));
  const cache = referenceCache();
  const voices = [];
  for (const { id, label, asset, sha256, url } of libraries.flatMap(library => library.voices)) {
    const candidates = [asset && join(repo, asset),
      join(cache, 'voice-library', `${sha256}.${url ? 'mp3' : 'wav'}`)].filter(Boolean);
    for (const path of candidates) {
      const file = await stat(path).catch(() => null);
      if (!file?.isFile() || file.size > 20 * 1024 * 1024) continue;
      const bytes = await readFile(path).catch(() => null);
      if (bytes && createHash('sha256').update(bytes).digest('hex') === sha256) {
        voices.push({ id, label });
        break;
      }
    }
  }
  return voices;
}

export function prepareSceneTurns(turns) {
  if (!Array.isArray(turns) || turns.length < 1 || turns.length > maxSceneTurns) {
    throw new Error(`Select 1 to ${maxSceneTurns} turns for one Fish audition.`);
  }
  let words = 0;
  let chars = 0;
  return turns.map(turn => {
    const { voiceId, text } = turn ?? {};
    if (typeof voiceId !== 'string' || voiceId.length > 80 || !/^library_[a-z0-9_]+$/.test(voiceId)) {
      throw new Error('Assign an available local reference voice to each turn.');
    }
    if (typeof text !== 'string') throw new Error('Each Fish turn needs text.');
    chars += text.length;
    if (chars > maxSceneChars) throw new Error(`Select at most ${maxSceneChars} UTF-16 units for one Fish audition.`);
    if (!text.trim() || !text.isWellFormed() || /<\||\0/.test(text)) {
      throw new Error('Fish turns need nonblank Unicode text without native control markers.');
    }
    const startWord = words;
    words += text.match(/\S+/g).length;
    return { voice: voiceId, text, startWord, endWord: words };
  });
}

async function fishRuntime() {
  if (process.platform !== 'darwin') {
    throw new Error('Fish Drama 3 requires arm64 macOS.');
  }
  const [catalog, checksums] = await Promise.all(['fish_drama_models.json', 'fish_drama_model_checksums.json']
    .map(name => readJson(join(assets, name))));
  const spec = catalog[fishModel];
  if (spec.estimatedPeakBytes > totalmem() * 0.85) {
    throw new Error('This Mac has insufficient physical memory for Fish Drama 3 bf16 native scenes. Use a higher-memory Mac.');
  }
  const interpreters = process.env.READALOUD_MLX_PYTHON ? [process.env.READALOUD_MLX_PYTHON]
    : mlxRoots.map(root => join(root, 'runtime', 'venv', 'bin', 'python'));
  const python = await existingPath(interpreters, executable,
    'Install the local MLX speech runtime or set READALOUD_MLX_PYTHON to its arm64 Python interpreter.');
  const checkpoints = process.env.READALOUD_MLX_TTS_MODEL_PATH ? [process.env.READALOUD_MLX_TTS_MODEL_PATH] : [
    process.env.HF_HUB_CACHE, process.env.HF_HOME && join(process.env.HF_HOME, 'hub'),
    join(homedir(), '.cache', 'huggingface', 'hub'),
    ...mlxRoots.flatMap(root => [join(root, 'models'), join(root, 'runtime-cache', 'hub')]),
  ].filter(Boolean).map(root => join(root, `models--${spec.repo.replace('/', '--')}`, 'snapshots', spec.revision));
  const checkpoint = await existingPath(checkpoints, async path => {
    const files = await Promise.all(Object.entries(checksums.variants[fishModel].files).map(async ([name, expected]) => {
      const file = await stat(join(path, name)).catch(() => null);
      return file?.isFile() && file.size === expected.size;
    }));
    return files.every(Boolean);
  }, `Prepare the complete pinned Fish Drama 3 bf16 snapshot ${spec.revision} and set READALOUD_MLX_TTS_MODEL_PATH to the snapshot directory.`);
  return { python: resolve(python), checkpoint: resolve(checkpoint) };
}

export async function renderComposition({ turns, outputPath, signal, onProgress }) {
  const scene = prepareSceneTurns(turns);
  if (typeof outputPath !== 'string' || !outputPath) throw new Error('Choose a new WAV destination.');
  return withEngine(signal, async () => {
    const { python, checkpoint } = await fishRuntime();
    const destination = resolve(outputPath);
    const parent = await realpath(dirname(destination)).catch(() => null);
    if (!parent) throw new Error('Create the WAV destination folder before rendering.');
    if (await isFile(destination)) throw new Error('The WAV destination already exists. Choose a new filename.');
    const staging = await mkdtemp(join(parent, '.fish-handoff-'));
    const output = join(staging, 'complete.wav');
    const cache = resolve(process.env.READALOUD_BLOCK_HANDOFF_CACHE
      ?? join(homedir(), 'Library', 'Caches', 'ReadAloudBlockHandoff'));
    try {
      const payload = { id: randomUUID(), turns: scene, checkpoint, output,
        referenceCache: referenceCache(), privateCache: join(cache, 'hub'), runtimeMemoryLimitBytes: 85000000000 };
      if (Buffer.byteLength(JSON.stringify(payload)) + 1 > maxFishRequestBytes) {
        throw new Error('The encoded Fish request exceeded 64 KiB. Select a shorter composition.');
      }
      const { result } = await pythonProcess({ python, operation: 'Fish Drama 3',
        args: [fileURLToPath(new URL('engine_fish.py', import.meta.url))], payload, staging,
        timeout: 510000, signal, onProgress });
      signal?.throwIfAborted();
      if (result?.request?.sessionId !== payload.id || result.modelId !== fishModel
          || result.request.outputPath !== output || !Number.isInteger(result.frames) || result.frames <= 0) {
        throw new Error('Fish returned a mismatched render receipt. Retry the selected scene.');
      }
      try {
        // Link only a complete verified WAV. Preserve an existing or concurrently
        // created destination and keep worker artifacts in private staging.
        await link(output, destination);
      } catch (error) {
        if (error.code === 'EEXIST') throw new Error('The WAV destination already exists. Choose a new filename.');
        throw error;
      }
      return { ...result, audioPath: destination };
    } finally {
      await rm(staging, { recursive: true, force: true });
    }
  });
}
