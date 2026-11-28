# R2 timing and hardware changes to R1 work orders

These instructions apply before the native Dart speech rewrite and runtime
migration complete. App launch, cold process start and launch-to-speech duration
have no acceptance threshold. Prior time measurements remain historical evidence.
Tests may observe startup duration for diagnosis. Functional startup and resource
readiness, failure handling and cancellation remain within their own contracts.
The [owner decision](https://github.com/kellyjanderson/readaloud/issues/122#issuecomment-7234797323) is the source for this policy.

## R02 and R07c · Chapter timing and integration review

For a first-load acceptance run, use Open after normal app startup through first
captured speech. Preserve the accepted chapter admission rule and speaker
accuracy checks. Treat cold launch results as historical observations. Retain
the post-startup document-load, active playback, partial-book continuity and
prerequisite integration checks.

## R08 · Verify post-startup document loads and responsiveness

On one exact signed ordinary app, test a fresh small and large source, saved
analysis requiring synthesis, and complete offline book reuse. Complete normal
startup, then record explicit Open, prompt Play and first matched emitted
speech. Apply R25's ten-second first-load and five-second reusable-load caps.
Include all work triggered by Open, show real progress, exercise input and
pending Cancel, and retain failure and recovery evidence.

## R10 · Verify available supported hardware

Exercise the approved precision and switching policy using the same bounded
fixture on an available supported Apple Silicon Mac. Report model admission,
memory, cancellation and drain, emitted completion and recovery. Identify the
machine and profile. Physical M3 testing is optional and an unavailable M3
does not block R10 or subsequent work.

## R12–R17 · Final package, human checks and reconciliation

R12 validates the exact ordinary packaged app, including functional launch.
R13 follows required engineering checks, including R10 on available supported
hardware. R14–R17 verify the acceptance and release evidence under this amended
policy. Missing M3 evidence and historical launch duration cannot block a
pre-rewrite slice or candidate. Continue to verify the exact package, document
loads, responsiveness, emitted audio, continuity, reuse, human judgments and
distribution as assigned in R1.

## N01–N07 · Native speech and optional analysis migration

Keep functional output, playback, supported deployment, memory safety, runtime
packaging and required engine coverage in the native migration. Comparative
runtime and first-output measurements are diagnostic until the migration is
complete. They carry no startup timing acceptance threshold in these slices.

## #207 · Startup performance after migration

Schedule this late follow-up after the native Dart speech bindings and required
engine migration are complete and N07 is cleared. Establish the exact candidate,
supported engine and optional analysis configuration, startup clocks, fixtures
and acceptance criteria before implementation.
