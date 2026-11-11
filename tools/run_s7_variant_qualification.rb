#!/usr/bin/env ruby
# #112 ACD-M1 R1. Reuses the signed-app smoke runner's bounded ownership model.
# Model acquisition is through the app's existing managed cache; no aliases.
require 'json'
require 'digest'
require 'fileutils'
require 'timeout'
require 'rbconfig'

MODES = %w[default-policy cached-bf16 cached-8bit cached-4bit cached-aba online-cancel-retry].freeze
abort 'Usage: run_s7_variant_qualification.rb APP MODE NEW_OUTPUT CAPTURE' unless ARGV.size == 4
bundle, mode, output, capture = ARGV
bundle, output, capture = [bundle, output, capture].map { |p| File.expand_path(p) }
secondary_capture = ENV['READALOUD_S7_SECONDARY_CAPTURE']
secondary_capture = File.expand_path(secondary_capture) if secondary_capture
abort 'Missing secondary capture executable' if secondary_capture && !File.executable?(secondary_capture)
abort 'Invalid mode' unless MODES.include?(mode)
if mode == 'online-cancel-retry' && ENV['READALOUD_S7_ALLOW_DOWNLOAD'] != '1'
  abort 'Online mode requires READALOUD_S7_ALLOW_DOWNLOAD=1 (may download managed model files)'
end
app = File.join(bundle, 'Contents/MacOS/read_aloud')
abort 'Missing app/capture or existing output' unless File.executable?(app) && File.executable?(capture) && !File.exist?(output)
abort 'Signature failure' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
identity = IO.popen(['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier', File.join(bundle, 'Contents/Info.plist')], &:read).strip
abort 'Requires isolated mlxPlaybackTest identity' unless identity == 'com.kellyjanderson.readAloud.mlxPlaybackTest'
abort 'QA app already running' unless IO.popen(['/usr/bin/pgrep', '-f', '^' + Regexp.escape(app) + '( |$)'], &:read).split.empty?
FileUtils.mkdir_p(output)
receipt = File.join(output, 'receipt.json')
log_path = File.join(output, 'app.log')
stop = File.join(output, 'capture.stop')
result = {schema: 'readaloud-native-variant-runner-v1', mode: mode,
          passed: false, nativePassed: false, normalQuit: false,
          appExitVerified: false, forcedCleanup: false, remainingOwnedPids: [],
          frameworkSha256: Digest::SHA256.file(File.join(bundle, 'Contents/Frameworks/App.framework/App')).hexdigest,
          executableSha256: Digest::SHA256.file(app).hexdigest,
          maxMlxChildren: 0, observedMlxSamples: 0, processEvents: [], errors: [],
          limits: '100ms child/process observations and emitted signal per playback interval. ' \
                  'Exact waveform matching, glitch/voice quality, total memory envelope, ' \
                  'physical-speaker and M3 acceptance remain separate. Capture 300s; work deadline 270s.'}
pid = cap = log = capture_log = secondary_cap = secondary_log = nil
status = nil
owned = []
last_children = nil
native = nil
profiles = []
profile_stalls = ENV['READALOUD_S7_PROFILE_STALLS'] == '1'
profile_continuously = ENV['READALOUD_S7_PROFILE_STALLS'] == 'continuous'
profile_instruments = ENV['READALOUD_S7_PROFILE_STALLS'] == 'timeprofiler'
if profile_stalls || profile_continuously || profile_instruments
  result[:diagnosticProfiling] = true
  result[:errors] << 'Diagnostic native sampling enabled; timing is instrumented'
end
if ENV['READALOUD_S7_LAZY_NATIVE_PREPARATION'] == '1'
  result[:lazyNativePreparationExperiment] = true
  result[:errors] << 'QA-only native preparation comparison; production default unchanged'
