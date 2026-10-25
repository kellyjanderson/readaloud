#!/usr/bin/env ruby
# Launch a separately built p2 probe. Never qualifies live playback continuity.
require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'timeout'
require_relative 'run_native_baseline'

module P2NativeProbe
  def self.wav(path, ffmpeg)
    bytes = File.binread(path)
    raise "Invalid RIFF length: #{path}" unless bytes[0, 4] == 'RIFF' && bytes[8, 4] == 'WAVE' && bytes[4, 4].unpack1('V') + 8 == bytes.bytesize
    offset = 12
    pcm = format = nil
    while offset + 8 <= bytes.bytesize
      tag = bytes[offset, 4]
      size = bytes[offset + 4, 4].unpack1('V')
      payload = bytes[offset + 8, size]
      raise 'Truncated WAV chunk' unless payload && payload.bytesize == size
      format = payload.unpack('vvVVvv') if tag == 'fmt '
      pcm = payload if tag == 'data'
      offset += 8 + size + size % 2
    end
    raise 'Expected nonempty mono PCM16 at 24kHz' unless format && format[0] == 1 && format[1] == 1 && format[2] == 24_000 && format[4] == 2 && format[5] == 16 && pcm && !pcm.empty? && pcm.bytesize.even?
    _, error, status = Open3.capture3(ffmpeg, '-v', 'error', '-xerror', '-i', path, '-f', 'null', '-')
    raise "Strict decode failed: #{error}" unless status.success?
    {frames: pcm.bytesize / 2, pcm_sha256: Digest::SHA256.hexdigest(pcm), wav_sha256: Digest::SHA256.hexdigest(bytes), strict_decode_exit: status.exitstatus}
  end

  def self.validate(output, ffmpeg: ENV.fetch('FFMPEG', '/opt/homebrew/bin/ffmpeg'))
    records = File.readlines(File.join(output, 'probe', 'events.jsonl')).map { |line| JSON.parse(line) }
    raise 'Missing success or recorded failure' unless records.last['kind'] == 'complete' && records.none? { |item| item['kind'] == 'failure' }
    chunks = records.select { |item| item['kind'] == 'chunk' }
    raise 'Expected 306 unique uncached chunks' unless chunks.length == 306 && chunks.map { |item| item['path'] }.uniq.length == 306 && chunks.all? { |item| !item['events'].include?('cacheHit') && item['events'].include?('inferencing') }
    lifecycle = records.select { |item| %w[prepared released disposed complete].include?(item['kind']) }
    raise 'Missing awaited lifecycle stages' unless lifecycle.map { |item| item['kind'] } == %w[prepared released prepared disposed prepared disposed complete]
    [300, 3, 3].each_with_index do |count, cycle|
      raise 'Incorrect cycle sequence' unless chunks.select { |item| item['cycle'] == cycle }.map { |item| item['index'] } == (0...count).to_a
    end
    chunks.each do |item|
      expected_voice = item['index'] % 3 == 1 ? 'am_fenrir' : 'af_bella'
      raise 'Route mismatch' unless item['voiceId'] == expected_voice
      verified = wav(item['path'], ffmpeg)
      raise 'Recorded hash differs from WAV' unless verified[:pcm_sha256] == item['pcmSha256'] && verified[:wav_sha256] == item['wavSha256']
      raise 'Duration mismatch' unless (item['durationMillis'] - verified[:frames] / 24.0).abs <= 0.5
      item['verified'] = verified
    end
    before = records.find { |item| item['kind'] == 'assets_before' }
    after = records.find { |item| item['kind'] == 'assets_after' }
    raise 'Missing assets' unless before && after
    %w[model af_bella am_fenrir].each do |key|
      raise 'Runtime asset changed' unless before[key]['sha256'] == after[key]['sha256'] && Digest::SHA256.file(after[key]['path']).hexdigest == after[key]['sha256']
    end
    prepared = records.select { |item| item['kind'] == 'prepared' }
    raise 'Missing prepare cycles' unless prepared.map { |item| item['cycle'] } == [0, 1, 2]
    prepared.each do |item|
      raise 'Missing voice bindings' unless item['bindings'].map { |binding| binding['voiceId'] }.sort == %w[af_bella am_fenrir]
      item['bindings'].each do |binding|
        raise 'Binding asset digest mismatch' unless binding['modelDigest'] == after['model']['sha256'] && binding['voiceDigest'] == after[binding['voiceId']]['sha256']
      end
    end
    log = File.read(File.join(output, 'native.log'))
    native = log.scan(/READALOUD_ORT method=(\w+) sessions=(\d+) tensors=(\d+) error=(\w+)/).map { |method, sessions, tensors, error| {method: method, sessions: sessions.to_i, tensors: tensors.to_i, error: error} }
    raise 'Missing native trace' if native.empty?
    raise 'Native error/resource bound' unless native.all? { |item| item[:error] == 'false' && item[:sessions] <= 1 && item[:tensors] <= 4 }
    counts = native.group_by { |item| item[:method] }.transform_values(&:length)
    raise "Unexpected inference/session counts: #{counts}" unless counts['runInference'] == 306 && counts['createSession'] == 3 && counts['closeSession'] == 3
    inference_indexes = native.each_index.select { |index| native[index][:method] == 'runInference' }
    inference_indexes.each_with_index do |start, index|
      finish = inference_indexes[index + 1] || native.length
      raise 'Tensors did not return to zero between inferences' unless native[(start + 1)...finish].any? { |item| item[:tensors].zero? }
    end
    closes = native.select { |item| item[:method] == 'closeSession' }
    raise 'Close did not drain resources' unless closes.all? { |item| item[:sessions].zero? && item[:tensors].zero? } && native.last[:sessions].zero? && native.last[:tensors].zero?
    resource = log.lines.filter_map do |line|
      match = line.match(/READALOUD_RESOURCE (\{.*\})/)
      JSON.parse(match[1]) if match
    end
    loads = resource.select { |item| item['event'] == 'prepared' }
    raise 'Missing/incorrect voice residency counters' unless loads.length == 3 && loads.all? { |item| item['loadedVoiceCount'] == 2 } && loads.map { |item| item['loadCount'] } == [2, 4, 2]
    resource.each_with_index do |item, index|
      next unless item['event'] == 'prepared'
      release = resource[(index + 1)..].find { |event| event['event'] == 'released' }
      raise 'Voices reloaded during chunks or release missing' unless release && release['loadedVoiceCount'] == 0 && release['loadCount'] == item['loadCount']
    end
    same_voice = chunks.group_by { |item| item['voiceId'] }.transform_values do |items|
      {unique_pcm_hashes: items.map { |item| item['pcmSha256'] }.uniq, bit_identical: items.map { |item| item['pcmSha256'] }.uniq.length == 1}
    end
    # Floating-point model output may vary: report equality, never label it acoustic quality.
    warm = chunks.select { |item| item['cycle'] == 0 && item['index'] >= 30 }
    rss = warm.map { |item| item['rssBytes'] }
    report = {
      passed: true, chunks: chunks.length, native_counts: counts, native_snapshots: native,
      peak_sessions: native.map { |item| item[:sessions] }.max, peak_tensors: native.map { |item| item[:tensors] }.max,
      final_resources: native.last, resource_events: resource, runtime_assets: after,
      fixture: records.find { |item| item['kind'] == 'fixture' }, prepared: prepared,
      same_voice_pcm: same_voice, post_warmup_rss_bytes: {min: rss.min, max: rss.max, first: rss.first, last: rss.last, last_minus_first: rss.last - rss.first},
      verified_chunks: chunks, lifecycle: records.select { |item| %w[prepared released disposed complete].include?(item['kind']) },
      limitation: 'Uncached native synthesis and explicit lifecycle only. RSS is measured, not a universal stability threshold. No live transport, pause/resume, perceptual voice identity or audio continuity claim.'
    }
    File.write(File.join(output, 'validation.json'), JSON.pretty_generate(report))
    report
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.first == '--validate'
    abort 'Usage: --validate OUTPUT_DIR' unless ARGV.length == 2
    report = P2NativeProbe.validate(File.expand_path(ARGV[1]))
    puts JSON.generate(report.slice(:passed, :chunks, :native_counts, :post_warmup_rss_bytes, :same_voice_pcm))
    exit 0
  end
  abort 'Usage: run_p2_native_probe.rb APP_EXECUTABLE NEW_OUTPUT_DIR' unless ARGV.length == 2
  app, output = ARGV.map { |value| File.expand_path(value) }
  abort 'Output already exists' if File.exist?(output)
  abort 'App executable missing' unless File.executable?(app)
  plist = File.expand_path('../Info.plist', File.dirname(app))
  bundle, status = Open3.capture2('/usr/libexec/PlistBuddy', '-c', 'Print CFBundleIdentifier', plist)
  abort 'Requires isolated com.kellyjanderson.readAloud.p2 bundle' unless status.success? && bundle.strip == 'com.kellyjanderson.readAloud.p2'
  root = File.expand_path('..', __dir__)
  bundled = File.expand_path('../Frameworks/App.framework/Resources/flutter_assets/assets/kokoro', File.dirname(app))
  snapshots = {source: NativeBaselineAssets.snapshot(File.join(root, 'assets/kokoro')), bundled: NativeBaselineAssets.snapshot(bundled)}
  FileUtils.mkdir_p(output)
  metadata = {app: app, bundle_id: bundle.strip, git_head: Open3.capture2('git', '-C', root, 'rev-parse', 'HEAD').first.strip, asset_snapshots: snapshots, executable_sha256: Digest::SHA256.file(app).hexdigest}
  pid = nil
  begin
    File.open(File.join(output, 'native.log'), 'w') do |log|
      pid = Process.spawn({'READALOUD_ORT_RESOURCE_TRACE' => '1'}, app, File.join(output, 'probe'), out: log, err: log, chdir: root)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      File.open(File.join(output, 'memory.csv'), 'w') do |memory|
        memory.puts 'elapsed_seconds,rss_kib'
        loop do
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          memory.puts "#{elapsed.round(3)},#{IO.popen(['ps', '-o', 'rss=', '-p', pid.to_s], &:read).strip}"
          memory.flush
          if Process.waitpid(pid, Process::WNOHANG)
            metadata[:process_exit] = $?.exitstatus
            pid = nil
            break
          end
          raise 'Probe deadline exceeded (1800s)' if elapsed > 1800
          sleep 1 # Process/RSS sampling only; correctness uses awaited probe events.
        end
      end
    end
    raise "Probe exit #{metadata[:process_exit]}" unless metadata[:process_exit] == 0
    report = P2NativeProbe.validate(output)
    metadata[:passed] = report[:passed]
    metadata[:runtime_matches_bundle] = {'model' => 'model/kokoro-v1.0.onnx', 'af_bella' => 'voices/af_bella.npy', 'am_fenrir' => 'voices/am_fenrir.npy'}.to_h do |runtime_key, key|
      [key, report[:runtime_assets][runtime_key]['sha256'] == snapshots[:bundled].fetch(key).fetch(:sha256)]
    end
    raise 'Bundled/runtime asset mismatch' unless metadata[:runtime_matches_bundle].values.all?
    puts JSON.generate(report.slice(:passed, :chunks, :native_counts, :post_warmup_rss_bytes, :same_voice_pcm))
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
