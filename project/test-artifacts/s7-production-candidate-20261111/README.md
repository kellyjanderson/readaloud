# Combined production candidate diagnostics and acceptance failures

Refs #142/#144/#112 under ACD-M1R1/#110R23/R25. Product source25936d4
includes the finite local-WAV per-player opt-in08d90fc and runtime progress
coalesceradcece7. All experimental player/scheduling/history flags are off.
Offline analyzer revisions are separate: quiet grouping147b1d7 and complete
reference context65bcb6c. These records do not declare the slices complete.

| Case | Native / UI maximum | Active native replies | Result |
| --- | --- | --- | --- |
| v49 4bit | 189 /10ms | 0/708 | Functional runner true; strict qualification refuses foreground absence |
| v50 8bit | 396 /5ms | 0/688 | Native failure; no foreground credit |
| v51 4bit | 227 /9ms | 671/671 | Strict acoustic/runtime pass |
| v52 8bit | 362 /4ms | 670/670 | Real native failures at901ms initialization and6301ms first synthesis |
| v53 attached Time Profiler | 258 /4ms | 672/672 | Instrumented failure; profiler began after delayed handlers |
| v54 launch profiler | none | none | xctrace refused ambiguous historical app names before launching any app |
| v55 launch via env exec | 188ms | 674/674 | Instrumented pass only; no earlier failure erased |

V51's original dual analysis matches173 full audible packets/55.624s in both
captures, minimum active correlation.994751 and maximum external join.004748ms;
no timing violations. Subsequent strengthened-context results are retained
separately where available. V49's original analyzer stopped at a10.77ms quiet
packet because two10ms guards erased its interior. Consecutive quiet sources
now use one bracketed signal interval; no individual quiet boundary/waveform
credit. The new test fails original code; an inserted20ms gap still fails.

V52's original analysis reported -65.355/+65.357ms joins around packet11. Its
62416-frame reference had only14comparisonframes above.01 (~73microseconds).
A free threshold-span search could identify an unrelated earlier transient.
The retained offline probe locates the complete reference at9.870869792s with
correlation.999608. This diagnostic alone does not override qualification.
Revision65bcb6c selects using complete context>=.98 and independently requires
active-span>=.98 at that exact placement; other gates stay unchanged. Four
regressions fail old source and a bypass-active-gate mutant fails.62focused
analyzer tests pass. Old and strengthened reports remain distinct. Native
362/344ms failures remain independent of any corrected acoustic placement.

Native finite-EOF controls are retained: original6a9061c and a same-head mutant
both fail the one-notice-before-last-sample then Pause assertion; fixed native
suite passes. Source fixtures are not emitted-audio or asynchronous native seek
proof. Raw logs from the worker were not retained; root reran the controls with
persistent logs and exact commands here.

V53 TOC starts19:14:04.228 Pacific; first sample is+323.160125ms, roughly1.742s
after the failed handler entered19:14:02.808848.35747rows/zero hang rows do not
explain that delay. Waiting-thread capture was on, context-switch sampling off.
V54 failure is tooling, with no app PID/normal-Quit credit. V55 uses maintained
xctrace launch of /usr/bin/env, which execs the exact app path; app PID29978 was
verified. Waiting-thread and context-switch capture were on. Trace coverage and
ownership require separate bounded audit; no remote owner is inferred here.

Every actually launched app in these cases requested normal Quit and verified
owned PID exit/no orphans; v55 also verifies capture/guard/tracer exit0. No
physical speaker, human listening, M3, universal-delay cure, release integration
or publication claim. Full raw audio and profiler/environment data remain
private, with file hashes retained; no WAVs, weights or raw TOC in Git.
