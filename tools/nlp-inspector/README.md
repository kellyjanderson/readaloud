# NLP Inspector

Open UTF-8 text or Markdown and inspect the pinned ModernBookNLP output against a small baseline for paired quotation marks and explicit named speech tags. The inspector runs locally, uses the existing evaluation runtime in offline mode, and does not involve Read Aloud playback or its caches.

Start from the repository root with Node 20.20 or later.

```sh
node tools/nlp-inspector/server.mjs
```

Open the [inspector](http://127.0.0.1:8769). Choose **Open text file** or paste a sample, then select **Analyze passage**. Long files are divided into passages at nearby paragraph or line breaks. Navigate with Previous/Next, or select a smaller portion in the editor. File input is capped at 8 MB. The worker limits analysis to 16,384 UTF-16 units and 4,096 tokens. The default runtime is the [existing evaluation install](../../docs/modernbooknlp-provider.md#isolated-setup). Set `NLP_INSPECTOR_PYTHON` and `NLP_INSPECTOR_ASSETS` to override it, or `NLP_INSPECTOR_PORT` to change the port.

The highlight key toggles model quotes, person mentions, the model's chosen speaker mentions, and baseline quotes. Only identified speakers get a hue, with six distinct hues before additional speakers share a neutral style. Dialogue uses the speaker's fill and speaker evidence uses its matching underline. General person mentions use a neutral dotted line. Hover text gives all labels on an overlapping highlight. Select a quote to locate it in the text and inspect the proposed speaker, evidence, baseline and offsets. **Save output JSON** includes the analyzed source, raw provider artifacts and baseline output.

The comparison baseline leaves untagged speakers unknown. Cluster IDs and colors are passage-local. Independent passages can lose cross-boundary context, so use a selected excerpt to shift the boundary when investigating a disputed turn. Offsets refer to the exact analyzed text. Files with CRLF line endings are normalized to LF on open.

The browser owns editable text and one current analysis generation. Changing passages, editing, or canceling aborts the current request, and late results are ignored. The loopback server runs one worker at a time, with no queue. Disconnect, timeout or shutdown retires the process and removes its temporary files. Each analysis loads a fresh model. The only persistent output is an explicit JSON download. Ctrl-C stops the server.
