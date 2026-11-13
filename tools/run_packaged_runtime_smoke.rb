#!/usr/bin/env ruby
# Bounded signed native lifetime runner; normal Quit is required on every path.
require 'json'
require 'fileutils'
require 'timeout'
require 'rbconfig'
abort 'Usage: run_packaged_runtime_smoke.rb APP_BUNDLE NEW_OUTPUT_DIRECTORY booknlp|runtime-cancel [RUNTIME_ID]' unless [3, 4].include?(ARGV.size)
bundle, output = ARGV.take(2).map { |p| File.expand_path(p) }
mode, runtime = ARGV.drop(2)
abort 'Unknown native scenario' unless (mode == 'booknlp' && runtime.nil?) || (mode == 'runtime-cancel' && %w[mlx modernbooknlp].include?(runtime))
abort 'Output exists' if File.exist?(output)
abort 'Signing preflight failed' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
FileUtils.mkdir_p(output)
receipt = File.join(output, 'receipt.json')
args = [mode, runtime, receipt].compact
cleanup = {normalQuit: false, forcedCleanup: false}
pid = nil
status = nil
error = nil
begin
  File.open(File.join(output, 'app.log'), 'w') do |log|
    pid = Process.spawn(File.join(bundle, 'Contents/MacOS/read_aloud'), *args, out: log, err: log, pgroup: true)
    File.write(File.join(output, 'pid'), pid.to_s)
    Timeout.timeout(600) do
      until File.file?(receipt)
        exited = Process.wait2(pid, Process::WNOHANG)
        if exited
          status = exited.last
          raise 'App exited before native receipt'
        end
        sleep 0.2
      end
    end
    result = JSON.parse(File.read(receipt))
    raise "Native scenario failed: #{result['error']}" unless result['passed']
  end
rescue StandardError => failure
  error = failure.message
ensure
  if pid
    quit = Process.spawn('/usr/bin/osascript', '-e', "ignoring application responses\ntell application #{bundle.inspect} to quit\nend ignoring", out: File::NULL, err: File::NULL)
    begin
      _, quit_status = Timeout.timeout(10) { Process.wait2(quit) }
      cleanup[:normalQuit] = quit_status.success?
    rescue Timeout::Error
      Process.kill('KILL', quit) rescue Errno::ESRCH
      Process.waitpid(quit) rescue Errno::ECHILD
    end
    begin
      _, status = Timeout.timeout(25) { Process.wait2(pid) } unless status
    rescue Timeout::Error
      cleanup[:forcedCleanup] = true
    rescue Errno::ECHILD
    end
    remaining = IO.popen(['pgrep', '-g', pid.to_s], &:read).split.map(&:to_i)
    cleanup[:ownedPidsAfterNormalQuit] = remaining
    unless status && remaining.empty?
      cleanup[:forcedCleanup] = true
      Process.kill('KILL', -pid) rescue Errno::ESRCH
      Process.waitpid(pid) rescue Errno::ECHILD
    end
    cleanup[:remainingOwnedPids] = IO.popen(['pgrep', '-g', pid.to_s], &:read).split.map(&:to_i)
    cleanup[:exitStatus] = status&.exitstatus
    error ||= 'Normal Quit/child cleanup failed' unless cleanup[:normalQuit] && !cleanup[:forcedCleanup] && cleanup[:remainingOwnedPids].empty? && status&.success?
  end
  cleanup[:error] = error
  cleanup[:passed] = error.nil?
  File.write(File.join(output, 'cleanup.json'), JSON.pretty_generate(cleanup))
end
abort error if error
puts "PASS: #{args.first} native scenario; normal Quit verified"
