#!/usr/bin/env ruby
# First load through production intake and Fish; no capture or model-ready gate.
# Requires s6_acceptance_smoke first-load dispatch; does not build or launch CI.
require 'json'
require 'digest'
require 'fileutils'
require 'rbconfig'
require 'timeout'
require 'time'

abort 'Usage: run_radoc_first_load_smoke.rb APP_BUNDLE FISH_ENGINE INPUT_DOCUMENT NEW_OUTPUT CAPTURE' unless ARGV.length == 5
bundle, engine, book, output, capture = ARGV
bundle, book, output, capture = [bundle, book, output, capture].map { |p| File.expand_path(p) }
abort 'Expected Fish engine' unless engine.start_with?('fish_drama3')
abort 'Missing existing model' unless File.directory?(ENV.fetch('READALOUD_MLX_TTS_MODEL_PATH', ''))
explicit_python = ENV['READALOUD_MLX_PYTHON']
abort 'Invalid explicit Python override' if explicit_python && !explicit_python.empty? && !File.executable?(explicit_python)
app = File.join(bundle, 'Contents/MacOS/read_aloud')
abort 'Missing input or existing output' unless File.executable?(app) && File.file?(book) && File.executable?(capture) && !File.exist?(output)
abort 'Use a plain-text fixture for independent source counting' unless File.extname(book).downcase == '.txt'
expected_words = File.read(book, encoding: 'UTF-8').split.size
abort 'Use at least 80 words for multiple packets' unless expected_words >= 80
abort 'Invalid signature' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
matching = -> { IO.popen(['/usr/bin/pgrep', '-f', '^' + Regexp.escape(app) + '( |$)'], &:read).split.map(&:to_i) }
abort 'Target app already running' unless matching.call.empty?
FileUtils.mkdir_p(output)
copied = File.join(output, 'copied-input' + File.extname(book))
FileUtils.cp(book, copied)
File.write(File.join(output, 'fixture.json'), JSON.pretty_generate({sourcePath: book, copiedPath: copied, sha256: Digest::SHA256.file(book).hexdigest, copiedSha256: Digest::SHA256.file(copied).hexdigest, executable: app, executableSha256: Digest::SHA256.file(app).hexdigest}))
receipt = File.join(output, 'receipt.json')
app_log = File.join(output, 'app.log')
File.write(app_log, '')
result = {passed: false, launchMethod: 'LaunchServices open -W -n', deadlineSeconds: 300, normalQuit: false, forcedCleanup: false, captureIntroducedPlayGate: false}
errors = []
alive = lambda do |p|
  Process.kill(0, p)
  true
rescue Errno::ESRCH
  false
end
stop_child = lambda do |p|
  Process.kill('TERM', p) rescue Errno::ESRCH
  begin
    Timeout.timeout(2) { Process.waitpid(p) }
  rescue Timeout::Error
    Process.kill('KILL', p) rescue Errno::ESRCH
    Process.waitpid(p) rescue Errno::ECHILD
  rescue Errno::ECHILD
  end
