require 'minitest/autorun'
require_relative 'rc2_timing_report'

class Rc2TimingReportTest < Minitest::Test
  def receipt
    {'schema' => 'readaloud-rc2-timing-v1', 'candidate' => {
      'commit' => 'fixture', 'binary_sha256' => 'a' * 64, 'host' => 'fixture M5',
      'architecture' => 'arm64', 'build_mode' => 'release',
      'entrypoint' => 'lib/main.dart', 'capture_route' => 'fixture loopback'
    }, 'cases' => [{'id' => 'fixture', 'condition' => 'fresh', 'fixture_sha256' => 'b' * 64,
      'trials' => 10.times.map { |i| {'id' => i.to_s, 'valid' => true,
        'clock_domain' => 'fixture monotonic', 'launch_us' => 1000,
        'first_interactive_us' => 100_000, 'play_us' => 110_000,
        'first_pcm_us' => 500_000, 'audible_us' => 1_001_000,
        'input_ack_us' => 10_000, 'max_main_stall_us' => 20_000,
        'environment' => 'synthetic unit-test data; not app evidence',
        'output_evidence' => {'path' => 'fixture.wav', 'sha256' => 'c' * 64,
          'route' => 'fixture', 'basis' => 'recorded-output',
          'clock_mapping' => 'fixture', 'onset_method' => 'fixture'}} }}]}
  end

  def trials(input)
    input['cases'].first['trials']
  end

  def test_reports_all_samples_and_nearest_rank_percentiles
    result = Rc2TimingReport.evaluate(receipt)
    assert_equal 'pass', result[:verdict]
    assert_equal [1000.0] * 10, result[:cases].first[:launch_to_audible][:samples_ms]
    assert_equal 1000.0, result[:cases].first[:launch_to_audible][:p99_ms]
  end

  def test_one_slow_trial_cannot_hide_behind_mean_or_percentile
    input = receipt
    trials(input).last['audible_us'] = 2_002_000
    result = Rc2TimingReport.evaluate(input)
    assert_equal 'fail', result[:verdict]
    assert_equal 2001.0, result[:cases].first[:launch_to_audible][:max_ms]
  end

  def test_pcm_or_player_callback_cannot_replace_actual_output
    input = receipt
    trials(input).first.delete('audible_us')
    assert_equal 'fail', Rc2TimingReport.evaluate(input)[:verdict]
    trials(input).first['audible_us'] = 900_000
    trials(input).first['output_evidence']['basis'] = 'player-callback'
    assert_equal 'fail', Rc2TimingReport.evaluate(input)[:verdict]
  end

  def test_invalid_attempts_remain_visible_and_do_not_count_toward_ten
    input = receipt
    trials(input).first.merge!('valid' => false, 'invalid_reason' => 'missing input')
    result = Rc2TimingReport.evaluate(input)
    assert_equal 'fail', result[:verdict]
    assert_equal 'invalid', result[:cases].first[:trials].first[:verdict]
    trials(input) << trials(input).last.merge('id' => 'replacement')
    assert_equal 'pass', Rc2TimingReport.evaluate(input)[:verdict]
  end

  def test_out_of_order_clock_ui_stall_and_missing_environment_fail
    %w[clock_domain environment].each do |key|
      input = receipt
      trials(input).first.delete(key)
      assert_equal 'fail', Rc2TimingReport.evaluate(input)[:verdict]
    end
    input = receipt
    trials(input).first['play_us'] = 1
    assert_equal 'fail', Rc2TimingReport.evaluate(input)[:verdict]
    input = receipt
    trials(input).first['max_main_stall_us'] = 100_001
    assert_equal 'fail', Rc2TimingReport.evaluate(input)[:verdict]
  end

  def test_exact_limits_pass_and_document_intake_is_measured_separately
    input = receipt
    trials(input).first.merge!('document_open_us' => 50_000, 'audible_us' => 2_001_000,
                              'input_ack_us' => 100_000, 'max_main_stall_us' => 100_000)
    result = Rc2TimingReport.evaluate(input)
    assert_equal 'pass', result[:verdict]
    assert_equal [1951.0], result[:cases].first[:document_open_to_audible][:samples_ms]
  end

  def test_empty_matrix_and_non_native_debug_build_fail
    input = receipt
    input['cases'] = []
    assert_equal 'fail', Rc2TimingReport.evaluate(input)[:verdict]
    input = receipt
    input['candidate']['build_mode'] = 'debug'
    assert_equal 'fail', Rc2TimingReport.evaluate(input)[:verdict]
  end

  def test_post_launch_intake_uses_document_open_clock_without_erasing_launch
    input = receipt
    input['cases'].first['scenario'] = 'document-open'
    trials(input).each do |trial|
      trial.merge!('document_open_us' => 10_000_000, 'play_us' => 10_100_000,
                   'first_pcm_us' => 10_500_000, 'audible_us' => 11_000_000)
    end
    result = Rc2TimingReport.evaluate(input)
    assert_equal 'pass', result[:verdict]
    assert_equal 1000.0, result[:cases].first[:document_open_to_audible][:max_ms]
    assert_equal 10_999.0, result[:cases].first[:launch_to_audible][:max_ms]
    trials(input).first.delete('document_open_us')
    assert_equal 'fail', Rc2TimingReport.evaluate(input)[:verdict]
  end

  def test_prefetching_pcm_before_play_is_allowed_but_audio_before_play_fails
    input = receipt
    trials(input).first['first_pcm_us'] = 50_000
    assert_equal 'pass', Rc2TimingReport.evaluate(input)[:verdict]
    trials(input).first['audible_us'] = 109_999
    assert_equal 'fail', Rc2TimingReport.evaluate(input)[:verdict]
  end
end
