#!/usr/bin/env ruby
# Combine post-startup document load, app-only signal and exact waveform proof.
# The launch goal remains diagnostic; hard limits never subtract guessed startup.
require 'json'
require_relative 'startup_timing_policy'
abort 'Usage: summarize_startup_audio.rb NATIVE_OUTPUT_DIRECTORY COMPARISON_JSON NEW_RESULT_JSON [radoc|first-load]' unless [3, 4].include?(ARGV.length)
dir, comparison_path, output = ARGV.first(3).map { |p| File.expand_path(p) }
load_class = ARGV.fetch(3, 'radoc')
begin
  hard_limit_ms = StartupTimingPolicy.hard_limit_ms(load_class)
rescue ArgumentError => error
  abort error.message
end
abort 'Output already exists' if File.exist?(output)
read = ->(name) { JSON.parse(File.read(File.join(dir, name))) }
native = read.call('receipt.json')
runner = read.call('runner.json')
capture = read.call('capture.wav.timing.json')
comparison = JSON.parse(File.read(comparison_path))
first = comparison.fetch('matchedTurns').first or abort 'Missing expected speech match'
launch = runner['launchMonotonicRawNanos']
startup = native['appStartupCompleteMonotonicRawNanos']
opened = native['documentLoadRequestedMonotonicRawNanos']
play = native['playRequestedMonotonicRawNanos']
signal = capture['firstSignalMonotonicRawNanos']
# Explicit MonotonicRawNanos names identify CLOCK_MONOTONIC_RAW throughout;
# Unix timestamps, app stopwatches and readiness flags are never fallbacks.
valid_timestamp = ->(value) { value.is_a?(Integer) && value >= 0 }
duration = ->(start, finish) do
  (finish - start) / 1_000_000.0 if valid_timestamp.call(start) && valid_timestamp.call(finish) && finish >= start
end
elapsed = duration.call(launch, signal)
startup_elapsed = duration.call(launch, startup)
load_elapsed = duration.call(opened, signal)
play_elapsed = duration.call(play, signal)
observed_start = capture.fetch('firstSignalFrame') / capture.fetch('sampleRate').to_f
alignment = (observed_start - first.fetch('activeSpeechStartSeconds')).abs * 1000
errors = []
boundaries = [launch, startup, opened, signal]
valid_boundaries = boundaries.all? { |value| valid_timestamp.call(value) } &&
  boundaries.each_cons(2).all? { |start, finish| start <= finish }
errors << 'Missing/invalid CLOCK_MONOTONIC_RAW boundaries or document load requested before app startup completed' unless valid_boundaries
if native.key?('playRequestedMonotonicRawNanos') &&
    !(valid_boundaries && valid_timestamp.call(play) && play.between?(opened, signal))
  errors << 'Play CLOCK_MONOTONIC_RAW boundary is invalid or outside the document load/speech interval'
end
errors << 'A controlled Play gate was used' unless native['controlledCaptureGate'] == false && runner['captureIntroducedPlayGate'] == false
errors << 'Native functional/cleanup check failed' unless native['passed'] && runner['passed'] && runner['normalQuit'] && !runner['forcedCleanup'] && runner['remainingOwnedPids'] == [] && runner['captureExitStatus'] == 0
errors << 'Expected waveform/continuity check failed' unless comparison['passed'] && comparison.fetch('matchedTurns').all? { |m| m.fetch('correlation') >= 0.98 }
errors << 'First captured signal does not align with expected speech' unless alignment.finite? && alignment <= 50
goal_met = !elapsed.nil? && elapsed <= StartupTimingPolicy::GOAL_MS
hard_limit_met = valid_boundaries && load_elapsed <= hard_limit_ms
errors << "Post-startup document load to captured speech exceeds #{hard_limit_ms} ms hard limit or has invalid boundary evidence" unless hard_limit_met
result = {
  schema: 'readaloud-ungated-startup-audio-v3',
  timingPolicy: StartupTimingPolicy::REVISION,
  loadClass: load_class,
  goalMs: StartupTimingPolicy::GOAL_MS,
  hardLimitMs: hard_limit_ms,
  goalMet: goal_met,
  hardLimitMet: hard_limit_met,
  passed: errors.empty?, errors: errors,
  clockDomain: 'CLOCK_MONOTONIC_RAW',
  hardLimitOrigin: 'documentLoadRequestedMonotonicRawNanos',
  goalOrigin: 'launchMonotonicRawNanos',
  boundariesMonotonicRawNanos: {launch: launch, appStartupComplete: startup,
    documentLoadRequested: opened, playRequested: play, firstSignal: signal},
  appStartupDurationMs: startup_elapsed,
  launchToSpeechReceiptUpperBoundMs: elapsed,
  documentLoadToSpeechReceiptUpperBoundMs: valid_boundaries ? load_elapsed : nil,
  playToSpeechReceiptUpperBoundMs: play_elapsed,
  firstSignalExpectedSpeechAlignmentMs: alignment,
  launchToNativePositionMs: native['launchToNativePositionMs'],
  waveformComparison: comparison_path,
  limits: 'CLOCK_MONOTONIC_RAW independently records launch, ordinary app startup completion, post-startup document request and the first signal-bearing app-only packet aligned with the exact expected waveform. Hard limits include all work triggered by the measured document request; launch-to-speech retains the two-second goal. These are upper bounds on app-emitted speech, not physical speaker latency or human listening. Absence of off-clock target preparation, candidate completeness and fresh-profile provenance must be verified separately. Historical launch-only receipts cannot qualify under startup-r25.'
}
File.write(output, JSON.pretty_generate(result) + "\n")
puts JSON.generate(result.slice(:passed, :appStartupDurationMs, :launchToSpeechReceiptUpperBoundMs,
  :documentLoadToSpeechReceiptUpperBoundMs, :playToSpeechReceiptUpperBoundMs,
  :firstSignalExpectedSpeechAlignmentMs, :loadClass, :goalMet, :hardLimitMet, :errors))
exit(errors.empty? ? 0 : 1)
