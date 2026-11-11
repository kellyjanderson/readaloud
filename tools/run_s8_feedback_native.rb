#!/usr/bin/env ruby
# UI-only lifecycle runner. Does not launch recorders, simulate input or claim
# UI acceptance. Gate paths are printed by the app to native.log for the CUA
# coordinator. Normal Quit and an empty owned process group are mandatory.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'timeout'

abort 'Usage: run_s8_feedback_native.rb APP_EXECUTABLE NEW_OUTPUT_DIR' unless ARGV.length == 2
app, output = ARGV.map { |path| File.expand_path(path) }
bundle = File.expand_path('../..', File.dirname(app))
abort 'Missing executable' unless File.executable?(app)
abort 'Output already exists' if File.exist?(output)
identifier, status = Open3.capture2('/usr/libexec/PlistBuddy', '-c', 'Print CFBundleIdentifier', File.join(bundle, 'Contents/Info.plist'))
abort 'Requires isolated mlxPlaybackTest bundle' unless status.success? && identifier.strip == 'com.kellyjanderson.readAloud.mlxPlaybackTest'
abort 'Signing/entitlement preflight failed' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
processes, = Open3.capture2('ps', '-axo', 'pid=,comm=')
existing = processes.lines.filter_map do |line|
  match = line.match(/^\s*(\d+)\s+(.*)$/)
  match[1].to_i if match && match[2].strip == app
end
abort 'Target executable already has a running PID' unless existing.empty?
seconds = Integer(ENV.fetch('READALOUD_S8_WORK_SECONDS', '480'))
abort 'Work deadline must be 30..600 seconds' unless (30..600).cover?(seconds)
FileUtils.mkdir_p(output)
metadata = {app: app, bundle: bundle, bundle_id: identifier.strip,
            executable_sha256: Digest::SHA256.file(app).hexdigest,
            work_deadline_seconds: seconds, cleanup_deadline_seconds: 30,
            scope: 'UI-only; coordinator owns native input, screenshots and accessibility observations',
            passed: false, normal_quit: false, forced_cleanup: false}
pid = nil
awake_pid = nil
reaped = false
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
remaining = -> { [seconds + 30 - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started), 0.1].max }
group_members = -> { pid ? IO.popen(['pgrep', '-g', pid.to_s], &:read).split.map(&:to_i) : [] }
quit = lambda do
  quit_pid = Process.spawn('/usr/bin/osascript', '-e', "with timeout of 5 seconds\ntell application #{bundle.inspect} to quit\nend timeout")
  begin
    _, exited = Timeout.timeout([6, remaining.call].min) { Process.wait2(quit_pid) }
    exited.success?
  rescue Timeout::Error
    Process.kill('KILL', quit_pid) rescue Errno::ESRCH
    Process.waitpid(quit_pid) rescue Errno::ECHILD
    false
  end
end
begin
  File.open(File.join(output, 'native.log'), 'w') do |log|
    pid = Process.spawn({'READALOUD_S8_NORMAL_QUIT' => '1', 'READALOUD_S8_WORK_SECONDS' => seconds.to_s},
                        app, File.join(output, 'probe'), out: log, err: log, pgroup: true)
    metadata[:pid] = pid
    # Session-local display wake assertion, automatically tied to this exact
    # owned app PID. No lock, security or global preference setting is changed.
    awake_pid = Process.spawn('/usr/bin/caffeinate', '-d', '-w', pid.to_s)
    metadata[:awake_guard_pid] = awake_pid
    File.write(File.join(output, 'launch.json'), JSON.pretty_generate(metadata))
    puts "S8_STARTED pid=#{pid} log=#{output}/native.log gates=#{output}/probe"
    $stdout.flush
    receipt_path = File.join(output, 'probe/receipt.json')
    Timeout.timeout(remaining.call) do
      loop do
        exited = Process.wait2(pid, Process::WNOHANG)
        if exited
          reaped = true
          metadata[:exit_status] = exited.last.exitstatus
          raise 'Probe exited before normal Quit / cleanup receipt'
        end
        break if File.file?(receipt_path)
        sleep 0.1
      end
    end
    metadata[:receipt] = JSON.parse(File.read(receipt_path))
    metadata[:normal_quit] = quit.call
    raise 'Normal Quit failed' unless metadata[:normal_quit]
    _, exited = Timeout.timeout([20, remaining.call].min) { Process.wait2(pid) }
    reaped = true
    metadata[:exit_status] = exited.exitstatus
    raise 'Application exit was unsuccessful' unless exited.success?
    raise 'Probe receipt failed' unless metadata[:receipt]['passed'] && metadata[:receipt]['ownersDrained']
    raise 'Owned child processes survived normal Quit' unless group_members.call.empty?
    metadata[:passed] = true
  end
rescue StandardError => error
  metadata[:error] = error.full_message
  warn "S8_FAILED #{error.message}"
ensure
  # Failure/timeout still requests normal Quit before any forced cleanup. A
  # force signal is explicitly failed evidence; never label it a clean session.
  if pid && !reaped
    begin
      metadata[:normal_quit] = quit.call
      _, exited = Timeout.timeout([20, remaining.call].min) { Process.wait2(pid) }
      metadata[:exit_status] = exited.exitstatus
      reaped = true
    rescue Errno::ECHILD
      reaped = true
    rescue Timeout::Error
      metadata[:forced_cleanup] = true
    end
  end
  unless group_members.call.empty?
    metadata[:forced_cleanup] = true
    Process.kill('TERM', -pid) rescue Errno::ESRCH
    begin
      Timeout.timeout(5) { Process.waitpid(pid) } unless reaped
    rescue Errno::ECHILD
    rescue Timeout::Error
      Process.kill('KILL', -pid) rescue Errno::ESRCH
      Process.waitpid(pid) rescue Errno::ECHILD
    end
    Process.kill('KILL', -pid) rescue Errno::ESRCH unless group_members.call.empty?
  end
  metadata[:remaining_owned_pids] = group_members.call
  metadata[:owned_pid_exited] = !metadata[:remaining_owned_pids].include?(pid)
  if awake_pid
    begin
      _, awake_status = Timeout.timeout(2) { Process.wait2(awake_pid) }
      metadata[:awake_guard_exited] = true
      metadata[:awake_guard_exit_status] = awake_status.exitstatus
    rescue Timeout::Error
      metadata[:awake_guard_exited] = false
      metadata[:forced_cleanup] = true
      Process.kill('KILL', awake_pid) rescue Errno::ESRCH
      Process.waitpid(awake_pid) rescue Errno::ECHILD
    end
  end
  metadata[:passed] &&= metadata[:normal_quit] && !metadata[:forced_cleanup] && metadata[:remaining_owned_pids].empty?
  File.write(File.join(output, 'run.json'), JSON.pretty_generate(metadata))
end
puts "S8_RESULT passed=#{metadata[:passed]} receipt=#{output}/probe/receipt.json cleanup=#{output}/run.json"
exit(metadata[:passed] ? 0 : 1)
