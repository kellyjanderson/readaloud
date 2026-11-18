import assert from 'node:assert/strict';
import test from 'node:test';
import { analyzeText, prepareSceneTurns, projectBlocks } from './engine.mjs';

const source = '🌱 Front.\n\n“Why? Listen!” Ada said. “Yes.”';
const analysis = {
  tokenCount: 16,
  quotes: [
    { startUtf16: source.indexOf('“Why'), endUtf16: source.indexOf('”') + 1, entityId: '7' },
    { startUtf16: source.indexOf('“Yes'), endUtf16: source.length, entityId: null },
  ],
  entities: [{ entityId: '7', mentions: [{ text: 'Ada', proper: true }] }],
  linguisticArtifacts: { files: {
    tokens: [
      'paragraph_ID\tsentence_ID\tbyte_onset\tbyte_offset\tword',
      '0\t0\t0\t1\t🌱', '0\t0\t2\t7\tFront', '0\t0\t7\t8\t.',
      '1\t1\t10\t11\t“', '1\t1\t11\t14\tWhy', '1\t1\t14\t15\t?',
      '1\t2\t16\t22\tListen', '1\t2\t22\t23\t!', '1\t2\t23\t24\t”',
      '1\t2\t25\t28\tAda', '1\t2\t29\t33\tsaid', '1\t2\t33\t34\t.',
      '1\t3\t35\t36\t“', '1\t3\t36\t39\tYes', '1\t3\t39\t40\t.', '1\t3\t40\t41\t”',
    ].join('\n'),
    entities: 'COREF\tprop\tcat\ttext\n7\tPROP\tPER\tAda',
  } },
};

test('provider sentences and quotes produce exact UTF-16 blocks across an astral character', () => {
  const blocks = projectBlocks(source, analysis);
  assert.deepEqual(blocks.map(({ kind, text, speaker }) => [kind, text, speaker]), [
    ['narration', '🌱 Front.', undefined],
    ['dialogue', '“Why? Listen!”', 'Ada'],
    ['narration', 'Ada said.', undefined],
    ['dialogue', '“Yes.”', undefined],
  ]);
  for (const block of blocks) assert.equal(source.slice(block.start, block.end), block.text);
});

test('overlapping provider quote offsets fail visibly', () => {
  const quotes = [analysis.quotes[0], { ...analysis.quotes[1], startUtf16: analysis.quotes[0].endUtf16 - 1 }];
  assert.throws(() => projectBlocks(source, { ...analysis, quotes }), /overlapping/);
});

test('Fish scene admission retains order and text beyond 75 words', () => {
  const lengthy = 'long word '.repeat(600);
  assert.deepEqual(prepareSceneTurns([
    { voiceId: 'library_ben', text: lengthy },
    { voiceId: 'library_ava', text: '“Yes.”  ' },
  ]), [
    { voice: 'library_ben', text: lengthy, startWord: 0, endWord: 1200 },
    { voice: 'library_ava', text: '“Yes.”  ', startWord: 1200, endWord: 1201 },
  ]);
});

test('Fish scene admission rejects oversized input and native control markers', () => {
  const turn = text => ({ voiceId: 'library_ava', text });
  assert.throws(() => prepareSceneTurns(Array(17).fill(turn('Hi.'))), /1 to 16/);
  assert.throws(() => prepareSceneTurns([turn('🌱'.repeat(8193))]), /16384 UTF-16/);
  assert.throws(() => prepareSceneTurns([turn('<|speaker:1|> Hi.')]), /control markers/);
});

test('MBNLP rejects blank, oversized and invalid Unicode source before starting Python', async () => {
  for (const invalid of ['   ', '🌱'.repeat(8193), '\ud800']) {
    await assert.rejects(analyzeText(invalid), /16384 UTF-16/);
  }
});
