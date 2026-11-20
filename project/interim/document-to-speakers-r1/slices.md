# Document-to-speakers work orders

Fixed R1 prompt set for [design #170](https://github.com/kellyjanderson/readaloud/issues/170). The [release plan in #122](https://github.com/kellyjanderson/readaloud/issues/122) owns scope. Use the folder's [architecture](architecture.md) for the proposed contract and the [pre-alfa walkthrough](../../architecture/document-to-speakers.md) for implemented behavior.

## How to assign one prompt

Choose one ready work order and copy its block. The issue identifies the durable owner. Before dispatch, the coordinator records the actual worker, SHA, worktree, target and dependency state in its current block. The suggested model is available for the bounded task; high reasoning is used for acoustic attribution, concurrency, compatibility, hardware or release evidence. The release coordinator supplies scope and human decisions. All work orders below are unassigned when published.

R work orders cover the existing release. D/L/N/K/A/C/V work orders describe proposed changes, each subject to R01 admission into a named release. K uses existing design #165. Analysis #158 already has an implemented draft; start from its verified branch when reconciling linguistic cuts. Advanced-media synchronization stays with #135. Unavailable hardware, missing licensing evidence or an incompatible model yields a specific blocked result. Parallel work requires exclusive ownership in separate worktrees; serialize edits to a common controller, manifest, native sink or package. Run the final native lane serially.

## Dependency map

| Work stream | Entry and handoff |
| --- | --- |
| Existing reader | R01 → chapter, offline and memory findings → dependency PRs → exact ordinary package R12 → measured R08/R09/R10, notices and listening → R14/R17 → R15/R16 |
| Prepared book | D01 → D02 and D03 → D04 → D05; D01 also feeds L02 |
| Linguistic planner | L01 compares cuts; L02 consumes its result and the agreed chapter admission rule |
| Native speech | N01 exact Fish proof → N02 binding → N03 lifecycle → N04 acquisition → seven N05 profile decisions; N06 separately evaluates optional analysis; N07 retires superseded provisioning |
| Kokoro | K01a → K01b → K01c once a qualified native replacement exists |
| Audio and storage | A01 → A02 and A03 → A04. C01 → C02 → C03 after A04 → C04a/C04b |
| Controls | V01 measures applied speed; V02 qualifies directional cues and voice evidence |
| Conditional integration | Every lane admitted at R01 returns its terminal evidence and exact SHA to R17. Integrate admitted changes **before** collecting final R08–R13 evidence. If the integrated tree changes, repeat affected checks. |

## Release integration and acceptance

### R01 · Reconcile release membership

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires the pre-alfa and current release record.

```text
Read #170 R1 and the current block of #122. Take only R01 once its prerequisites are cleared.
In #122 enumerate the seven R23 workstreams S3/S6/S7/S8/S9/S10/S11, chapter amendment #158, #154/#157/#169 and their exact integration bases. Compare the optional R1 slices below with #135, #160, #161 and #165. Record admit/defer/retain-existing-owner for each lane, version decision owner, first-load policy owner and branch target. Return a decision matrix. Preserve all current milestone gates.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R02 · Decide the opening narration rule

Owner [#158](https://github.com/kellyjanderson/readaloud/issues/158) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #158. Take only R02 once its prerequisites are cleared.
In #158 reproduce the 25.459 s first-chapter wait and the 12.522 s saved-analysis synthesis path with the existing timed fixture, or identify why reproduction differs. Compare bounded opening narration against holding dialogue until chapter evidence is ready. Return the recommended admission rule, effects on speaker accuracy and both launch and post-startup budgets. Obtain the coordinator’s policy decision before changing behavior.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #158.
```

### R03 · Implement the agreed chapter admission rule

Owner [#158](https://github.com/kellyjanderson/readaloud/issues/158) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R02.

```text
Read #170 R1 and the current block of #158. Take only R03 once its prerequisites are cleared.
Own reader_chapter_analysis.dart and its focused tests. At normal Open/Play and seek apply the #158 decision using the existing revision owner. A held chapter must not publish stale speech after Cancel or replacement. Show matched opening anchors, later dialogue identity, real progress and unaffected completed chapter reuse on the fixed fixture.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #158.
```

### R04 · Eliminate offline replay’s incidental model retry

Owner [#158](https://github.com/kellyjanderson/readaloud/issues/158) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R01.

```text
Read #170 R1 and the current block of #158. Take only R04 once its prerequisites are cleared.
Own reader audio-book reopen and model-prepare demand in the controller. Open a complete v5 book in an offline empty-model profile, capture to EOF and inspect the normal status UI. Require zero model-prepare demand or retry for verified audio, then demonstrate selective synthesis demand on a genuinely missing scene. Return a focused regression and native replay evidence.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #158.
```

### R05a · Verify the corrected passage and narrator reference

Owner [#158](https://github.com/kellyjanderson/readaloud/issues/158) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #158. Take only R05a once its prerequisites are cleared.
Own the #169 corrected quote fixture. Replay stored analysis, regenerate the affected passages and compare expected speaker, emitted line order and narrator reference digest. Prepare private matched clips for human accent and identity judgment in R13. Record only fixture IDs, measurements and remaining acoustic uncertainty publicly.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #158.
```

### R05b · Verify text selection across mounted reader ranges

Owner [#158](https://github.com/kellyjanderson/readaloud/issues/158) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #158. Take only R05b once its prerequisites are cleared.
Own the #169 reader selection verification. Drag a selection across a mounted range boundary in the ordinary macOS app, copy and compare its contents including Unicode, check follow suspension and resume, then Quit and verify exit. Return native evidence or one bounded repair and its regression.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #158.
```

### R06 · Resolve incomplete memory accounting at Fish admission

Owner [#112](https://github.com/kellyjanderson/readaloud/issues/112) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #112. Take only R06 once its prerequisites are cleared.
Own the narrow Fish process-tree memory observation and admission path. Reproduce the #158 fresh-source refusal with a cold process, verify treatment of incomplete observations and retry/recovery without admitting a model beyond the configured envelope. Return timestamps, measured memory, refusal/recovery and Cancel/normal Quit evidence.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #112.
```

### R07a · Reconcile the dependency PR #167

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R01.

```text
Read #170 R1 and the current block of #122. Take only R07a once its prerequisites are cleared.
Own the release integration review for #167 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07b · Reconcile the dependency PR #157

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07a.

```text
Read #170 R1 and the current block of #122. Take only R07b once its prerequisites are cleared.
Own the release integration review for #157 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07c · Reconcile the dependency PR #169

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R03, R04, R05a, R05b, R06, R07b.

```text
Read #170 R1 and the current block of #122. Take only R07c once its prerequisites are cleared.
Own the release integration review for #169 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07d · Reconcile the dependency PR #154

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07c.

```text
Read #170 R1 and the current block of #122. Take only R07d once its prerequisites are cleared.
Own the release integration review for #154 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07e · Reconcile the dependency PR #136

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07d.

```text
Read #170 R1 and the current block of #122. Take only R07e once its prerequisites are cleared.
Own the release integration review for #136 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07f · Reconcile the dependency PR #134

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07e.

```text
Read #170 R1 and the current block of #122. Take only R07f once its prerequisites are cleared.
Own the release integration review for #134 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07g · Reconcile the dependency PR #133

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07f.

```text
Read #170 R1 and the current block of #122. Take only R07g once its prerequisites are cleared.
Own the release integration review for #133 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07h · Reconcile the dependency PR #132

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07g.

```text
Read #170 R1 and the current block of #122. Take only R07h once its prerequisites are cleared.
Own the release integration review for #132 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07i · Reconcile the dependency PR #131

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07h.

```text
Read #170 R1 and the current block of #122. Take only R07i once its prerequisites are cleared.
Own the release integration review for #131 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07j · Reconcile the dependency PR #130

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07i.

```text
Read #170 R1 and the current block of #122. Take only R07j once its prerequisites are cleared.
Own the release integration review for #130 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07k · Reconcile the dependency PR #129

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07j.

```text
Read #170 R1 and the current block of #122. Take only R07k once its prerequisites are cleared.
Own the release integration review for #129 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R07l · Reconcile the dependency PR #128

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07k.

```text
Read #170 R1 and the current block of #122. Take only R07l once its prerequisites are cleared.
Own the release integration review for #128 only. On its declared base, verify head/base SHAs, parent decisions, local checks, review state and accepted evidence. Compare overlapping work by exact tree and reconcile only conflicts introduced at this hop. If approved for integration, record the resulting SHA on its declared target and refresh the downstream diff. Otherwise record the specific gate. #123/main and release publication remain R15/R16.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R08 · Measure startup and responsiveness on the integrated candidate

Owner [#152](https://github.com/kellyjanderson/readaloud/issues/152) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R07l, R12.

```text
Read #170 R1 and the current block of #152. Take only R08 once its prerequisites are cleared.
Own the ordinary-app timing run on one exact signed candidate. Test fresh small/large source, saved-analysis requiring synthesis and complete offline book. Record launch, normal startup, Open, Play, first matched emitted speech, pending Cancel and response during work. Report the 2 s launch and 10 s/5 s post-startup criteria separately with actual progress and failure recovery.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #152.
```

### R09 · Capture sustained Fish continuity and portable round trip

Owner [#152](https://github.com/kellyjanderson/readaloud/issues/152) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R07l, R12.

```text
Read #170 R1 and the current block of #152. Take only R09 once its prerequisites are cleared.
Own one public or authorized local long-form fixture. In ordinary playback capture to the declared end with ordered speaker/word/PCM coverage, starvation, joins and final syllables. Verify WAV export, saved v5 offline reopen and affected-region voice regeneration against the same fixture and unaffected hashes. Record capture duration/dropouts and Quit, with separate listening judgments in R13.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #152.
```

### R10 · Qualify the physical target hardware

Owner [#112](https://github.com/kellyjanderson/readaloud/issues/112) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R07l, R12.

```text
Read #170 R1 and the current block of #112. Take only R10 once its prerequisites are cleared.
On the declared physical M3 and supported higher-memory target, exercise the approved precision and model switching policy for the same bounded fixture. Report admission, memory, cancellation/drain, emitted completion and recovery per machine. Record actual hardware or an explicit missing-hardware gate.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #112.
```

### R11a · Resolve the project-grant distribution gate

Owner [#153](https://github.com/kellyjanderson/readaloud/issues/153) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #153. Take only R11a once its prerequisites are cleared.
Own only the project-grant entry in third_party/licenses/inventory.json and #55/#153. Trace exact candidate components to required notices, permission or owner decision. Inspect the candidate where needed and attach evidence or the remaining blocker. Run the local notices integrity checker. Preserve all other blocker records. Changes to licenses, signing identity or paid services require owner authority.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #153.
```

### R11b · Resolve the asset-origin distribution gate

Owner [#153](https://github.com/kellyjanderson/readaloud/issues/153) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #153. Take only R11b once its prerequisites are cleared.
Own only the asset-origin entry in third_party/licenses/inventory.json and #55/#153. Trace exact candidate components to required notices, permission or owner decision. Inspect the candidate where needed and attach evidence or the remaining blocker. Run the local notices integrity checker. Preserve all other blocker records. Changes to licenses, signing identity or paid services require owner authority.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #153.
```

### R11c · Resolve the pdfium-transitive distribution gate

Owner [#153](https://github.com/kellyjanderson/readaloud/issues/153) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #153. Take only R11c once its prerequisites are cleared.
Own only the pdfium-transitive entry in third_party/licenses/inventory.json and #55/#153. Trace exact candidate components to required notices, permission or owner decision. Inspect the candidate where needed and attach evidence or the remaining blocker. Run the local notices integrity checker. Preserve all other blocker records. Changes to licenses, signing identity or paid services require owner authority.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #153.
```

### R11d · Resolve the candidate-sdk distribution gate

Owner [#153](https://github.com/kellyjanderson/readaloud/issues/153) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R12.

```text
Read #170 R1 and the current block of #153. Take only R11d once its prerequisites are cleared.
Own only the candidate-sdk entry in third_party/licenses/inventory.json and #55/#153. Trace exact candidate components to required notices, permission or owner decision. Inspect the candidate where needed and attach evidence or the remaining blocker. Run the local notices integrity checker. Preserve all other blocker records. Changes to licenses, signing identity or paid services require owner authority.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #153.
```

### R11e · Resolve the in-app-notices distribution gate

Owner [#153](https://github.com/kellyjanderson/readaloud/issues/153) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R12.

```text
Read #170 R1 and the current block of #153. Take only R11e once its prerequisites are cleared.
Own only the in-app-notices entry in third_party/licenses/inventory.json and #55/#153. Trace exact candidate components to required notices, permission or owner decision. Inspect the candidate where needed and attach evidence or the remaining blocker. Run the local notices integrity checker. Preserve all other blocker records. Changes to licenses, signing identity or paid services require owner authority.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #153.
```

### R11f · Resolve the distribution-signing distribution gate

Owner [#153](https://github.com/kellyjanderson/readaloud/issues/153) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R12.

```text
Read #170 R1 and the current block of #153. Take only R11f once its prerequisites are cleared.
Own only the distribution-signing entry in third_party/licenses/inventory.json and #55/#153. Trace exact candidate components to required notices, permission or owner decision. Inspect the candidate where needed and attach evidence or the remaining blocker. Run the local notices integrity checker. Preserve all other blocker records. Changes to licenses, signing identity or paid services require owner authority.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #153.
```

### R11g · Resolve the mlx-runtime-and-reference-voices distribution gate

Owner [#153](https://github.com/kellyjanderson/readaloud/issues/153) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #153. Take only R11g once its prerequisites are cleared.
Own only the mlx-runtime-and-reference-voices entry in third_party/licenses/inventory.json and #55/#153. Trace exact candidate components to required notices, permission or owner decision. Inspect the candidate where needed and attach evidence or the remaining blocker. Run the local notices integrity checker. Preserve all other blocker records. Changes to licenses, signing identity or paid services require owner authority.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #153.
```

### R12 · Stage the ordinary candidate and validate packaging

Owner [#152](https://github.com/kellyjanderson/readaloud/issues/152) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R07l.

```text
Read #170 R1 and the current block of #152. Take only R12 once its prerequisites are cleared.
Own candidate packaging. Use the existing attested release build and package tool on the exact release branch with a fresh profile. Collect build metadata, manifests, offline install/replay, notices screen, signature/entitlements, applicable distribution identity and clean Quit. Return the immutable package hash and unpacked validation. A Reporting QA build is only the comparison baseline. Run the full relevant local Flutter suite and native, protocol and notice regressions, listing skips. Feed this package to candidate-specific R11 gates.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #152.
```

### R13 · Run the combined human acceptance session

Owner [#152](https://github.com/kellyjanderson/readaloud/issues/152) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R05a, R05b, R08, R09, R10, R12.

```text
Read #170 R1 and the current block of #152. Take only R13 once its prerequisites are cleared.
Use the native #155 runner once engineering is ready. Bind the exact ordinary build, profile and safe fixtures. Ask the listener to judge voice identity, narrator accent, cadence/emphasis, joins, intelligibility and controls including physical Cmd-V. Return completed cases, per-passage observations, remaining failures and evidence of normal Quit. Never fill human answers from software capture.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #152.
```

### R14 · Reconcile accepted features and release evidence

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R08, R09, R10, R12, R13, R11a, R11b, R11c, R11d, R11e, R11f, R11g.

```text
Read #170 R1 and the current block of #122. Take only R14 once its prerequisites are cleared.
Own current architecture, README and release issue reconciliation. Verify actual merged commits, admitted feature gates, remaining #83/#91/#55 obligations and each release milestone item, including docs/redesign exclusions. Record exact evidence and fix or return failures to their owners. Produce an item-by-item go/no-go and recommended candidate version.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R15 · Prepare the real release candidate

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R17.

```text
Read #170 R1 and the current block of #122. Take only R15 once its prerequisites are cleared.
On codex/release-drama-reading update version/changelog for the approved candidate, reconcile docs and build/test the exact SHA. Recheck the affected evidence if bytes changed, record artifacts and open/update #123 to main. Return clean local checks and stable review state. Keep final publication contingent on the release decision.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R16 · Publish and verify the approved release

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R15.

```text
Read #170 R1 and the current block of #122. Take only R16 once its prerequisites are cleared.
For the specifically authorized version, verify #123 is stable and required reviews/gates pass. Merge, verify the resulting local main SHA, rebuild and verify the actual main artifact; rerun affected acceptance for a changed tree. Create the immutable version tag, publish, download to a fresh location and compare the hash/signature. Record receipt and close only accepted release records. The pre-alfa approval covers that snapshot only.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

### R17 · Bind admitted optional features to final qualification

Owner [#122](https://github.com/kellyjanderson/readaloud/issues/122) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R14.

```text
Read #170 R1 and the current block of #122. Take only R17 once its prerequisites are cleared.
Before R15, compare R01’s signed scope decisions with actual integration SHAs for every admitted optional lane. Require its leaf evidence, legacy migration results, platform matrix and reruns of affected R08–R13 measurements on the integrated candidate. Return the release traceability table and each explicitly deferred issue. An unadmitted proposal cannot block #122.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #122.
```

## Canonical document intake

### D01 · Define the canonical prepared-range contract

Owner [#171](https://github.com/kellyjanderson/readaloud/issues/171) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R01.

```text
Read #170 R1 and the current block of #171. Take only D01 once its prerequisites are cleared.
Own prepared_document_snapshot.dart and range model tests. Define a typed range with source revision, anchor, UTF-16 display/spoken mapping, explicit direction and separately tracked text/analysis/audio coverage. Demonstrate equality for a source range and its restored representation, including Unicode and a seek window. Limit this change to the contract.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #171.
```

### D02 · Adapt source intake to canonical ranges

Owner [#172](https://github.com/kellyjanderson/readaloud/issues/172) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires D01.

```text
Read #170 R1 and the current block of #172. Take only D02 once its prerequisites are cleared.
Own document_preparation_supervisor.dart and the necessary import adapter seam. Feed one shared canonical publication path for TXT, Markdown, RTF, HTML, DOCX, EPUB and PDF. Test first range before EOF where format permits, clipping/seek and stale cancellation. Report unavoidable container setup separately. Keep existing source mappings and adapter parsing.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #172.
```

### D03 · Adapt saved documents and verified checkpoints

Owner [#173](https://github.com/kellyjanderson/readaloud/issues/173) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires D01.

```text
Read #170 R1 and the current block of #173. Take only D03 once its prerequisites are cleared.
Own reader_document_repository.dart, version reader seams and their fixtures. Map legacy v1–v4 JSON, indexed v5 and source checkpoint reuse into D01 ranges. Verify model-free demand reads, malformed-member recovery, source identity and equivalent cast/anchor/direction replay. Preserve legacy WAV books.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #173.
```

### D04 · Make the reader consume the shared range stream

Owner [#174](https://github.com/kellyjanderson/readaloud/issues/174) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires D02, D03.

```text
Read #170 R1 and the current block of #174. Take only D04 once its prerequisites are cleared.
Own reader_controller.dart’s document handoff. Route reader display, planning and export document input through the canonical contract. Force Open/replace/seek races and prove stale ranges do not enter the active session. Compare normal Open and saved reopen on the same input; remove one superseded handoff only after parity.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #174.
```

### D05 · Resume interrupted conversion and publish complete books

Owner [#175](https://github.com/kellyjanderson/readaloud/issues/175) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires D04.

```text
Read #170 R1 and the current block of #175. Take only D05 once its prerequisites are cleared.
Own the checkpoint writer and final book publication seam. Persist only verified revision-bound ranges across interruption, resume without redoing valid ranges, and expose full conversion as an explicit offline operation using the same intake. Prove atomic publication under cancellation, partial disk failure and retry. Text EOF, analysis and rendered completion must remain separately observable.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #175.
```

## Linguistic evidence and cuts

### L01 · Score linguistic cut candidates against the Dart baseline

Owner [#176](https://github.com/kellyjanderson/readaloud/issues/176) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #176. Take only L01 once its prerequisites are cleared.
Own a small labeled fixture and evaluator for the #158 chapter planner. On identical text map MBNLP sentences, dependencies and quotes to UTF-16 cuts, compare against provisional Dart rules with forbidden/acceptable boundaries and window-edge cases. Report cut precision/errors, speaker score separately and first-ready cost. Return the conditions for selecting provider evidence.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #176.
```

### L02 · Apply qualified linguistic cuts to future renders

Owner [#177](https://github.com/kellyjanderson/readaloud/issues/177) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires L01, D01, R03.

```text
Read #170 R1 and the current block of #177. Take only L02 once its prerequisites are cleared.
Own chunk_planner_service.dart’s cut-selection seam using the existing #169 scene projection. Let authored boundaries and voice changes constrain eligible semantic cuts, and let the engine enforce its token/context budget. Verify a late provider update changes only future uncommitted spans. Compare cadence on the same passage and checkpoint.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #177.
```

## Flutter/Dart native runtimes

### N01 · Prove the pinned Fish 4-bit native implementation

Owner [#178](https://github.com/kellyjanderson/readaloud/issues/178) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #178. Take only N01 once its prerequisites are cleared.
Own an isolated macOS native probe. Render one narrator/dialogue/narrator fixture using the Soniqo implementation and exact 4-bit snapshot 2b0c8028998533972e77359cce56b8bf1c5d6d4a offline with existing reference/transcript pairs. Measure cold load, first PCM, complete words/slots, memory and deployment floor against Python. Return reproducible evidence or the exact compatibility blocker.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #178.
```

### N02 · Expose one native render through Flutter/Dart

Owner [#179](https://github.com/kellyjanderson/readaloud/issues/179) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires N01.

```text
Read #170 R1 and the current block of #179. Take only N02 once its prerequisites are cleared.
Own the typed Flutter plugin interface and one native Fish 4-bit adapter. Expose capability, load, render and release for the verified profile with attempt ID, native sample rate and PCM descriptor. Use maintained bindings or a thin direct native bridge. Prove a signed arm64 Flutter app renders the fixture without a Python process, plus explicit capability failure on an unsupported platform.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #179.
```

### N03 · Bind incremental native audio to cancellation and credit

Owner [#180](https://github.com/kellyjanderson/readaloud/issues/180) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires N02.

```text
Read #170 R1 and the current block of #180. Take only N03 once its prerequisites are cleared.
Own the native adapter admission/packet integration. Feed ordered intervals into existing packet credit with session and binding revisions. Under full credit, held render, stale success/error and A→B→A replacement, prove immediate cancellation, acknowledged drain or quarantine, bounded memory, and no stale output. Compare normal reader playback and export to the accepted render.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #180.
```

### N04 · Move verified model acquisition onto the native route

Owner [#181](https://github.com/kellyjanderson/readaloud/issues/181) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires N03.

```text
Read #170 R1 and the current block of #181. Take only N04 once its prerequisites are cleared.
Own native snapshot resolution and catalog integration for Fish 4-bit. Reuse qualified cache paths/identities; test missing, offline, corrupt, interrupted/resumed and low-space cases with real progress. Verify the selected profile can provision and play in the ordinary sandboxed app without Python and preserves compatible saved audio.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #181.
```

### N05a · Prove the native Fish 8-bit profile

Owner [#182](https://github.com/kellyjanderson/readaloud/issues/182) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires N04.

```text
Read #170 R1 and the current block of #182. Take only N05a once its prerequisites are cleared.
Qualify only Fish 8-bit in the Dart native backend. Pin checkpoint, tokenizer/codec and reference/preset. On the same short fixture verify actual speaker order and final words, peak memory, first PCM, deployment and cold/warm rendering against the existing backend. Return a supported capability result or the exact blocker and defer decision. A missing implementation calls for a bounded follow-up decision before porting a whole model.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #182.
```

### N05b · Prove the native Fish bf16 profile

Owner [#183](https://github.com/kellyjanderson/readaloud/issues/183) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires N04.

```text
Read #170 R1 and the current block of #183. Take only N05b once its prerequisites are cleared.
Qualify only Fish bf16 in the Dart native backend. Pin checkpoint, tokenizer/codec and reference/preset. On the same short fixture verify actual speaker order and final words, peak memory, first PCM, deployment and cold/warm rendering against the existing backend. Include matched neutral, whisper and shout passages. Return a supported capability result or the exact blocker and defer decision. A missing implementation calls for a bounded follow-up decision before porting a whole model.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #183.
```

### N05c · Prove the native Qwen Base profile

Owner [#184](https://github.com/kellyjanderson/readaloud/issues/184) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires N04.

```text
Read #170 R1 and the current block of #184. Take only N05c once its prerequisites are cleared.
Qualify only Qwen Base in the Dart native backend. Pin checkpoint, tokenizer/codec and reference/preset. On the same short fixture verify actual speaker order and final words, peak memory, first PCM, deployment and cold/warm rendering against the existing backend. Return a supported capability result or the exact blocker and defer decision. A missing implementation calls for a bounded follow-up decision before porting a whole model.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #184.
```

### N05d · Prove the native Qwen CustomVoice profile

Owner [#185](https://github.com/kellyjanderson/readaloud/issues/185) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires N04.

```text
Read #170 R1 and the current block of #185. Take only N05d once its prerequisites are cleared.
Qualify only Qwen CustomVoice in the Dart native backend. Pin checkpoint, tokenizer/codec and reference/preset. On the same short fixture verify actual speaker order and final words, peak memory, first PCM, deployment and cold/warm rendering against the existing backend. Return a supported capability result or the exact blocker and defer decision. A missing implementation calls for a bounded follow-up decision before porting a whole model.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #185.
```

### N05e · Prove the native Voxtral full profile

Owner [#186](https://github.com/kellyjanderson/readaloud/issues/186) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires N04.

```text
Read #170 R1 and the current block of #186. Take only N05e once its prerequisites are cleared.
Qualify only Voxtral full in the Dart native backend. Pin checkpoint, tokenizer/codec and reference/preset. On the same short fixture verify actual speaker order and final words, peak memory, first PCM, deployment and cold/warm rendering against the existing backend. Return a supported capability result or the exact blocker and defer decision. A missing implementation calls for a bounded follow-up decision before porting a whole model.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #186.
```

### N05f · Prove the native Voxtral fast profile

Owner [#187](https://github.com/kellyjanderson/readaloud/issues/187) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires N04.

```text
Read #170 R1 and the current block of #187. Take only N05f once its prerequisites are cleared.
Qualify only Voxtral fast in the Dart native backend. Pin checkpoint, tokenizer/codec and reference/preset. On the same short fixture verify actual speaker order and final words, peak memory, first PCM, deployment and cold/warm rendering against the existing backend. Return a supported capability result or the exact blocker and defer decision. A missing implementation calls for a bounded follow-up decision before porting a whole model.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #187.
```

### N05g · Prove the native MOSS v1.5 profile

Owner [#188](https://github.com/kellyjanderson/readaloud/issues/188) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires N04.

```text
Read #170 R1 and the current block of #188. Take only N05g once its prerequisites are cleared.
Qualify only MOSS v1.5 in the Dart native backend. Pin checkpoint, tokenizer/codec and reference/preset. On the same short fixture verify actual speaker order and final words, peak memory, first PCM, deployment and cold/warm rendering against the existing backend. Return a supported capability result or the exact blocker and defer decision. A missing implementation calls for a bounded follow-up decision before porting a whole model.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #188.
```

### N06 · Decide portable analysis and target-platform coverage

Owner [#189](https://github.com/kellyjanderson/readaloud/issues/189) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #189. Take only N06 once its prerequisites are cleared.
Own the Flutter capability matrix for optional MBNLP. Compare the existing Python provider with one maintained native candidate on saved token/quote/offset/speaker fixtures; record packaging, first-ready latency and supported OS/architecture. Include explicit optional-unavailable behavior. Hand mobile inference experiments to #161. Return an adopt/defer decision for analysis independent of native speech.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #189.
```

### N07 · Retire superseded Python speech provisioning

Owner [#190](https://github.com/kellyjanderson/readaloud/issues/190) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires N04, N05a, N05b, N05c, N05d, N05e, N05f, N05g, N06.

```text
Read #170 R1 and the current block of #190. Take only N07 once its prerequisites are cleared.
Own production runtime packaging and its smoke tests. For the coordinator-approved engine matrix, verify all required bindings and model installs offline/online, then remove superseded speech interpreter provisioning from qualifying packages. Inspect embedded runtime inventory and emitted audio. Record any still-selected optional NLP runtime, tool-only Python and platform-specific exclusions.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #190.
```

## Deprecated Kokoro migration

### K01a · Migrate deprecated Kokoro engine and voice preferences

Owner [#165](https://github.com/kellyjanderson/readaloud/issues/165) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires N04.

```text
Read #170 R1 and the current block of #165. Take only K01a once its prerequisites are cleared.
Under #165, map saved Kokoro engine/voice choices to a qualified replacement or explicit unavailable state. Verify a pre-existing profile, cast edits and model-free audio replay, with an explicit capability result on unsupported hardware.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #165.
```

### K01b · Retire Kokoro-specific render and selection paths

Owner [#165](https://github.com/kellyjanderson/readaloud/issues/165) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires K01a.

```text
Read #170 R1 and the current block of #165. Take only K01b once its prerequisites are cleared.
Under #165 remove the deprecated engine, fallback, preview and regeneration routes from active dispatch after replacement coverage is signed off. Preserve the shared Fish playback and export infrastructure. Return route inventory and emitted Fish/saved-audio regression.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #165.
```

### K01c · Retire Kokoro-only packaging and QA paths

Owner [#165](https://github.com/kellyjanderson/readaloud/issues/165) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires K01b.

```text
Read #170 R1 and the current block of #165. Take only K01c once its prerequisites are cleared.
Under #165 remove superseded Kokoro-only build/setup assets and headless QA options from the selected release package, reconcile notices and docs, then inspect a signed bundle and smoke the supported native route. Preserve the old readable book formats.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #165.
```

## Audio placement and continuity

### A01 · Implement a file-independent audio placement contract

Owner [#191](https://github.com/kellyjanderson/readaloud/issues/191) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R01.

```text
Read #170 R1 and the current block of #191. Take only A01 once its prerequisites are cleared.
Own frame interval and rate metadata types. Reuse existing continuous-period interval math if suitable. Define half-open placements, sample-rate identity, semantic pause ownership and opaque asset offsets. Prove exact equality on split samples including a mid-word cut, pause and EOF with no implied silence or double counting.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #191.
```

### A02 · Schedule contiguous intervals on the native audio sink

Owner [#192](https://github.com/kellyjanderson/readaloud/issues/192) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires A01.

```text
Read #170 R1 and the current block of #192. Take only A02 once its prerequisites are cleared.
Own the playback submission boundary. Feed one render split inside voiced speech across files and credit-limited buffers; verify emitted samples around the join, exact resume/seek order and no added silence. Test a late buffer and mixed native/device sample rates. Retain legacy correction only for explicitly identified legacy assets.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #192.
```

### A03 · Qualify joins between independent generations

Owner [#193](https://github.com/kellyjanderson/readaloud/issues/193) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires A01.

```text
Read #170 R1 and the current block of #193. Take only A03 once its prerequisites are cleared.
Own one independently generated pair and its bounded continuation or shared-context retry. Preserve punctuation/explicit timing once. Compare aligned and deliberately incompatible boundaries for clipped/repeated words and voice discontinuity. Return emitted waveform and listening evidence; report unresolved joins explicitly. General multimedia alignment remains #135.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #193.
```

### A04 · Use the same resolved placements in export

Owner [#194](https://github.com/kellyjanderson/readaloud/issues/194) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires A02, A03.

```text
Read #170 R1 and the current block of #194. Take only A04 once its prerequisites are cleared.
Own the export assembly seam. Reuse the reader’s resolved positions and explicit overlaps in export and portable reopen. Demonstrate decoded frame parity, rate conversion accounting, cancellation and no duplicate semantic pause at a storage or inference boundary. Record a same-render sample comparison and emitted playback near the join.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #194.
```

## Lossless storage and export

### C01 · Compare FLAC, standard ALAC and NARALAC

Owner [#195](https://github.com/kellyjanderson/readaloud/issues/195) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires R01.

```text
Read #170 R1 and the current block of #195. Take only C01 once its prerequisites are cleared.
Own a repeatable lossless codec comparison against identical PCM. Measure size, seek and streaming decode latency, CPU, memory, library size, metadata retention and representative platform package builds. Specify truthful book-relative NARALAC metadata and optional META handling. Return a codec decision with disqualifiers and deployment matrix; FLAC is the first candidate.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #195.
```

### C02 · Read the new lossless book asset profile

Owner [#196](https://github.com/kellyjanderson/readaloud/issues/196) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires C01, D03.

```text
Read #170 R1 and the current block of #196. Take only C02 once its prerequisites are cleared.
Own radoc_audio_package.dart’s read path and manifest negotiation. Preserve old v1–v5 readers. Validate codec ID, frame count, hash, seek/index bounds, unknown optional metadata and corrupt members with bounded memory. Decode to the original sample values and preserve canonical timing and directions.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #196.
```

### C03 · Write lossless portable books atomically

Owner [#197](https://github.com/kellyjanderson/readaloud/issues/197) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires C02, A04.

```text
Read #170 R1 and the current block of #197. Take only C03 once its prerequisites are cleared.
Own new-version book writing and export staging. Encode the chosen profile, keep the authoritative timeline and provenance in the manifest, and publish only complete verified assets. Reopen offline and compare decoded PCM and frame placements to the reference. Prove recovery after interrupted writes and continued legacy WAV readability.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #197.
```

### C04a · Qualify the durable lossless render cache

Owner [#198](https://github.com/kellyjanderson/readaloud/issues/198) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires C03.

```text
Read #170 R1 and the current block of #198. Take only C04a once its prerequisites are cleared.
Own only the durable render cache. Demonstrate decoded PCM equality, cache provenance, interrupted writes, old-WAV reuse, disk size and seek latency. Record whether the selected in-book codec also qualifies for durable cache use.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #198.
```

### C04b · Qualify lossless standalone export

Owner [#199](https://github.com/kellyjanderson/readaloud/issues/199) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires C03.

```text
Read #170 R1 and the current block of #199. Take only C04b once its prerequisites are cleared.
Own only user-selected standalone export for the chosen codec. Verify on an independent player/decoder, PCM and duration, metadata retention and truthful handling of unsupported metadata. Keep the prior WAV export readable and document the selected behavior.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #199.
```

## Speech controls and listening evidence

### V01 · Make speech-rate behavior measurable

Owner [#200](https://github.com/kellyjanderson/readaloud/issues/200) · Suggested model **gpt-6.2-sol** · Reasoning **medium** · Requires R01.

```text
Read #170 R1 and the current block of #200. Take only V01 once its prerequisites are cleared.
Own the rate capability and its normal UI-to-sink route for one offered engine. Distinguish model rate, pitch-preserving listening speed and whether a chosen export rate is baked in. Verify multiple settings on identical speech using emitted duration, pitch, export duration and raw-cache reuse. Present unsupported controls truthfully.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #200.
```

### V02 · Qualify emphasis, cadence, pronunciation and accent controls

Owner [#201](https://github.com/kellyjanderson/readaloud/issues/201) · Suggested model **gpt-6.2-sol** · Reasoning **high** · Requires L01.

```text
Read #170 R1 and the current block of #201. Take only V02 once its prerequisites are cleared.
For one engine/profile at a time own the adapter capability mapping and fixed test passage. Preserve canonical intent, reference identity and pronunciation overrides; compare neutral/directed speech with the same speaker, pitch/stress/cadence measurements and human listening. Record unsupported controls and ensure directions survive portable reopen. Use #160 fixtures where available.
Return the result, exact base/head and target, changed paths, evidence and remaining gates to #201.
```