end
# Read only bounded uncompressed PCM or float WAV. This checks app-emitted signal
# separately from player intent, never labels energy as an exact speech match.
def emitted_signal(path, timing_path, segments)
  timing = JSON.parse(File.read(timing_path))
  bytes = File.binread(path)
  raise 'Capture size bound' if bytes.bytesize > 300 * 192_000 * 8 + 4096
  raise 'Not RIFF/WAVE capture' unless bytes[0, 4] == 'RIFF' && bytes[8, 4] == 'WAVE'
  offset = 12
  format = data = nil
  while offset + 8 <= bytes.bytesize
    tag = bytes[offset, 4]
    count = bytes[offset + 4, 4].unpack1('V')
    raise 'Truncated WAV chunk' if offset + 8 + count > bytes.bytesize
    format = bytes[offset + 8, count] if tag == 'fmt '
    data = bytes[offset + 8, count] if tag == 'data'
    offset += 8 + count + count % 2
  end
  raise 'Capture missing format/data' unless format && data && format.bytesize >= 16
  encoding, channels, rate, _, align, bits = format.unpack('vvVVvv')
  raise 'Unsupported capture format' unless [44_100, 48_000].include?(rate) && channels.between?(1, 2) &&
    [[1, 16], [3, 32]].include?([encoding, bits]) && align == channels * bits / 8
  frames = data.bytesize / align
  raise 'Capture timing mismatch' unless rate == timing['sampleRate'] && frames == timing['frames'] && frames <= rate * 300
  origin = timing.fetch('firstPacketReceivedUnixMicros')
  raise 'Missing capture signal' unless timing['firstSignalReceivedUnixMicros'].is_a?(Integer)
  segments.map do |segment|
    from = ((segment.fetch('firstPositionUnixMicros') - origin) * rate / 1_000_000.0).round
    finish = ((segment.fetch('pauseRequestedUnixMicros') - origin) * rate / 1_000_000.0).round
    raise 'Capture does not cover playback interval' unless from >= 0 && finish <= frames && finish > from
    active = 0
    silent_run = max_silent = 0
    peak = 0.0
    # 100ms windows, any channel. A 200ms edge guard permits callback delivery
    # variance; this is not a startup latency or sample-accurate alignment clock.
    window = rate / 10
    ((from + rate / 5)...(finish - rate / 5)).step(window) do |start|
      count = [window, finish - rate / 5 - start].min
      chunk = data.byteslice(start * align, count * align)
      values = encoding == 3 ? chunk.unpack('e*') : chunk.unpack('s<*').map { |v| v / 32768.0 }
      raise 'Invalid capture samples' unless values.all?(&:finite?)
      value = values.map(&:abs).max || 0.0
      peak = [peak, value].max
      if value > 0.001
        active += 1
        silent_run = 0
      else
        silent_run += 1
        max_silent = [max_silent, silent_run].max
      end
    end
    duration = (finish - from) / rate.to_f
    raise 'Insufficient app-emitted signal during playback' unless active * 0.1 >= duration * 0.55 && max_silent <= 20 && peak > 0.01
    {label: segment['label'], durationSeconds: duration, activeWindowSeconds: active * 0.1,
     longestSilentWindowSeconds: max_silent * 0.1, peak: peak,
     passed: true, scope: '100ms app-only signal windows; not waveform identity or acoustic continuity acceptance'}
  end
end

