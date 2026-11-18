import assert from 'node:assert/strict';
import test from 'node:test';
import {writeFile} from 'node:fs/promises';
import {startLab} from './server.mjs';

test('inspector and agents use the identical source blocks, ordered voices and audio', async t => {
  const engine = {
    listVoices: () => [{id:'a',label:'A'},{id:'b',label:'B'}],
    analyzeText: async (text, {onProgress}) => {
      onProgress({type:'progress', completed:1, total:1});
      const blocks = [
        {id:'one',start:0,end:3,text:text.slice(0,3),kind:'narration'},
        {id:'two',start:4,end:7,text:text.slice(4),kind:'dialogue'}
      ];
      return {raw:{ok:true, quotes:[]}, blocks};
    },
    renderComposition: async ({turns, outputPath}) => {
      await writeFile(outputPath,Buffer.alloc(64));
      return {request:{turns}};
    }
  };
  const lab = await startLab(engine);
  t.after(() => lab.close());
  const post = (path, value) => fetch(lab.origin + path, {
    method:'POST', headers:{'content-type':'application/json'},body:JSON.stringify(value)
  });
  const text = 'One Two';
  const analyzed = await (await post('/api/analyze',{text})).json();
  const response = await fetch(lab.origin+'/analyze', {method:'POST',body:text,
    headers:{origin:lab.origin,'content-type':'text/plain; charset=utf-8'}});
  const [progress, interactive] = (await response.text()).trim().split('\n').map(s => JSON.parse(s));
  assert.equal(progress.type,'progress');
  assert.deepEqual(interactive.blocks, analyzed.blocks);
  assert.equal(interactive.sourceId, analyzed.sourceId);
  assert.deepEqual(interactive.quotes, []);
  const items = [{blockId:'two',voiceId:'a'},{blockId:'one',voiceId:'b'}];
  const result = await (await post('/api/render',{sourceId:analyzed.sourceId,items})).json();
  assert.deepEqual(result.turns,[{text:'Two',voiceId:'a'},{text:'One',voiceId:'b'}]);
  assert.deepEqual(result.request.turns, result.turns);
  assert.equal((await fetch(lab.origin + result.audioUrl)).headers.get('content-type'),'audio/wav');
  assert.equal((await post('/api/render',{sourceId:analyzed.sourceId,items:[{blockId:'invented',voiceId:'a'}]})).status,400);
  assert.equal((await post('/api/render',{sourceId:'expired',items})).status,409);
  assert.equal((await fetch(lab.origin+'/api/voices',{headers:{origin:'http://elsewhere.invalid'}})).status,403);
});
