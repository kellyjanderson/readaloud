#!/usr/bin/env ruby
# Combine ungated app launch, app-only signal receipt and exact waveform proof.
require 'json'
abort 'Usage: summarize_startup_audio.rb NATIVE_OUTPUT_DIRECTORY COMPARISON_JSON NEW_RESULT_JSON' unless ARGV.length == 3
dir, comparison_path, output = ARGV.map { |p| File.expand_path(p) }
abort 'Output already exists' if File.exist?(output)
read = ->(name) { JSON.parse(File.read(File.join(dir, name))) }
native = read.call('receipt.json')
runner = read.call('runner.json')
capture = read.call('capture.wav.timing.json')
comparison = JSON.parse(File.read(comparison_path))
first = comparison.fetch('matchedTurns').first or abort 'Missing expected speech match'
launch = runner.fetch('launchMonotonicRawNanos')
signal = capture.fetch('firstSignalMonotonicRawNanos')
elapsed = (signal - launch) / 1_000_000.0
observed_start = capture.fetch('firstSignalFrame') / capture.fetch('sampleRate').to_f
alignment = (observed_start - first.fetch('activeSpeechStartSeconds')).abs * 1000
errors = []
errors << 'A controlled Play gate was used' unless native['controlledCaptureGate'] == false && runner['captureIntroducedPlayGate'] == false
errors << 'Native functional/cleanup check failed' unless native['passed'] && runner['passed'] && runner['normalQuit'] && !runner['forcedCleanup'] && runner['remainingOwnedPids'] == [] && runner['captureExitStatus'] == 0
errors << 'Expected waveform/continuity check failed' unless comparison['passed'] && comparison.fetch('matchedTurns').all? { |m| m.fetch('correlation') >= 0.98 }
errors << 'First captured signal does not align with expected speech' unless alignment.finite? && alignment <= 50
errors << 'Opening to captured speech exceeds two seconds' unless elapsed.finite? && elapsed >= 0 && elapsed <= 2000
result = {
  schema: 'readaloud-ungated-startup-audio-v1',
  passed: errors.empty?, errors: errors,
  launchToSpeechReceiptUpperBoundMs: elapsed,
  firstSignalExpectedSpeechAlignmentMs: alignment,
  launchToNativePositionMs: native['launchToNativePositionMs'],
  waveformComparison: comparison_path,
  limits: 'CLOCK_MONOTONIC_RAW from immediately before process spawn to receipt of the first signal-bearing app-only packet, aligned with the exact expected waveform. An upper bound on app-emitted speech, not physical speaker latency or human listening. Candidate completeness and fresh-profile provenance must be verified separately.'
}
File.write(output, JSON.pretty_generate(result) + "\n")
puts JSON.generate(result.slice(:passed, :launchToSpeechReceiptUpperBoundMs, :firstSignalExpectedSpeechAlignmentMs, :errors))
exit(errors.empty? ? 0 : 1)