begin
  log = File.open(log_path, 'w')
  env = {'HF_HUB_OFFLINE' => mode == 'online-cancel-retry' ? nil : '1',
         'READALOUD_MLX_PYTHON' => nil, 'READALOUD_MLX_TTS_MODEL_PATH' => nil,
         'READALOUD_S7_INSPECT' => nil}
  pid = Process.spawn(env, app, mode, receipt, out: log, err: log, pgroup: true)
  result[:pid] = pid
  capture_log = File.open(File.join(output, 'capture.log'), 'w')
  cap = Process.spawn(capture, pid.to_s, File.join(output, 'capture.wav'), '300', stop,
                      out: capture_log, err: capture_log)
  result[:capturePid] = cap
  if secondary_capture
    secondary_log = File.open(File.join(output, 'coreaudio.log'), 'w')
    secondary_cap = Process.spawn(secondary_capture, pid.to_s,
      File.join(output, 'coreaudio.wav'), '300', stop, out: secondary_log, err: secondary_log)
    result[:secondaryCapture] = {mechanism: 'CoreAudio process tap', pid: secondary_cap,
      executableSha256: Digest::SHA256.file(secondary_capture).hexdigest,
      scope: 'Independent diagnostic recording; primary acceptance gates remain unchanged'}
  end
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 270
  activated = false
  capture_ready = false
  until File.exist?(receipt)
    raise 'Native app exited before receipt' if Process.waitpid(pid, Process::WNOHANG)
    raise 'Variant probe 270s deadline' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    if (profile_continuously || profile_instruments) && profiles.empty? &&
        File.read(log_path).include?('S7_VARIANT_NATIVE_STARTED')
      result[:nativeSamplingStartedUnixMicros] = (Time.now.to_r * 1_000_000).to_i
      command = if profile_instruments
        options = JSON.parse(IO.popen(['/usr/bin/xcrun', 'xctrace', 'record',
          '--template', 'Time Profiler', '--show-recording-options'], &:read))
        options.fetch('Time Profiler')['recordWaitingThreads'] = true
        options_path = File.join(output, 'native-recording-options.json')
        File.write(options_path, JSON.pretty_generate(options) + "\n")
        result[:nativeRecordingOptions] = options
        ['/usr/bin/xcrun', 'xctrace', 'record', '--template', 'Time Profiler',
         '--attach', pid.to_s, '--time-limit', '70s', '--recording-options', options_path,
         '--output', File.join(output, 'native-time.trace')]
      else
        ['/usr/bin/sample', pid.to_s, '70', '10', '-file', File.join(output, 'native-continuous.sample.txt')]
      end
      profiles << Process.spawn(*command, out: log, err: log)
    end
    if profile_stalls && profiles.length < 4 &&
        File.read(log_path).scan('NATIVE_MAIN_PROBE_PENDING').length > profiles.length
      path = File.join(output, "native-stall-#{profiles.length + 1}.sample.txt")
      profiles << Process.spawn('/usr/bin/sample', pid.to_s, '1', '2', '-file', path,
        out: log, err: log)
    end
    wave = File.join(output, 'capture.wav')
    # Some processes register with CoreAudio only on first Play. A secondary
    # diagnostic must not deadlock that Play waiting for a tap to be installed.
    # Its actual first frame bounds its own independently observed interval.
    if !capture_ready && File.file?(wave) && File.size(wave) > 4096
      File.write(File.join(output, 'capture.ready'), 'Audio frames observed')
      capture_ready = true
      result[:captureReadyObservedUnixMicros] = (Time.now.to_r * 1_000_000).to_i
    end
    if !activated && File.read(log_path).include?('S7_VARIANT_NATIVE_STARTED')
      activated = system('/usr/bin/osascript', '-e', "tell application #{bundle.inspect} to activate")
      raise 'Could not activate test app' unless activated
    end
    children = IO.popen(['/usr/bin/pgrep', '-P', pid.to_s], &:read).split.map(&:to_i)
    owned |= children
    rows = children.empty? ? '' : IO.popen(['/bin/ps', '-ww', '-p', children.join(','), '-o', 'pid=,command='], &:read)
    models = rows.lines.filter_map { |line| line.split.first.to_i if line.include?('mlx_tts_worker.py') }.sort
    result[:observedMlxSamples] += 1 unless models.empty?
    result[:maxMlxChildren] = [result[:maxMlxChildren], models.size].max
    if models != last_children
      raise 'Process observation bound' if result[:processEvents].size >= 128
      result[:processEvents] << {unixMicros: (Time.now.to_r * 1_000_000).to_i, pids: models}
      last_children = models
    end
    raise 'Overlapping model children' if models.size > 1
    sleep 0.1
  end
  native = JSON.parse(File.read(receipt))
  result[:nativePassed] = native['passed'] == true
  result[:applicationActivationRequested] = activated
  raise "Native failure: #{native['error']}" unless result[:nativePassed]
  raise 'No real model child observed' unless result[:observedMlxSamples] > 0
  raise 'No playback segments' if native.fetch('segments').empty?
rescue StandardError => e
  result[:errors] << e.message
