# S6 R1 — portable dynamic audio books

Owner: /root. Source issue: [#137](https://github.com/kellyjanderson/readaloud/issues/137), under [#110 R23](https://github.com/kellyjanderson/readaloud/issues/110#issuecomment-6674071097). Implementation baseline: `1d7fe27a8f0a98061c382b90ce5efa40cf297120`, declared dependency `codex/fish-expressive-continuity` / #136. Target: that dependency branch, preserving its release chain.

Lifecycle: draft pending publication to #137. This is a proposed implementation contract, not implemented behavior or acceptance. GitHub owns assignments/status and subsequent decisions.

[Architectural delta](dynamic-audio-book.md) implements R23's already-authorized audio-only publishing outcome. It does not change default Character analysis activation or waive S3 failures. Illustrations, advanced timing and multimedia remain outside this revision.
