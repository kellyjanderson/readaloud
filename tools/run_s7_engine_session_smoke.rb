#!/usr/bin/env ruby
# Owns one isolated signed app, app-only capture and normal Quit. No downloads.
require 'json'
require 'digest'
require 'fileutils'
require 'timeout'
require 'rbconfig'

abort 'Usage: run_s7_engine_session_smoke.rb APP SOURCE_MODEL NEW_OUTPUT CAPTURE' unless ARGV.size == 4
bundle, model, output, capture = ARGV.map { |p| File.expand_path(p) }
app = File.join(bundle, 'Contents/MacOS/read_aloud')
abort 'Missing fixture/input or existing output' unless File.executable?(app) && File.directory?(model) && File.executable?(capture) && !File.exist?(output)
abort 'Signature failure' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
identity = IO.popen(['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier', File.join(bundle, 'Contents/Info.plist')], &:read).strip
abort 'Requires isolated mlxPlaybackTest identity' unless identity == 'com.kellyjanderson.readAloud.mlxPlaybackTest'
alias_path = File.expand_path("~/Library/Containers/#{identity}/Data/Library/Application Support/#{identity}/read_aloud/mlx-tts/fish_drama3")
abort 'Preserve preexisting QA alias/model' if File.exist?(alias_path) || File.symlink?(alias_path)
model = File.realpath(model)
existing = IO.popen(['/usr/bin/pgrep', '-f', '^' + Regexp.escape(app) + '( |$)'], &:read).split
abort 'QA app already running' unless existing.empty?
FileUtils.mkdir_p(output)
receipt = File.join(output, 'receipt.json')
log_path = File.join(output, 'app.log')
stop = File.join(output, 'capture.stop')
result = {passed: false, nativePassed: false, normalQuit: false,
          appExitVerified: false, forcedCleanup: false, remainingOwnedPids: [],
          modelSource: model, expectedOwnedAlias: alias_path,
          frameworkSha256: Digest::SHA256.file(File.join(bundle, 'Contents/Frameworks/App.framework/App')).hexdigest,
          executableSha256: Digest::SHA256.file(app).hexdigest,
          maxMlxChildren: 0, observedMlxSamples: 0, processEvents: [], errors: [],
          limits: '100ms process observations; source ownership checks are separate. Offline bf16 fixture, no quantized-model/M3 claim.'}
pid = cap = nil
status = nil
last_children = nil
begin
  log = File.open(log_path, 'w')
  pid = Process.spawn({'HF_HUB_OFFLINE' => '1', 'READALOUD_S7_INSPECT' => ENV['READALOUD_S7_INSPECT'], 'READALOUD_MLX_PYTHON' => nil,
                       'READALOUD_MLX_TTS_MODEL_PATH' => nil},
                      app, model, receipt, out: log, err: log, pgroup: true)
  result[:pid] = pid
  capture_log = File.open(File.join(output, 'capture.log'), 'w')
  cap = Process.spawn(capture, pid.to_s, File.join(output, 'capture.wav'), '300', stop,
                      out: capture_log, err: capture_log)
  result[:capturePid] = cap
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 360
  activated = false
  until File.exist?(receipt)
    raise 'Native app exited before receipt' if Process.waitpid(pid, Process::WNOHANG)
    raise 'Session probe deadline' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    if !activated && File.read(log_path).include?('S7_SESSION_NATIVE_STARTED')
      activated = system('/usr/bin/osascript', '-e', "tell application #{bundle.inspect} to activate")
      raise 'Could not activate test app' unless activated
    end
    children = IO.popen(['/usr/bin/pgrep', '-P', pid.to_s], &:read).split
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
rescue StandardError => e
  result[:errors] << e.message
ensure
  if cap
    FileUtils.touch(stop)
    begin
      _, captured = Timeout.timeout(15) { Process.wait2(cap) }
      result[:captureExitStatus] = captured.exitstatus
    rescue Timeout::Error
      Process.kill('TERM', cap) rescue Errno::ESRCH
      Process.waitpid(cap) rescue Errno::ECHILD
      result[:errors] << 'Capture did not stop'
    end
    capture_log.close
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
    result[:remainingOwnedPids] = IO.popen(['/usr/bin/pgrep', '-g', pid.to_s], &:read).split.map(&:to_i)
    # Only remove the alias that was absent at preflight and still targets this
    # exact read-only fixture. Never touch an occupied/replaced model directory.
    if File.symlink?(alias_path) && File.readlink(alias_path) == model
      File.unlink(alias_path)
      result[:runnerRemovedOwnedAlias] = true
    end
    result[:ownedAliasAbsent] = !File.exist?(alias_path) && !File.symlink?(alias_path)
    result[:passed] = result[:nativePassed] && result[:normalQuit] && result[:appExitVerified] &&
      !result[:forcedCleanup] && result[:remainingOwnedPids].empty? &&
      result[:ownedAliasAbsent] && result[:captureExitStatus] == 0 && result[:errors].empty?
    log.close
  end
  File.write(File.join(output, 'runner.json'), JSON.pretty_generate(result) + "\n")
end
puts JSON.generate(result.slice(:passed, :nativePassed, :normalQuit, :maxMlxChildren, :errors))
exit(result[:passed] ? 0 : 1)