ensure
  profiles.each do |profile|
    begin
      _, profiler_status = Timeout.timeout(12) { Process.wait2(profile) }
      (result[:nativeProfilerExitStatuses] ||= []) << profiler_status.exitstatus
      result[:errors] << 'Native profiler failed' unless profiler_status.success?
    rescue Timeout::Error
      Process.kill('TERM', profile) rescue Errno::ESRCH
      Process.waitpid(profile) rescue Errno::ECHILD
      result[:errors] << 'Native sampler did not stop'
    end
  end
  FileUtils.touch(stop) if cap || secondary_cap
  if secondary_cap
    begin
      _, captured = Timeout.timeout(12) { Process.wait2(secondary_cap) }
      result[:secondaryCapture][:exitStatus] = captured.exitstatus
    rescue Timeout::Error
      Process.kill('TERM', secondary_cap) rescue Errno::ESRCH
      Process.waitpid(secondary_cap) rescue Errno::ECHILD
      result[:secondaryCapture][:error] = 'Secondary capture did not stop'
    ensure
      secondary_log&.close
    end
  end
  if cap
    FileUtils.touch(stop)
    begin
      _, captured = Timeout.timeout(12) { Process.wait2(cap) }
      result[:captureExitStatus] = captured.exitstatus
    rescue Timeout::Error
      Process.kill('TERM', cap) rescue Errno::ESRCH
      Process.waitpid(cap) rescue Errno::ECHILD
      result[:errors] << 'Capture did not stop'
    end
    capture_log&.close
  end
  if pid
    alive = begin
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end
    if alive
      result[:normalQuit] = system('/usr/bin/osascript', '-e', "ignoring application responses\ntell application #{bundle.inspect} to quit\nend ignoring")
    else
      result[:errors] << 'Owned app exited before normal Quit'
    end
    begin
      _, status = Timeout.timeout(25) { Process.wait2(pid) }
      result[:appExitVerified] = true
    rescue Errno::ECHILD
      result[:appExitVerified] = true
    rescue Timeout::Error
      result[:forcedCleanup] = true
      Process.kill('TERM', -pid) rescue Errno::ESRCH
      Process.waitpid(pid) rescue Errno::ECHILD
    end
    result[:appExitStatus] = status&.exitstatus
    result[:errors] << 'App failed during normal Quit' if status && !status.success?
    group = IO.popen(['/usr/bin/pgrep', '-g', pid.to_s], &:read).split.map(&:to_i)
    alive_owned = owned.select do |child|
      begin
        Process.kill(0, child)
        true
      rescue Errno::ESRCH
        false
      end
    end
    result[:remainingOwnedPids] = (group | alive_owned).sort
    unless result[:remainingOwnedPids].empty?
      result[:errors] << 'Owned workers remain after normal Quit'
      result[:forcedCleanup] = true
      result[:remainingOwnedPids].each { |child| Process.kill('TERM', child) rescue Errno::ESRCH }
    end
    log&.close
  end
  if native && result[:captureExitStatus] == 0
    begin
      result[:emittedSignal] = emitted_signal(File.join(output, 'capture.wav'),
        File.join(output, 'capture.wav.timing.json'), native.fetch('segments'))
    rescue StandardError => e
      result[:errors] << "Emitted audio: #{e.message}"
    end
  end
  result[:passed] = result[:nativePassed] && result[:normalQuit] && result[:appExitVerified] &&
    !result[:forcedCleanup] && result[:remainingOwnedPids].empty? &&
    result[:captureExitStatus] == 0 && result[:emittedSignal]&.any? && result[:errors].empty?
  result[:strictAcousticAcceptance] = 'NOT_RUN: compare copied queued WAVs with capture; listening remains separate'
  pending = File.join(output, 'runner.json.pending')
  File.write(pending, JSON.pretty_generate(result) + "\n")
  File.rename(pending, File.join(output, 'runner.json'))
end
puts JSON.generate(result.slice(:passed, :nativePassed, :normalQuit, :maxMlxChildren, :errors))
exit(result[:passed] ? 0 : 1)
