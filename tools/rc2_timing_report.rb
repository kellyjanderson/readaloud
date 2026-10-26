#!/usr/bin/env ruby
# Refs #83, #86. Offline evidence validation; never launches or changes the app.
# Input is a JSON object with candidate and cases. Each case has id, condition
# (fresh/warm/radoc), scenario (launch/document-open; defaults to launch),
# fixture_sha256 and trials. Each trial has id, valid (bool),
# monotonic microsecond events, input_ack_us, max_main_stall_us and output_evidence
# {path, sha256, route, basis: "recorded-output"}. Events are launch_us,
# first_interactive_us, play_us, first_pcm_us, audible_us. For intake after launch,
# also supply document_open_us. first_pcm_us/player callbacks are NOT audible_us.
# All timestamps must share an explicitly identified clock_domain per trial.
# The capture owner supplies actual output onset, including capture clock mapping.
# Candidate requires commit, binary_sha256, host, architecture, build_mode,
# entrypoint, capture_route. This validates receipts, not their authenticity or
# acoustic meaning; original captures/traces must still be independently checked.
require 'json'

module Rc2TimingReport
  EVENTS = %w[launch_us first_interactive_us play_us first_pcm_us audible_us].freeze
  LIMIT_US = 2_000_000
  UI_LIMIT_US = 100_000
  SHA256 = /\A[0-9a-f]{64}\z/

  def self.percentiles(values)
    sorted = values.sort
    return nil if sorted.empty?
    {samples_ms: values.map { |n| n / 1000.0 },
     max_ms: sorted.last / 1000.0,
     p50_ms: sorted[(sorted.length * 0.50).ceil - 1] / 1000.0,
     p95_ms: sorted[(sorted.length * 0.95).ceil - 1] / 1000.0,
     p99_ms: sorted[(sorted.length * 0.99).ceil - 1] / 1000.0}
  end

  def self.evaluate(input)
    errors = []
    errors << 'schema must be readaloud-rc2-timing-v1' unless input['schema'] == 'readaloud-rc2-timing-v1'
    candidate = input.fetch('candidate', {})
    %w[commit binary_sha256 host architecture build_mode entrypoint capture_route].each do |key|
      errors << "candidate.#{key} missing" if candidate[key].to_s.empty?
    end
    errors << 'candidate must be arm64 release using lib/main.dart' unless
      candidate.values_at('architecture', 'build_mode', 'entrypoint') == %w[arm64 release lib/main.dart]
    errors << 'candidate.binary_sha256 invalid' unless SHA256.match?(candidate['binary_sha256'].to_s)
    cases = input.fetch('cases', [])
    errors << 'no cases supplied' if cases.empty?
    errors << 'duplicate case IDs' unless cases.map { |c| c['id'] }.uniq.length == cases.length
    results = cases.map do |record|
      case_errors = []
      case_errors << 'case id missing' if record['id'].to_s.empty?
      case_errors << 'condition must be fresh/warm/radoc' unless %w[fresh warm radoc].include?(record['condition'])
      scenario = record.fetch('scenario', 'launch')
      case_errors << 'scenario must be launch/document-open' unless %w[launch document-open].include?(scenario)
      case_errors << 'fixture_sha256 invalid' unless SHA256.match?(record['fixture_sha256'].to_s)
      trials = record.fetch('trials', [])
      case_errors << 'at least ten valid trials required' if trials.count { |t| t['valid'] == true } < 10
      case_errors << 'duplicate trial IDs' unless trials.map { |t| t['id'] }.uniq.length == trials.length
      samples = []
      open_samples = []
      trial_results = trials.map do |trial|
        problems = []
        problems << 'trial id missing' if trial['id'].to_s.empty?
        if trial['valid'] != true
          # Retain invalid attempts; the runner must explain them and add trials.
          problems << 'invalid attempt needs a recorded reason' if trial['invalid_reason'].to_s.empty?
          next({id: trial['id'], verdict: problems.empty? ? 'invalid' : 'incomplete', errors: problems,
                invalid_reason: trial['invalid_reason']})
        end
        problems << 'clock_domain missing' if trial['clock_domain'].to_s.empty?
        events = EVENTS.map { |key| trial[key] }
        problems << 'required monotonic timestamps missing/invalid' unless events.all? { |n| n.is_a?(Numeric) && n.finite? && n >= 0 }
        if problems.empty?
          # First PCM may be prefetched before the user requests Play. Playback
          # must still follow Play; prefetch is not permission to autoplay.
          ordered = trial.values_at('launch_us', 'first_interactive_us', 'play_us', 'audible_us')
          problems << 'events out of order' unless ordered.each_cons(2).all? { |a, b| a <= b } &&
            trial['first_pcm_us'].between?(trial['launch_us'], trial['audible_us'])
          latency = trial['audible_us'] - trial['launch_us']
          samples << latency
          problems << 'launch-to-audible exceeds 2000 ms' if scenario == 'launch' && latency > LIMIT_US
          problems << 'document-open trial is missing document_open_us' if scenario == 'document-open' && !trial.key?('document_open_us')
          if trial.key?('document_open_us')
            opened = trial['document_open_us']
            if !opened.is_a?(Numeric) || !opened.finite? || opened < trial['launch_us'] || opened > trial['play_us']
              problems << 'document_open_us invalid'
            else
              open_samples << trial['audible_us'] - opened
              problems << 'document-open-to-audible exceeds 2000 ms' if open_samples.last > LIMIT_US
            end
          end
        end
        %w[input_ack_us max_main_stall_us].each do |key|
          duration = trial[key]
          if !duration.is_a?(Numeric) || !duration.finite? || duration < 0
            problems << "#{key} missing/invalid"
          elsif duration > UI_LIMIT_US
            problems << "#{key} exceeds 100 ms"
          end
        end
        evidence = trial.fetch('output_evidence', {})
        problems << 'recorded actual output evidence missing' unless
          evidence['basis'] == 'recorded-output' && SHA256.match?(evidence['sha256'].to_s) &&
          %w[path route clock_mapping onset_method].all? { |key| !evidence[key].to_s.empty? }
        problems << 'environment/contention description missing' if trial['environment'].to_s.empty?
        {id: trial['id'], verdict: problems.empty? ? 'pass' : 'fail', errors: problems,
         events_us: trial.select { |key, _| EVENTS.include?(key) || key == 'document_open_us' }}
      end
      case_errors << 'one or more trials failed or are incomplete' if trial_results.any? { |r| %w[fail incomplete].include?(r[:verdict]) }
      {id: record['id'], condition: record['condition'], scenario: scenario, fixture_sha256: record['fixture_sha256'],
       verdict: case_errors.empty? ? 'pass' : 'fail', errors: case_errors,
       launch_to_audible: percentiles(samples), document_open_to_audible: percentiles(open_samples),
       trials: trial_results}
    end
    errors << 'one or more cases failed' if results.any? { |c| c[:verdict] != 'pass' }
    {schema: 'readaloud-rc2-timing-report-v1', verdict: errors.empty? ? 'pass' : 'fail',
     errors: errors, candidate: candidate, cases: results,
     limits: ['Receipt validation does not prove acoustic onset or capture accuracy.',
              'A passing supplied case set does not prove the full #83 fixture/condition matrix.',
              'Continuity, progress, cancel/stale work and UI interactions need separate evidence.']}
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: ruby tools/rc2_timing_report.rb RECEIPT.json' unless ARGV.length == 1
  begin
    result = Rc2TimingReport.evaluate(JSON.parse(File.read(ARGV.first)))
    puts JSON.pretty_generate(result)
    exit(result[:verdict] == 'pass' ? 0 : 1)
  rescue JSON::ParserError, KeyError, TypeError, NoMethodError => error
    warn "Invalid timing receipt: #{error.message}"
    exit 2
  end
end
