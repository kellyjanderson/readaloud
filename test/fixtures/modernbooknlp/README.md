# ModernBookNLP test evidence

`smoke_cases.json` is synthetic protocol smoke input, not a literary benchmark.

`rain-record.json` and `orchard-record.json` contain actual offline CPU outputs
for the existing public RC2 prose corpus, captured November 5, 2026 using the
pinned runtime/model identities inside each record and `paragraph-context-v2`.
They contain no private City/Rosalina material. Labels remain in the separate
[RC2 oracle corpus](../rc2_prose/README.md), including its independent blind audit.
The model receives prose only; fixtures are not expected-output generators.

The raw artifacts preserve all upstream entity categories and `.book` summaries,
including model mistakes/uncertainty. A model result is evidence, not a gold label.
`modernbooknlp_window_test.dart` validates source correspondence, exact bindings,
alias/singleton handling and portable retention without requiring inference.