end
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
owned = []
pid = opener = cap = nil
open_status = nil
stop = File.join(output, 'capture.stop')
deadline = clock.call + 300
begin
  launched = Time.now
  result[:launchUtc] = launched.utc.iso8601(6)
  micros = (launched.to_r * 1_000_000).to_i
  result[:launchMonotonicRawNanos] = Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW, :nanosecond)
  opener = Process.spawn('/usr/bin/open', '-W', '-n', '-a', bundle, '--stdout', app_log, '--stderr', app_log, '--env', "READALOUD_SMOKE_LAUNCH_UNIX_MICROS=#{micros}", '--env', "READALOUD_FIRST_LOAD_EXPECTED_WORDS=#{expected_words}", *%w[READALOUD_MLX_TTS_MODEL_PATH READALOUD_MLX_PYTHON READALOUD_SMOKE_QUANTIZATION_BITS READALOUD_DISABLE_SPEECH_ACTIVITY].filter_map { |key| ['--env', "#{key}=#{ENV[key]}"] if ENV[key] }.flatten, '--args', 'first-load', engine, copied, receipt, pgroup: true)
  result[:launcherPid] = opener
  discovery_end = clock.call + 15
  loop do
    found = matching.call
    raise 'Multiple target processes' if found.length > 1
    if found.length == 1
      pid = found.first
      owned << pid
      break
    end
    exited = Process.wait2(opener, Process::WNOHANG)
    if exited
      open_status = exited.last
      raise 'LaunchServices returned before target process appeared'
    end
    raise 'Target process discovery deadline' if clock.call > discovery_end
    sleep 0.01
  end
  result[:pid] = pid
  cap_log = File.open(File.join(output, 'capture.log'), 'w')
  cap = Process.spawn(capture, pid.to_s, File.join(output, 'capture.wav'), '290', stop, out: cap_log, err: cap_log)
  result[:capturePid] = cap
  puts "RADOC_LAUNCH_SERVICES_STARTED pid=#{pid} output=#{output}"
  STDOUT.flush
  next_inventory = 0
  until File.file?(receipt)
    raise 'App exited before receipt' unless alive.call(pid)
    raise 'Native smoke deadline' if clock.call > deadline - 20
    if clock.call >= next_inventory
      parents = IO.popen(['/bin/ps', '-axo', 'pid=,ppid='], &:read).lines.map { |line| line.split.map(&:to_i) }
      loop do
        added = parents.select { |child, parent| owned.include?(parent) && !owned.include?(child) }.map(&:first)
        break if added.empty?
        owned.concat(added)
        raise 'Owned process bound exceeded' if owned.length > 128
      end
      next_inventory = clock.call + 1
    end
    sleep 0.05
  end
  native = JSON.parse(File.read(receipt))
  result.merge!(nativeReceipt: receipt, nativePassed: native['passed'], launchToNativePositionMs: native['launchToNativePositionMs'], nativePositionWithinTwoSeconds: native['nativePositionWithinTwoSeconds'])
  raise "Native playback failed: #{native['error']}" unless native['passed'] && native['controlledCaptureGate'] == false && native['resourceShutdownComplete'] == true && native['observedSourceEndWord'] == native['originalSourceExpectedWordCount'] && native['peakPcm16'].to_i >= 100 && native.dig('nativePlaybackPositions', 'sampledSourcePositionTotalMs').to_i >= 500
rescue => error
  errors << error.message
ensure
  discovered = matching.call
  owned |= discovered
  pid ||= discovered.first
  if cap
    FileUtils.touch(stop)
    begin
      _, status = Timeout.timeout(10) { Process.wait2(cap) }
      result[:captureExitStatus] = status.exitstatus
      errors << 'Capture failed' unless status.success?
    rescue Timeout::Error
      stop_child.call(cap)
      errors << 'Capture required forced cleanup'
    ensure
      cap_log.close
    end
  end
  if pid
    quit = Process.spawn('/usr/bin/osascript', '-e', "ignoring application responses\ntell application #{bundle.inspect} to quit\nend ignoring")
    begin
      _, status = Timeout.timeout(10) { Process.wait2(quit) }
      result[:normalQuit] = status.success?
    rescue Timeout::Error
      stop_child.call(quit)
    end
    quit_end = [deadline - 3, clock.call + 20].min
    sleep 0.05 while owned.any? { |p| alive.call(p) } && clock.call < quit_end
    remaining = owned.select { |p| alive.call(p) }
    result[:ownedPidsAfterNormalQuit] = remaining
    unless remaining.empty?
      result[:forcedCleanup] = true
      remaining.each { |p| Process.kill('TERM', p) rescue Errno::ESRCH }
      sleep 0.1
      remaining.select { |p| alive.call(p) }.each { |p| Process.kill('KILL', p) rescue Errno::ESRCH }
    end
    result[:remainingOwnedPids] = owned.select { |p| alive.call(p) }
    result[:appExitVerified] = !alive.call(pid)
    errors << 'Normal Quit/owned exit not verified' unless result[:normalQuit] && result[:appExitVerified] && !result[:forcedCleanup] && result[:remainingOwnedPids].empty?
  end
  if opener && !open_status
    begin
      _, open_status = Timeout.timeout(5) { Process.wait2(opener) }
    rescue Timeout::Error
      stop_child.call(opener)
      errors << 'LaunchServices waiter did not exit'
    end
  end
  result[:launcherExitStatus] = open_status&.exitstatus
  result[:appExitStatus] = nil # LaunchServices owns/reaps the app, not this runner.
  errors << 'LaunchServices failed' unless open_status&.success?
  result[:errors] = errors
  result[:passed] = errors.empty?
  File.write(File.join(output, 'runner.json'), JSON.pretty_generate(result))
end
abort "FAIL: #{errors.join('; ')}" unless errors.empty?
puts "PASS: First-load functional playback and normal Quit; #{result[:launchToNativePositionMs]}ms native position"
