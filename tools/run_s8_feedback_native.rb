#!/usr/bin/env ruby
# UI-only lifecycle runner. Does not launch recorders, simulate input or claim
# UI acceptance. Gate paths are printed by the app to native.log for the CUA
# coordinator. Normal Quit and an empty owned process inventory are mandatory.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'time'

abort 'Usage: run_s8_feedback_native.rb APP_EXECUTABLE NEW_OUTPUT_DIR' unless ARGV.length == 2
app, output = ARGV.map { |path| File.expand_path(path) }
bundle = File.expand_path('../..', File.dirname(app))
abort 'Missing executable' unless File.executable?(app)
abort 'Output already exists' if File.exist?(output)
identifier, status = Open3.capture2('/usr/libexec/PlistBuddy', '-c', 'Print CFBundleIdentifier', File.join(bundle, 'Contents/Info.plist'))
isolated_ids = %w[com.kellyjanderson.readAloud.mlxPlaybackTest com.kellyjanderson.readAloud.feedbackTest]
abort 'Requires an isolated feedbackTest or mlxPlaybackTest bundle' unless status.success? && isolated_ids.include?(identifier.strip)
abort 'Signing/entitlement preflight failed' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
matching = lambda do
  processes, ps_status = Open3.capture2('/bin/ps', '-axo', 'pid=,comm=')
  raise 'Cannot discover exact target executable' unless ps_status.success?
  processes.lines.filter_map do |line|
    match = line.match(/^\s*(\d+)\s+(.*)$/)
    match[1].to_i if match && match[2].strip == app
  end
end
abort 'Target executable already has a running PID' unless matching.call.empty?
seconds = Integer(ENV.fetch('READALOUD_S8_WORK_SECONDS', '480'))
abort 'Work deadline must be 30..600 seconds' unless (30..600).cover?(seconds)
forced_frames = ENV.fetch('READALOUD_S8_FORCE_HEARTBEAT_FRAMES', '0')
abort 'Frame control must be 0 or 1' unless %w[0 1].include?(forced_frames)
FileUtils.mkdir_p(output)
metadata = {app: app, bundle: bundle, bundle_id: identifier.strip,
            executable_sha256: Digest::SHA256.file(app).hexdigest,
            launch_method: 'LaunchServices open -W -n',
            app_exit_status: nil, app_exit_status_owner: 'LaunchServices; unavailable to runner',
            work_deadline_seconds: seconds, cleanup_deadline_seconds: 30,
            force_heartbeat_frames: forced_frames == '1',
            scope: 'UI-only; coordinator owns native input, screenshots and accessibility observations',
            passed: false, normal_quit: false,
            normal_quit_evidence: 'One-way request succeeded; actual PID exit verified separately',
            forced_cleanup: false}
framework = File.join(bundle, 'Contents/Frameworks/App.framework/App')
if File.file?(framework)
  metadata[:app_framework] = File.realpath(framework)
  metadata[:app_framework_sha256] = Digest::SHA256.file(framework).hexdigest
end
pid = opener = awake_pid = nil
open_status = nil
owned = []
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
started = clock.call
work_deadline = started + seconds
global_deadline = work_deadline + 30
alive = lambda do |process|
  Process.kill(0, process)
  true
rescue Errno::ESRCH
  false
end
# As in run_radoc_launch_services_smoke.rb, LaunchServices owns the app;
# only open, caffeinate and osascript are children reaped by this runner.
wait_child = lambda do |child, deadline|
  loop do
    exited = Process.wait2(child, Process::WNOHANG)
    break exited.last if exited
    break nil if clock.call >= deadline
    sleep [0.05, deadline - clock.call].min if clock.call < deadline
  end
end
stop_child = lambda do |child, deadline|
  Process.kill('TERM', child) rescue Errno::ESRCH
  status = wait_child.call(child, [clock.call + 0.5, deadline].min)
  unless status
    Process.kill('KILL', child) rescue Errno::ESRCH
    status = wait_child.call(child, deadline)
  end
  status
end
inventory = lambda do
  parents, ps_status = Open3.capture2('/bin/ps', '-axo', 'pid=,ppid=')
  raise 'Cannot inventory owned processes' unless ps_status.success?
  parents = parents.lines.map { |line| line.split.map(&:to_i) }
  loop do
    added = parents.select { |child, parent| owned.include?(parent) && !owned.include?(child) }.map(&:first)
    break if added.empty?
    raise 'Owned process bound exceeded' if owned.length + added.length > 128
    owned.concat(added)
  end
