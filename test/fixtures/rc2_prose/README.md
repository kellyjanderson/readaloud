# RC2 natural prose fixtures

The production input is only `text/*.txt`. The separate `oracles/*.json` files are test-only: canonical cast IDs, dialogue owners, exact UTF-16 source spans, textual voice hints, negative controls and SHA-256 identities. The importer receives none of these expectations.

[Independent blind audit](https://github.com/kellyjanderson/readaloud/issues/89#issuecomment-6429213427) reviewed the original five before oracle freeze. The same separate agent authored the held-out passage `rain.txt`; its prose is retained verbatim. The audit identified an across-file identity ladder, so the test uses a reproducibly shuffled file order and includes renamed/rephrased variants with reversed dialogue-tag order. This remains a small, comparatively easy corpus; it does not establish general literary coreference accuracy.

| Contract case | Text | Words | Dialogue identities |
| --- | --- | ---: | --- |
| P0 | tide.txt | 352 | none |
| P1 | lantern.txt | 367 | Mara |
| P2 | orchard.txt | 376 | Mara, Jonah |
| P3 | platform.txt | 375 | Mara, Jonah, Niko |
| P4 | bridge.txt | 378 | Mara, Jonah, Niko, Saira |
| Held-out | rain.txt | 421 | Beatrice, Leon, Priya, Tomas |

Variants are `glass.txt`, `fruit.txt`, `track.txt` and `current.txt`; each oracle names its source variant. All files remain 350–500 words. Hashes are stored in the corresponding oracles and checked before import. `Bea` is a grounded vocative alias in the held-out prose; it must not become a duplicate speaking character. The focused inference tests separately verify explicit alias declarations, stable IDs, redirects and evidence-preserving merges.

`rc2_prose_corpus_test.dart` imports natural text through `DocumentImportService.importPastedText`, then checks the complete cast identity set and every quoted span's owner/text, narration routing, pronoun provenance and evidence coordinates. Counts alone cannot pass. This source-level check does not qualify the native voice dialog, incremental playback, emitted audio or reusable `.radoc`; those remain integrated RC2 evidence requirements in #83/#91.
