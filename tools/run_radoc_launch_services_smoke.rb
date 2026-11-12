#!/usr/bin/env ruby
# Measure ordinary macOS application opening, including LaunchServices overhead.
# Uses the existing real-player/model-forbidden probe; never gates Play.
require 'json'
require 'digest'
require 'fileutils'
require 'rbconfig'
require 'timeout'
require 'time'

abort 'Usage: run_radoc_launch_services_smoke.rb APP_BUNDLE BOOK NEW_OUTPUT CAPTURE' unless ARGV.length == 4
bundle, book, output, capture = ARGV.map { |p| File.expand_path(p) }
app = File.join(bundle, 'Contents/MacOS/read_aloud')
abort 'Missing input or existing output' unless File.executable?(app) && File.file?(book) && File.executable?(capture) && !File.exist?(output)
abort 'Invalid signature' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
matching = -> { IO.popen(['/usr/bin/pgrep', '-f', '^' + Regexp.escape(app) + '( |$)'], &:read).split.map(&:to_i) }
abort 'Target app already running' unless matching.call.empty?
FileUtils.mkdir_p(output)
copied = File.join(output, 'copied-input.radoc')
FileUtils.cp(book, copied)
startup_book = File.join(output, 'startup-input.radoc')
FileUtils.cp(book, startup_book)
File.write(File.join(output, 'fixture.json'), JSON.pretty_generate({sourcePath: book, copiedPath: copied, startupPath: startup_book, sha256: Digest::SHA256.file(book).hexdigest, copiedSha256: Digest::SHA256.file(copied).hexdigest, executable: app, executableSha256: Digest::SHA256.file(app).hexdigest}))
receipt = File.join(output, 'receipt.json')
app_log = File.join(output, 'app.log')
File.write(app_log, '')
result = {passed: false, launchMethod: 'LaunchServices open -W -n', deadlineSeconds: 120, normalQuit: false, forcedCleanup: false, captureIntroducedPlayGate: false}
physical_head = ENV['READALOUD_QUEUE_PHYSICAL_HEAD_INDEX']
abort 'Invalid physical-head QA flag' unless physical_head.nil? || %w[0 1].include?(physical_head)
errors = []
if physical_head == '1'
  result[:physicalHeadIndexDiagnostic] = true
  errors << 'QA-only physical-head ownership candidate; production default unchanged'
end
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
pid = opener = cap = awake_pid = nil
open_status = nil
stop = File.join(output, 'capture.stop')
deadline = clock.call + 120
begin
  launched = Time.now
  result[:launchUtc] = launched.utc.iso8601(6)
  micros = (launched.to_r * 1_000_000).to_i
  result[:launchMonotonicRawNanos] = Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW, :nanosecond)
  opener = Process.spawn('/usr/bin/open', '-W', '-n', '-a', bundle, '--stdout', app_log, '--stderr', app_log, '--env', "READALOUD_SMOKE_LAUNCH_UNIX_MICROS=#{micros}", *(physical_head ? ['--env', "READALOUD_QUEUE_PHYSICAL_HEAD_INDEX=#{physical_head}"] : []), '--args', copied, receipt, startup_book, pgroup: true)
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
  awake_pid = Process.spawn('/usr/bin/caffeinate', '-d', '-w', pid.to_s)
  result[:awakeGuardPid] = awake_pid
  cap_log = File.open(File.join(output, 'capture.log'), 'w')
  cap = Process.spawn(capture, pid.to_s, File.join(output, 'capture.wav'), '110', stop, out: cap_log, err: cap_log)
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
  %w[timingClockDomain appStartupCompleteMonotonicRawNanos appStartupCompleteUnixMicros documentLoadRequestedMonotonicRawNanos documentLoadRequestedUnixMicros playRequestedMonotonicRawNanos playRequestedUnixMicros].each { |key| result[key] = native[key] if native.key?(key) }
  raise 'Missing post-startup native timing boundaries' unless native['timingClockDomain'] == 'CLOCK_MONOTONIC_RAW' && native['appStartupCompleteMonotonicRawNanos'].is_a?(Integer) && native['documentLoadRequestedMonotonicRawNanos'].is_a?(Integer) && result[:launchMonotonicRawNanos] <= native['appStartupCompleteMonotonicRawNanos'] && native['appStartupCompleteMonotonicRawNanos'] <= native['documentLoadRequestedMonotonicRawNanos']
  result.merge!(nativeReceipt: receipt, nativePassed: native['passed'], launchToNativePositionMs: native['launchToNativePositionMs'], nativePositionWithinTwoSeconds: native['nativePositionWithinTwoSeconds'])
  raise "Native playback failed: #{native['error']}" unless native['passed'] && native['forbiddenModelCallCount'] == 0 && native['peakPcm16'].to_i >= 100 && native['maxNativePositionMs'].to_i >= 500
rescue => error
  errors << error.message
ensure
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
if awake_pid
  begin
    _, awake_status = Timeout.timeout(3) { Process.wait2(awake_pid) }
    result[:awakeGuardExitStatus] = awake_status.exitstatus
    result[:awakeGuardExited] = true
    errors << 'Display wake guard failed' unless awake_status.success?
  rescue Timeout::Error
    stop_child.call(awake_pid)
    result[:awakeGuardExited] = !alive.call(awake_pid)
    errors << 'Display wake guard required forced cleanup'
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
puts "PASS: LaunchServices native playback and normal Quit; #{result[:launchToNativePositionMs]}ms native position"