end
begin
  log = File.join(output, 'native.log')
  File.write(log, '')
  metadata[:launch_utc] = Time.now.utc.iso8601(6)
  opener = Process.spawn('/usr/bin/open', '-W', '-n', '-a', bundle,
                         '--stdout', log, '--stderr', log,
                         '--env', 'READALOUD_S8_NORMAL_QUIT=1',
                         '--env', "READALOUD_S8_WORK_SECONDS=#{seconds}",
                         '--env', "READALOUD_S8_FORCE_HEARTBEAT_FRAMES=#{forced_frames}",
                         '--args', File.join(output, 'probe'), pgroup: true)
  metadata[:launcher_pid] = opener
  discovery_deadline = [clock.call + 15, work_deadline].min
  loop do
    found = matching.call
    owned |= found
    raise 'Multiple target processes' if found.length > 1
    if found.length == 1
      pid = found.first
      break
    end
    exited = Process.wait2(opener, Process::WNOHANG)
    if exited
      open_status = exited.last
      raise 'LaunchServices returned before target process appeared'
    end
    raise 'Target process discovery deadline' if clock.call >= discovery_deadline
    sleep 0.01
  end
  metadata[:pid] = pid
  # Session-local display wake assertion tied to the exact app PID.
  awake_pid = Process.spawn('/usr/bin/caffeinate', '-d', '-w', pid.to_s)
  metadata[:awake_guard_pid] = awake_pid
  File.write(File.join(output, 'launch.json'), JSON.pretty_generate(metadata))
  puts "S8_STARTED pid=#{pid} log=#{log} gates=#{output}/probe"
  $stdout.flush
  receipt_path = File.join(output, 'probe/receipt.json')
  next_inventory = 0
  loop do
    raise 'Probe exited before normal Quit / cleanup receipt' unless alive.call(pid)
    raise 'S8 work deadline' if clock.call >= work_deadline
    if clock.call >= next_inventory
      inventory.call
      next_inventory = clock.call + 1
    end
    break if File.file?(receipt_path)
    sleep 0.05
  end
  metadata[:receipt] = JSON.parse(File.read(receipt_path))
  raise 'Probe receipt failed' unless metadata[:receipt]['passed'] && metadata[:receipt]['ownersDrained']
  raise 'QA-only forced-frame stress diagnostic; not production frame scheduling' if forced_frames == '1'
  metadata[:passed] = true
rescue StandardError => error
  metadata[:error] = error.full_message
  warn "S8_FAILED #{error.message}"
ensure
  cleanup_deadline = [clock.call + 30, global_deadline].min
  # Include a target that appeared at the discovery boundary. Never address a
  # stopped bundle with AppleScript: that could relaunch it just to send Quit.
  target_running = false
  begin
    owned |= matching.call if opener && !pid
    inventory.call unless owned.empty?
    target_running = pid && alive.call(pid) && matching.call.include?(pid)
  rescue StandardError => error
    metadata[:cleanup_inventory_error] = error.message
    metadata[:passed] = false
  end
  if target_running
    quit_pid = Process.spawn('/usr/bin/osascript', '-e', "ignoring application responses\ntell application #{bundle.inspect} to quit\nend ignoring")
    quit_status = wait_child.call(quit_pid, [clock.call + 5, cleanup_deadline - 4].min)
    metadata[:normal_quit] = quit_status&.success? || false
    unless quit_status
      metadata[:quit_request_forced_cleanup] = true
      metadata[:forced_cleanup] = true
      stop_child.call(quit_pid, [clock.call + 1, cleanup_deadline].min)
    end
  end
  quit_deadline = [clock.call + 20, cleanup_deadline - 4].min
  sleep 0.05 while owned.any? { |process| alive.call(process) } && clock.call < quit_deadline
  remaining = owned.select { |process| alive.call(process) }
  metadata[:owned_pids_after_normal_quit] = remaining
  unless remaining.empty?
    metadata[:forced_cleanup] = true
    remaining.each { |process| Process.kill('TERM', process) rescue Errno::ESRCH }
    sleep 0.1 if clock.call + 0.1 < cleanup_deadline
    remaining.select { |process| alive.call(process) }.each { |process| Process.kill('KILL', process) rescue Errno::ESRCH }
  end
  if opener && !open_status
    open_status = wait_child.call(opener, [clock.call + 2, cleanup_deadline - 2].min)
    unless open_status
      metadata[:forced_cleanup] = true
      metadata[:launcher_forced_cleanup] = true
      open_status = stop_child.call(opener, [clock.call + 1, cleanup_deadline - 1].min)
    end
  end
  metadata[:launcher_exit_status] = open_status&.exitstatus
  if awake_pid
    awake_status = wait_child.call(awake_pid, [clock.call + 2, cleanup_deadline - 1].min)
    unless awake_status
      metadata[:forced_cleanup] = true
      metadata[:awake_guard_forced_cleanup] = true
      awake_status = stop_child.call(awake_pid, cleanup_deadline)
    end
    metadata[:awake_guard_exited] = !awake_status.nil?
    metadata[:awake_guard_exit_status] = awake_status&.exitstatus
  end
  metadata[:owned_pids] = owned
  metadata[:remaining_owned_pids] = owned.select { |process| alive.call(process) }
  metadata[:owned_pid_exited] = pid ? !alive.call(pid) : false
  metadata[:elapsed_seconds] = clock.call - started
  cleanup_errors = []
  cleanup_errors << 'Normal Quit request failed or app was already absent' unless metadata[:normal_quit]
  cleanup_errors << 'Actual app PID exit not verified' unless metadata[:owned_pid_exited]
  cleanup_errors << 'LaunchServices waiter failed or was not reaped' unless open_status&.success?
  cleanup_errors << 'Wake guard exit not verified' unless metadata[:awake_guard_exited]
  cleanup_errors << 'Forced cleanup required' if metadata[:forced_cleanup]
  cleanup_errors << 'Owned processes remain' unless metadata[:remaining_owned_pids].empty?
  metadata[:cleanup_errors] = cleanup_errors
  metadata[:passed] &&= cleanup_errors.empty?
  File.write(File.join(output, 'run.json'), JSON.pretty_generate(metadata))
end
puts "S8_RESULT passed=#{metadata[:passed]} receipt=#{output}/probe/receipt.json cleanup=#{output}/run.json"
exit(metadata[:passed] ? 0 : 1)
