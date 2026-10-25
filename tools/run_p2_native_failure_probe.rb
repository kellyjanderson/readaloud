#!/usr/bin/env ruby
# Separate p2 build: flutter build macos --debug -t tools/p2_native_failure_probe.dart
require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'timeout'

module P2FailureProbe
  def self.validate(output)
    rows = File.readlines(File.join(output, 'probe/events.jsonl')).map { |line| JSON.parse(line) }
    raise 'Probe incomplete/failed' unless rows.last['event'] == 'complete' && rows.none? { |row| row['event'] == 'failure' }
    names = %w[malformed_model truncated_voice inference_shape]
    %w[case_start expected_error case_complete].each do |event|
      raise "Missing #{event}" unless rows.select { |row| row['event'] == event }.map { |row| row['case'] } == names
    end
    log = File.read(File.join(output, 'native.log'))
    # Scope native observations to each awaited case; native errors must be real.
    cases = names.to_h do |name|
      lines = log.lines
      start = lines.index { |line| line.include?('READALOUD_FAILURE ') && line.include?('"event":"case_start"') && line.include?("\"case\":\"#{name}\"") }
      finish = lines.index { |line| line.include?('READALOUD_FAILURE ') && line.include?('"event":"case_complete"') && line.include?("\"case\":\"#{name}\"") }
      raise "Missing log markers: #{name}" unless start && finish && finish > start
      trace = lines[start..finish].join.scan(/READALOUD_ORT method=(\w+) sessions=(\d+) tensors=(\d+) error=(\w+)/).map { |method, sessions, tensors, error| {method: method, sessions: sessions.to_i, tensors: tensors.to_i, error: error} }
      raise "No native trace: #{name}" if trace.empty?
      raise "Native handles retained: #{name}" unless trace.last[:sessions].zero? && trace.last[:tensors].zero?
      raise 'Unbounded handles' unless trace.all? { |row| row[:sessions] <= 1 && row[:tensors] <= 4 }
      errors = trace.select { |row| row[:error] == 'true' }
      expected = {'malformed_model' => ['createSession'], 'truncated_voice' => [], 'inference_shape' => ['runInference']}.fetch(name)
      raise "Wrong native error evidence: #{name}" unless errors.map { |row| row[:method] } == expected
      counts = trace.group_by { |row| row[:method] }.transform_values(&:length)
      expected_closes = {'malformed_model' => 0, 'truncated_voice' => 2, 'inference_shape' => 1}.fetch(name)
      raise "Unexpected close count: #{name}" unless counts.fetch('closeSession', 0) == expected_closes
      if name == 'inference_shape'
        raise 'Missing successful recovery inference' unless counts['runInference'] == 2
        first = trace.index { |row| row[:method] == 'runInference' }
        second = ((first + 1)...trace.length).find { |index| trace[index][:method] == 'runInference' }
        raise 'Failure tensors not released before recovery' unless trace[(first + 1)...second].any? { |row| row[:tensors].zero? }
      end
      [name, {counts: counts, trace: trace}]
    end
    before = rows.find { |row| row['event'] == 'assets_before' }
    after = rows.find { |row| row['event'] == 'assets_after' }
    %w[model voice].each do |key|
      raise 'Runtime assets changed' unless before[key]['sha256'] == after[key]['sha256'] && Digest::SHA256.file(after[key]['path']).hexdigest == after[key]['sha256']
    end
    recovered_voice = rows.find { |row| row['event'] == 'voice_recovered' }
    raise 'No valid reprepare' unless recovered_voice && recovered_voice['bindings'].length == 1 && recovered_voice['bindings'][0]['voiceDigest'] == after['voice']['sha256']
    audio = rows.find { |row| row['event'] == 'inference_recovered' }
    raise 'No recovered audio' unless audio && File.size(audio['path']) == audio['samples'] * 4 && Digest::SHA256.file(audio['path']).hexdigest == audio['float32Sha256']
    samples = File.binread(audio['path']).unpack('e*')
    raise 'Invalid recovery samples' unless samples.all?(&:finite?) && samples.any? { |sample| sample != 0 }
    {passed: true, cases: cases, runtime_assets: after, recovered_audio: audio, limitation: 'Native failure/cleanup/recovery only; Float32 output is not a WAV or listening claim. No real hung-native scenario.'}
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.first == '--validate'
    abort 'Usage: --validate OUTPUT' unless ARGV.length == 2
    puts JSON.pretty_generate(P2FailureProbe.validate(File.expand_path(ARGV[1])))
    exit 0
  end
  abort 'Usage: run_p2_native_failure_probe.rb APP_EXECUTABLE NEW_OUTPUT_DIR' unless ARGV.length == 2
  app, output = ARGV.map { |value| File.expand_path(value) }
  abort 'Output exists' if File.exist?(output)
  abort 'Missing executable' unless File.executable?(app)
  plist = File.expand_path('../Info.plist', File.dirname(app))
  bundle, status = Open3.capture2('/usr/libexec/PlistBuddy', '-c', 'Print CFBundleIdentifier', plist)
  abort 'Requires isolated com.kellyjanderson.readAloud.p2 bundle' unless status.success? && bundle.strip == 'com.kellyjanderson.readAloud.p2'
  FileUtils.mkdir_p(output)
  metadata = {app: app, bundle_id: bundle.strip, executable_sha256: Digest::SHA256.file(app).hexdigest}
  pid = nil
  begin
    File.open(File.join(output, 'native.log'), 'w') do |log|
      pid = Process.spawn({'READALOUD_ORT_RESOURCE_TRACE' => '1'}, app, File.join(output, 'probe'), out: log, err: log)
      Timeout.timeout(180) { Process.waitpid(pid) }
      metadata[:process_exit] = $?.exitstatus
      pid = nil
    end
    raise "Exit #{metadata[:process_exit]}" unless metadata[:process_exit] == 0
    report = P2FailureProbe.validate(output)
    File.write(File.join(output, 'validation.json'), JSON.pretty_generate(report))
    metadata[:passed] = true
    puts JSON.generate(report.slice(:passed, :cases))
  rescue StandardError => error
    metadata[:passed] = false
    metadata[:error] = error.message
    warn error.full_message
  ensure
    if pid
      metadata[:harness_terminated] = true
      Process.kill('TERM', pid) rescue Errno::ESRCH
      begin
        Timeout.timeout(5) { Process.waitpid(pid) }
      rescue Timeout::Error
        Process.kill('KILL', pid) rescue Errno::ESRCH
        Process.waitpid(pid) rescue Errno::ECHILD
      end
    end
    File.write(File.join(output, 'run.json'), JSON.pretty_generate(metadata))
  end
  exit(metadata[:passed] ? 0 : 1)
end
