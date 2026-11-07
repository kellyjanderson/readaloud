#!/usr/bin/env ruby
# Run an already-built, isolated signed app; never builds or changes model data.
require 'json'
require 'digest'
require 'fileutils'
require 'rbconfig'
require 'time'

abort 'Usage: run_radoc_playback_smoke.rb APP_EXECUTABLE BOOK NEW_OUTPUT_DIRECTORY' unless ARGV.length == 3
app, book, output = ARGV.map { |path| File.expand_path(path) }
abort 'Executable missing' unless File.file?(app) && File.executable?(app)
abort 'Book missing' unless File.file?(book)
abort 'Output already exists' if File.exist?(output)
bundle = File.expand_path('../..', File.dirname(app))
abort 'Expected an app bundle executable' unless bundle.end_with?('.app')
abort 'Release signing/entitlement preflight failed' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
FileUtils.mkdir_p(output)
copied_book = File.join(output, 'copied-input.radoc')
FileUtils.cp(book, copied_book)
File.write(File.join(output, 'fixture.json'), JSON.pretty_generate({
  sourcePath: book, copiedPath: copied_book, bytes: File.size(book),
  sha256: Digest::SHA256.file(book).hexdigest,
  copiedSha256: Digest::SHA256.file(copied_book).hexdigest,
  executable: app, executableSha256: Digest::SHA256.file(app).hexdigest,
}))
receipt = File.join(output, 'receipt.json')
runner_receipt = {passed: false, deadlineSeconds: 120, normalQuit: false, forcedCleanup: false}
pid = nil
status = nil
errors = []
monotonic = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
members = -> { pid ? IO.popen(['/usr/bin/pgrep', '-g', pid.to_s], &:read).split.map(&:to_i) : [] }
File.open(File.join(output, 'app.log'), 'w') do |log|
  begin
    launched_at = Time.now
    deadline = monotonic.call + 120
    runner_receipt[:launchUtc] = launched_at.utc.iso8601(6)
    launch_micros = (launched_at.to_r * 1_000_000).to_i
    pid = Process.spawn({'READALOUD_SMOKE_LAUNCH_UNIX_MICROS' => launch_micros.to_s}, app, copied_book, receipt, out: log, err: log, pgroup: true)
    runner_receipt[:pid] = pid
    puts "RADOC_SMOKE_STARTED pid=#{pid} output=#{output}"
    loop do
      exited = Process.wait2(pid, Process::WNOHANG)
      if exited
        status = exited.last
        raise 'App exited before normal Quit was requested'
      end
      break if File.file?(receipt)
      raise 'Native smoke exceeded bounded process deadline' if monotonic.call >= deadline - 15
      sleep 0.1
    end
    result = JSON.parse(File.read(receipt))
    runner_receipt[:nativeReceipt] = receipt
    runner_receipt[:nativePassed] = result['passed']
    runner_receipt[:launchToNativePositionMs] = result['launchToNativePositionMs']
    runner_receipt[:nativePositionWithinTwoSeconds] = result['nativePositionWithinTwoSeconds']
    unless result['passed'] && result['forbiddenModelCallCount'] == 0 && result['peakPcm16'].to_i >= 100 && result['maxNativePositionMs'].to_i >= 500
      errors << "Native playback failed: #{result['error'] || result['shutdownError']}"
    end
  rescue => error
    errors << error.message
  ensure
    if pid
      # Always attempt normal Quit, including native errors and timeouts. The
      # osascript child and every wait share the original 120-second deadline.
      unless status
        quit_pid = Process.spawn('/usr/bin/osascript', '-e', "tell application #{bundle.inspect} to quit", out: log, err: log)
        quit_deadline = [deadline - 5, monotonic.call + 10].min
        quit_status = nil
        while monotonic.call < quit_deadline
          reaped = Process.wait2(quit_pid, Process::WNOHANG)
          if reaped
            quit_status = reaped.last
            break
          end
          sleep 0.05
        end
        unless quit_status
          Process.kill('KILL', quit_pid) rescue Errno::ESRCH
          Process.waitpid(quit_pid) rescue Errno::ECHILD
        end
        runner_receipt[:normalQuit] = !!quit_status&.success?
        while monotonic.call < deadline - 3
          reaped = Process.wait2(pid, Process::WNOHANG)
          if reaped
            status = reaped.last
            break
          end
          sleep 0.05
        end
      end
      remaining = members.call
      runner_receipt[:ownedPidsAfterNormalQuit] = remaining
      unless status && remaining.empty?
        runner_receipt[:forcedCleanup] = true
        Process.kill('TERM', -pid) rescue Errno::ESRCH
        until members.call.empty? || monotonic.call >= deadline - 1
          sleep 0.05
        end
        Process.kill('KILL', -pid) rescue Errno::ESRCH
        reaped = Process.wait2(pid, Process::WNOHANG) rescue nil
        status ||= reaped&.last
      end
      runner_receipt[:remainingOwnedPids] = members.call
      runner_receipt[:exitStatus] = status&.exitstatus
      runner_receipt[:appExitVerified] = !status.nil?
      runner_receipt[:elapsedSeconds] = monotonic.call - (deadline - 120)
      errors << 'Normal Quit and clean child exit were not verified' unless runner_receipt[:normalQuit] && status&.success? && !runner_receipt[:forcedCleanup] && runner_receipt[:remainingOwnedPids].empty?
    end
    runner_receipt[:errors] = errors
    runner_receipt[:passed] = errors.empty?
    File.write(File.join(output, 'runner.json'), JSON.pretty_generate(runner_receipt))
  end
end
abort "FAIL: #{errors.join('; ')}; evidence: #{output}" unless errors.empty?
puts "PASS: copied audio book native playback/reopen/transport; evidence: #{output}"
puts "Native launch-to-position: #{runner_receipt[:launchToNativePositionMs]}ms; emitted onset/listening require separate capture evidence"
