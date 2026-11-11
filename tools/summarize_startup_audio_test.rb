require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'open3'
require 'rbconfig'

class SummarizeStartupAudioTest < Minitest::Test
  def evaluate(elapsed_ms, load_class: 'radoc', native_passed: true)
    Dir.mktmpdir('startup-policy-test-') do |root|
      inputs = {
        'receipt.json' => {passed: native_passed, controlledCaptureGate: false},
        'runner.json' => {passed: true, normalQuit: true, forcedCleanup: false,
          remainingOwnedPids: [], captureExitStatus: 0, captureIntroducedPlayGate: false,
          launchMonotonicRawNanos: 1_000_000},
        'capture.wav.timing.json' => {firstSignalMonotonicRawNanos: 1_000_000 + elapsed_ms * 1_000_000,
          firstSignalFrame: 4800, sampleRate: 48000},
        'comparison.json' => {passed: true, matchedTurns: [{activeSpeechStartSeconds: 0.1, correlation: 0.999}]}
      }
      inputs.each { |name, data| File.write(File.join(root, name), JSON.generate(data)) }
      output = File.join(root, 'result.json')
      _, status = Open3.capture2(RbConfig.ruby, File.join(__dir__, 'summarize_startup_audio.rb'),
        root, File.join(root, 'comparison.json'), output, load_class)
      [JSON.parse(File.read(output)), status.success?]
    end
  end

  def test_radoc_goal_and_hard_limit_are_separate_and_inclusive
    result, success = evaluate(2000)
    assert success
    assert result['goalMet']
    result, success = evaluate(5000)
    assert success
    refute result['goalMet']
    assert result['hardLimitMet']
    _, success = evaluate(5001)
    refute success
  end

  def test_first_load_uses_ten_second_hard_limit
    result, success = evaluate(10000, load_class: 'first-load')
    assert success
    assert_equal 10000, result['hardLimitMs']
    refute result['goalMet']
    _, success = evaluate(10001, load_class: 'first-load')
    refute success
  end

  def test_timing_cannot_override_failed_native_evidence
    result, success = evaluate(3000, native_passed: false)
    refute success
    assert result['hardLimitMet']
    assert_includes result['errors'], 'Native functional/cleanup check failed'
  end
end
