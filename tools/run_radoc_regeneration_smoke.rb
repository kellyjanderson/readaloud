#!/usr/bin/env ruby
# Native app + real inference; captures each phase before releasing its Play gate.
require 'json'
require 'fileutils'
require 'timeout'
require 'rbconfig'
abort 'Usage: RUN APP_BUNDLE NEW_OUTPUT_DIRECTORY CAPTURE_EXECUTABLE' unless ARGV.size == 3
bundle, output, capture = ARGV.map { |p| File.expand_path(p) }
abort 'Output already exists' if File.exist?(output)
abort 'Signing preflight failed' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
FileUtils.mkdir_p(output)
app = File.join(bundle, 'Contents/MacOS/read_aloud')
receipt = File.join(output, 'receipt.json')
gate = File.join(output, 'capture-ready')
captures = {}
normal = false
forced = false
activated = false
pid = nil
status = nil
begin
  log = File.open(File.join(output, 'app.log'), 'w')
  pid = Process.spawn({'READALOUD_RADOC_CAPTURE_GATE_PREFIX' => gate}, app, 'fish_drama3', receipt, out: log, err: log, pgroup: true)
  File.write(File.join(output, 'pid'), pid.to_s)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1200
  until File.exist?(receipt)
    raise 'Test app exited before receipt' if Process.waitpid(pid, Process::WNOHANG)
    raise 'Native regeneration deadline' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    contents = File.read(File.join(output, 'app.log'))
    %w[initial changed reused missing].each do |phase|
      if contents.include?("RADOC_REGEN_CAPTURE_WAITING phase=#{phase} ") && !captures.key?(phase)
        if phase == 'initial'
          # A directly spawned macOS bundle need not become the active app.
          # Exercise the foreground reading interaction explicitly; per-sample
          # native receipts retain active/inactive state without waiving250ms.
          activated = system('/usr/bin/osascript', '-e', "tell application #{bundle.inspect} to activate")
          raise 'Could not activate native test application' unless activated
        end
        capture_log = File.open(File.join(output, "#{phase}-capture.log"), 'w')
        stop = File.join(output, "#{phase}.stop")
        cap_pid = Process.spawn(capture, pid.to_s, File.join(output, "#{phase}.wav"), '300', stop, out: capture_log, err: capture_log)
        captures[phase] = {pid: cap_pid, stop: stop, log: capture_log}
        Timeout.timeout(20) do
          until File.read(File.join(output, "#{phase}-capture.log")).include?('Capturing app PID')
            raise 'Capture exited before ready' if Process.waitpid(cap_pid, Process::WNOHANG)
            sleep 0.1
          end
        end
        File.write("#{gate}.#{phase}", 'ready')
        puts "Capturing #{phase}; Play gate released"
        STDOUT.flush
      end
      if captures[phase] && contents.include?("RADOC_REGEN_SOURCE_END phase=#{phase} ")
        FileUtils.touch(captures[phase][:stop])
      end
    end
    sleep 0.2
  end
  result = JSON.parse(File.read(receipt))
  puts "Native receipt: passed=#{result['passed']} error=#{result['error']}"
ensure
  captures.each_value do |entry|
    FileUtils.touch(entry[:stop])
    begin
      _, s = Timeout.timeout(15) { Process.wait2(entry[:pid]) }
      entry[:exitStatus] = s.exitstatus
    rescue Errno::ECHILD
      entry[:exitStatus] ||= -1
    rescue Timeout::Error
      Process.kill('TERM', entry[:pid]) rescue Errno::ESRCH
      Process.waitpid(entry[:pid]) rescue Errno::ECHILD
      entry[:exitStatus] = -1
    end
    entry[:log].close
  end
  if pid
    normal = system('/usr/bin/osascript', '-e', "ignoring application responses\ntell application #{bundle.inspect} to quit\nend ignoring")
    begin
      _, status = Timeout.timeout(25) { Process.wait2(pid) }
    rescue Errno::ECHILD
    rescue Timeout::Error
      forced = true
      Process.kill('TERM', -pid) rescue Errno::ESRCH
      Process.waitpid(pid) rescue Errno::ECHILD
    end
    remaining = IO.popen(['pgrep', '-g', pid.to_s], &:read).split.map(&:to_i)
    File.write(File.join(output, 'cleanup.json'), JSON.pretty_generate({normalQuit: normal, applicationActivationRequested: activated, forcedCleanup: forced, exitStatus: status&.exitstatus, remainingOwnedPids: remaining, captures: captures.transform_values { |v| v.reject { |k,_| k == :log } }}))
    abort 'Normal app/child cleanup failed' unless normal && !forced && remaining.empty?
  end
end
abort 'Native test failed' unless result && result['passed'] && captures.values.all? { |v| v[:exitStatus] == 0 }
