require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'open3'
require 'rbconfig'

class SummarizeStartupAudioTest < Minitest::Test
  def evaluate(elapsed_ms, load_class: 'radoc', native_passed: true, startup_ms: 0)
    Dir.mktmpdir('startup-policy-test-') do |root|
      inputs = {
        'receipt.json' => {passed: native_passed, controlledCaptureGate: false,
          appStartupCompleteMonotonicRawNanos: 1_000_000 + startup_ms * 1_000_000,
          documentLoadRequestedMonotonicRawNanos: 1_000_000 + startup_ms * 1_000_000},
        'runner.json' => {passed: true, normalQuit: true, forcedCleanup: false,
          remainingOwnedPids: [], captureExitStatus: 0, captureIntroducedPlayGate: false,
          launchMonotonicRawNanos: 1_000_000},
        'capture.wav.timing.json' => {firstSignalMonotonicRawNanos: 1_000_000 + (startup_ms + elapsed_ms) * 1_000_000,
          firstSignalFrame: 4800, sampleRate: 48000},
        'comparison.json' => {passed: true, matchedTurns: [{activeSpeechStartSeconds: 0.1, correlation: 0.999}]}
      }
      yield inputs if block_given?
      inputs.each { |name, data| File.write(File.join(root, name), JSON.generate(data)) }
      output = File.join(root, 'result.json')
      _, status = Open3.capture2(RbConfig.ruby, File.join(__dir__, 'summarize_startup_audio.rb'),
        root, File.join(root, 'comparison.json'), output, load_class)
      [JSON.parse(File.read(output)), status.success?]
    end
  end

  def test_long_ordinary_startup_is_reported_separately_and_only_misses_goal
    result, success = evaluate(5000, startup_ms: 20000) do |inputs|
      inputs['receipt.json'][:playRequestedMonotonicRawNanos] = 21_001_000_000
    end
    assert success
    assert_equal 'startup-r25', result['timingPolicy']
    assert_equal 'readaloud-ungated-startup-audio-v3', result['schema']
    assert_equal 20000, result['appStartupDurationMs']
    assert_equal 25000, result['launchToSpeechReceiptUpperBoundMs']
    assert_equal 5000, result['documentLoadToSpeechReceiptUpperBoundMs']
    assert_equal 4000, result['playToSpeechReceiptUpperBoundMs']
    assert result['hardLimitMet']
    refute result['goalMet']
  end

  def test_missing_or_wrong_domain_boundaries_do_not_qualify_historical_receipts
    %i[appStartupCompleteMonotonicRawNanos documentLoadRequestedMonotonicRawNanos].each do |key|
      result, success = evaluate(17000) do |inputs|
        inputs['receipt.json'].delete(key)
        inputs['receipt.json'][:appStartupCompleteUnixMicros] = 1000
        inputs['receipt.json'][:documentLoadRequestedUnixMicros] = 2000
      end
      refute success
      refute result['hardLimitMet']
      assert_nil result['documentLoadToSpeechReceiptUpperBoundMs']
      assert_equal 17000, result['launchToSpeechReceiptUpperBoundMs']
    end
    result, success = evaluate(1000) { |inputs| inputs['capture.wav.timing.json'].delete(:firstSignalMonotonicRawNanos) }
    refute success
    refute result['hardLimitMet']
  end

  def test_reversed_and_cross_window_boundaries_fail
    [
      [:appStartupCompleteMonotonicRawNanos, 0],
      [:appStartupCompleteMonotonicRawNanos, 2_000_000],
      [:documentLoadRequestedMonotonicRawNanos, 0],
      [:documentLoadRequestedMonotonicRawNanos, 2_000_000_000],
      [:documentLoadRequestedMonotonicRawNanos, '1000000']
    ].each do |key, value|
      result, success = evaluate(1000) { |inputs| inputs['receipt.json'][key] = value }
      refute success, "#{key}=#{value}"
      refute result['hardLimitMet']
    end
    _, success = evaluate(1000) { |inputs| inputs['receipt.json'][:playRequestedMonotonicRawNanos] = 0 }
    refute success
  end

  def test_waveform_alignment_gate_and_cleanup_remain_required
    mutations = [
      ->(i) { i['comparison.json'][:matchedTurns].first[:correlation] = 0.979 },
      ->(i) { i['comparison.json'][:passed] = false },
      ->(i) { i['comparison.json'][:matchedTurns].first[:activeSpeechStartSeconds] = 0.151 },
      ->(i) { i['receipt.json'][:controlledCaptureGate] = true },
      ->(i) { i['runner.json'][:captureIntroducedPlayGate] = true },
      ->(i) { i['runner.json'][:normalQuit] = false },
      ->(i) { i['runner.json'][:forcedCleanup] = true },
      ->(i) { i['runner.json'][:remainingOwnedPids] = [123] },
      ->(i) { i['runner.json'][:captureExitStatus] = 1 }
    ]
    mutations.each do |mutate|
      result, success = evaluate(1000, &mutate)
      refute success
      assert result['hardLimitMet']
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
