# Native Play position snapshot fixture receipt

Work order: https://github.com/kellyjanderson/readaloud/issues/144#issuecomment-6815633761
Base: a721106; local commit: 7af15c036cbee741ad09f8aef3ff64d939346043.
Branch/worktree: codex/s7-play-position-snapshot at /Users/k/.codex/worktrees/s7-play-position-snapshot/readaloud.
Target for root review/integration: codex/reader-feedback-s8 then S7/#145 -> #139; no push or merge performed.

The only production change snapshots the existing position reader before rate activation under TARGET_OS_OSX + readAloudFiniteLocalWavQueue + loop-off. It retains _seekPos policy, actual current item position and upstream results/EOF/lifecycle. Other paths retain rate-then-position ordering. No scheduler, offload, timer, producer or GPU policy was added.

Run `bash tmp/s7-play-position-snapshot/replay.sh` from this checkout to replay exact commands. The script selects the supplied Flutter framework, runs the whole native fixture suite, archives exact base a721106 Darwin sources and runs the same current startup-lock fixture against that source override. Logs:

- fixed-native.log: exit 0; full existing queue/admission/audit/EOF suite plus real production Play position chain, bounded startup lock, nonzero pause/resume, duplicate/result, attach initial position, outstanding real item seek target and 2 x 3 opt-in/loop cases.
- old-source-negative.log: exit 1 expected; `FAIL: Play read AVPlayerItem.currentTime while rate activation owns the startup clock lock`.
- status.txt: exact exit codes.
- source-sha256.txt: tested source/doc hashes.
- host-architecture.txt / framework-architecture.txt: native build host and selected framework architectures.

The startup fixture retains AudioPlayer.updatePosition/getCurrentPosition and UriAudioSource.position. Its recording item substitutes only the AVFoundation boundary; a recording rate activation owns a surrogate NSLock and currentTime uses a bounded 25 ms lock attempt. The base source fails for the intended post-activation read, not for a fake updatePosition counter or a source-text ordering assertion. Nonzero/clock-read assertions prevent inventing a position to evade the lock.

Passed: native source compilation, full fixture suite, expected old-source negative, git diff --check. No warnings in final compile logs. Failed production/runtime gates: not evaluated by this worker. Not run: Flutter/app build, real AVPlayerItem runtime/timing, emitted audio, responsiveness, saved-book replay, sustained/human/M3 acceptance, other-platform compilation. No UI application or Flutter engine was launched, so no application cleanup session was needed. These fixture results do not prove that AVFoundation rate activation or other callbacks cannot block; root owns exact candidate native rebuild and running-app acceptance. #144 remains open.
