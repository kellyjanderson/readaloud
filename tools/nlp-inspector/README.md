# NLP Inspector

Open UTF-8 text or Markdown and inspect the pinned ModernBookNLP output against a small baseline for paired quotation marks and explicit named speech tags. The inspector runs locally. The same analyzed passage supplies the highlight view and selectable Fish Audio Drama 3 blocks. Auditions use the local model and reference voices independently of the reader’s playback queue.

Start from the repository root with Node 20.20 or later.

```sh
node tools/nlp-inspector/server.mjs
```

Open the [inspector](http://127.0.0.1:8769). Choose **Open text file** or paste a sample, then select **Analyze passage**. Long files are divided into passages at nearby paragraph or line breaks. Navigate with Previous/Next, or select a smaller portion in the editor. File input is capped at 8 MB. The worker limits analysis to 16,384 UTF-16 units and 4,096 tokens. The default runtime is the [existing evaluation install](../../docs/modernbooknlp-provider.md#isolated-setup). Set `NLP_INSPECTOR_PYTHON` and `NLP_INSPECTOR_ASSETS` to override it, or `NLP_INSPECTOR_PORT` to change the port.

The highlight key toggles model quotes, person mentions, the model's chosen speaker mentions, and baseline quotes. Only identified speakers get a hue, with six distinct hues before additional speakers share a neutral style. Dialogue uses the speaker's fill and speaker evidence uses its matching underline. General person mentions use a neutral dotted line. Hover text gives all labels on an overlapping highlight. Select a quote to locate it in the text and inspect the proposed speaker, evidence, baseline and offsets. **Save output JSON** includes the analyzed source, raw provider artifacts and baseline output.

The comparison baseline leaves untagged speakers unknown. Cluster IDs and colors are passage-local. Independent passages can lose cross-boundary context, so use a selected excerpt to shift the boundary when investigating a disputed turn. Offsets refer to the exact analyzed text. Files with CRLF line endings are normalized to LF on open.

The browser owns editable text and one current analysis generation. Changing passages, editing, or canceling aborts the current request, and late results are ignored. The loopback server runs one worker at a time, with no queue. Disconnect, timeout or shutdown retires the process and removes its temporary files. Each analysis loads a fresh model. Ctrl-C stops the server and releases its temporary sources and WAVs. Model caches remain available for reuse.

## Compose a Fish audition

Analyze a passage or selection once. Under **Source blocks**, drag a block into **Composition** or use **Add**. Choose a reference voice for each item. Move, repeat or remove items to hear different handoffs. Reveal a block in the highlighted passage to check its source. **Render audio** submits the displayed order. Use the audio player to listen, and expand the receipt to inspect the actual speaker tags, text and reference identities. Editing or changing the source starts a new interactive composition.

The lab derives blocks from MBNLP sentence/paragraph token metadata and quote offsets. Each item is an exact UTF-16 slice of the analyzed selection, with optional speaker evidence. The blocks are the inspector's projection of that evidence. The final Fish voice is a deliberate experimental choice.

Audition requires the qualified local **Fish Drama 3 bf16** native-scene checkpoint, its arm64 MLX Python environment and available verified voice references. Set `READALOUD_MLX_PYTHON` and `READALOUD_MLX_TTS_MODEL_PATH` for non-default installations. Source analysis can be used independently of Fish. The server allows one model operation at a time. The first render includes model verification and load. Stop a pending operation with Cancel or by disconnecting the request. [Local runtime setup](../../docs/mlx-tts-engines.md)

## Drive the same inspector from an agent

Start the inspector as above. The JSON API is loopback-only. The example uses curl and jq and saves a generated WAV in the current directory.

```sh
inspector=http://127.0.0.1:8769
curl -fsS "$inspector/api/voices" > voices.json
curl -fsS "$inspector/api/analyze" -H 'Content-Type: application/json' \
  -d '{"text":"“You may begin,” said the King. “I am ready,” said the Rabbit."}' > analysis.json
jq '.blocks[] | {id, text, kind, speaker}' analysis.json
jq -n --slurpfile a analysis.json --slurpfile v voices.json '
  ($a[0].blocks | map(select(.kind == "dialogue"))) as $q |
  {sourceId:$a[0].sourceId, items:[
    {blockId:$q[0].id, voiceId:$v[0].voices[0].id},
    {blockId:$q[1].id, voiceId:$v[0].voices[1].id}
  ]}' > composition.json
curl -fsS "$inspector/api/render" -H 'Content-Type: application/json' \
  --data-binary @composition.json > receipt.json
curl -fsS "$inspector$(jq -r .audioUrl receipt.json)" -o audition.wav
```

Supply IDs from the analysis and voices returned by this server. The order of `items` is the submitted order. The render receipt includes the source ID, ordered items/turns, actual backend request, model and references, frame count and a local audio URL. Store the receipt beside the WAV for repeatable comparisons. Source IDs and audio URLs live only in this server session. The last eight distinct analyses and last eight renders remain available. An expired source requires another analysis. A failed model operation returns an error; it never substitutes generated demo audio. The inspector remains an exploratory tool. Acoustic test qualification is tracked separately. [Test framework design](https://github.com/kellyjanderson/readaloud/issues/160)
