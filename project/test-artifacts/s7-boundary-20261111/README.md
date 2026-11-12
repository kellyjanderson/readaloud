# Native queue boundary evidence — November 11, 2026

Refs #142/#144 under #112 / ACD-M1 R1, parent #110 R23/R25.
These are immutable diagnostic records, not acceptance or a local task ledger.
Full receipts are compact-JSON normalized; original private receipt/media byte
hashes remain in `private-artifact-inventory.json`. No WAVs or weights in Git.

| Case | Native / UI maximum | Acoustic observation | Result |
| --- | --- | --- | --- |
| v37 utility4bit, sourcebd52661 | 260ms /5ms | 172 full references in both recordings; one complete waveform fails, recovery373.008ms late | Failed |
| v38 exact-v37 packet replay | 196ms /2ms | 174 full references,55.755s, max join0.00397ms | Diagnostic criteria met |
| v39 native audit, normal rewind | 262ms /3ms | 173 full references in both; one full-waveform failure, recovery290.57ms late | Failed |
| v40 skip-rewind | 1ms /4ms | No playback; capture unavailable on locked screen | Blocked control |
| v41 skip-rewind | 983ms /5ms | 167 full references in both; three complete-waveform failures | Failed |
| v42 bounded history retention | 247ms /5ms | 169 full references/54.059s in both, no timing violations, max join0.00457ms | Diagnostic criteria met |

V38 uses four seconds of preadmission and no history pruning, with no MLX child.
It establishes capability with the exact same immutable PCM, not safety of live
arrival/pruning. V42 retains the live inference, startup and lookahead policies;
it suppresses history pruning below512 represented entries, then resumes ordinary
pruning. Its60s case queued267 entries and does not qualify long-run behavior at
that ceiling. One pass does not prove a cause or sufficient remedy. All QA
variants remain labelled non-qualifying by their runner. Thresholds remain
250ms native/UI, full-active correlation0.98 and10ms external joins.

V37 microanalysis finds both recordings contain222.1875ms and111.625ms exact-zero
intervals. All sampled20ms reference fragments match locally at>=0.9985, with
the later fragments259.218ms late. This proves an interruption/delay in that
case; it does not prove every transition sample survived. Earlier fixed-timeline
v17/v23 losses remain distinct retained observations.

## Native identity facts

The native audit candidate source is380e0c7. It uses the existing global
just_audio channel and is off by default. Main-thread-owned rings have first8
source objects,64 item identities,2048 events,32 queue entries and8 loaded ranges
as hard bounds. No logging, file writes, new timers or dispatch backlog occur in
callbacks. Off-main/truncation/overflow/disposal facts are explicit. Snapshots
are sequential, not atomic; timestamps precede AVFoundation queries.

V39 records all first8 loop-off rewind entries while the ended item was observed
as the physical current item. This exposes a candidate race; it does not prove
the later seek executed before handoff or caused the emitted gap. Removing those
rewinds in v41 failed and was not adopted.

V41 also records packet0004's end notification at1794447671807586us while the
physical current/head was packet0003 at0.248813458s. Packet0003's notification
arrived later,1794447671885421us. Native KVO then briefly observes packet0004 at
EOF before packet0005. Thus an end notification alone cannot establish the
current audible/physical owner. The first8 trace records no destructive native
head removal; it does not prove history pruning caused the acoustic failure.

## Checks and cleanup

Full S7 Flutter suite1082 passed /4 optional skips. Scoped analysis passed.
Native fixtures pass the original24 queue scenarios plus disabled/no-query,
identity/stale, bounds, off-main, disposal and QA rewind-control cases. The first
local fixture compile attempted a stripped release-framework header path and
failed; rerunning against the pinned SDK's headers passed. That failed tooling
control is retained separately. Full signed arm64 app build succeeded; raw build
logs remain private because they contain environment data.

All six runs requested normal Quit and verified owned app exit/no orphans.
V40 could not provide a controller/audio pass and is not reused as one. A
temporary display wake guard was added after that lock; v41/v42 verify its actual
exit0. It does not unlock the Mac or change lock/security settings. No listening,
physical speaker, M3, R25 clock, release integration or publication claim.
