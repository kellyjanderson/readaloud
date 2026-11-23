#!/usr/bin/env ruby
# Diagnostic-only target: tools/flutter build macos --release -t tools/s11_export_diagnostic.dart
# Run only a separately signed/cloned QA bundle. Completion means diagnostics
# were captured; export success and ordinary-app acceptance are separate fields.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'timeout'

abort 'Usage: APP_BUNDLE OLD_SOURCE_OR_DASH SOURCE NEW_OUTPUT SOURCE_COMMIT' unless ARGV.length == 5
bundle, old_source, source, output, commit = ARGV
bundle, source, output = [bundle, source, output].map { |path| File.expand_path(path) }
old_source = File.expand_path(old_source) unless old_source == '-'
app = File.join(bundle, 'Contents/MacOS/read_aloud')
abort 'Missing executable/source or existing output' unless File.executable?(app) && File.file?(source) &&
  (old_source == '-' || File.file?(old_source)) && !File.exist?(output)
identifier, status = Open3.capture2('/usr/libexec/PlistBuddy', '-c', 'Print CFBundleIdentifier', File.join(bundle, 'Contents/Info.plist'))
abort 'Requires isolated QA bundle identity' unless status.success? &&
  identifier.strip.match?(/\Acom\.kellyjanderson\.readAloud\.(?:qa|exportDiagnostic)\.[A-Za-z0-9-]+\z/)
abort 'Signing/entitlement preflight failed' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
rows = lambda do
  text, ps_status = Open3.capture2('/bin/ps', '-axo', 'pid=,ppid=,comm=')
  raise 'Cannot inventory processes' unless ps_status.success?
  text.lines.filter_map do |line|
    m = line.match(/^\s*(\d+)\s+(\d+)\s+(.*)$/)
    [m[1].to_i, m[2].to_i, m[3].strip] if m
  end
end
abort 'Target app already running' if rows.call.any? { |_, _, command| command == app }
FileUtils.mkdir_p(output)
metadata = {schema: 'readaloud-s11-export-diagnostic-runner-v1', diagnostic_only: true,
            app: app, bundle_id: identifier.strip, source_commit: commit,
            source_sha256: Digest::SHA256.file(source).hexdigest,
            app_framework_sha256: Digest::SHA256.file(File.join(bundle, 'Contents/Frameworks/App.framework/App')).hexdigest,
            diagnostic_captured: false, normal_quit: false, forced_cleanup: false}
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
deadline = clock.call + 600
pid = opener = nil
owned = []
alive = lambda do |process|
  Process.kill(0, process)
  true
rescue Errno::ESRCH
  false
end
inventory = lambda do
  processes = rows.call
  owned |= processes.select { |_, _, command| command == app }.map(&:first)
  loop do
    found = processes.select { |child, parent, _| owned.include?(parent) && !owned.include?(child) }.map(&:first)
    break if found.empty?
    raise 'Owned process bound exceeded' if owned.length + found.length > 128
    owned.concat(found)
  end
end
begin
  log = File.join(output, 'native.log')
  File.write(log, '')
  opener = Process.spawn('/usr/bin/open', '-W', '-n', '-a', bundle,
                         '--stdout', log, '--stderr', log,
                         '--env', 'HF_HUB_OFFLINE=1',
                         '--env', 'READALOUD_TTS_ENGINE=fish_drama3_8bit',
                         '--args', File.join(output, 'probe'), old_source, source, commit)
  discovery = clock.call + 15
  loop do
    matches = rows.call.select { |_, _, command| command == app }.map(&:first)
    raise 'Multiple target apps' if matches.length > 1
    if matches.length == 1
      pid = matches.first
      owned << pid
      break
    end
    raise 'App discovery deadline' if clock.call >= discovery
    sleep 0.02
  end
  metadata[:pid] = pid
  puts "S11_EXPORT_STARTED pid=#{pid} log=#{log}"
  $stdout.flush
  receipt = File.join(output, 'probe/receipt.json')
  loop do
    inventory.call
    break if File.file?(receipt)
    raise 'Diagnostic app exited without receipt' unless alive.call(pid)
    raise 'Diagnostic deadline' if clock.call >= deadline
    sleep 0.1
  end
  metadata[:receipt] = JSON.parse(File.read(receipt))
  metadata[:diagnostic_captured] = metadata[:receipt]['diagnosticCompleted'] == true &&
    metadata[:receipt]['preparationOwnerDrained'] == true
rescue StandardError => error
  metadata[:error] = error.full_message
ensure
  inventory.call if opener
  # The root native owner issues Cmd-Q with CUA, then writes this exact-PID
  # acknowledgment. Process exit alone is never called a normal Quit request.
  acknowledgment = File.join(output, 'normal-quit-request.json')
  if pid && alive.call(pid)
    File.write(File.join(output, 'quit-ready.json'), JSON.pretty_generate({pid: pid, acknowledgment: acknowledgment}))
    puts "READY_FOR_NORMAL_QUIT pid=#{pid} acknowledgment=#{acknowledgment}"
    $stdout.flush
    quit_deadline = clock.call + 60
    loop do
      if File.file?(acknowledgment)
        request = JSON.parse(File.read(acknowledgment))
        metadata[:normal_quit] = request['pid'] == pid && request['method'] == 'CUA Cmd-Q'
        metadata[:normal_quit_request] = request
        break
      end
      break if clock.call >= quit_deadline
      sleep 0.05
    end
  end
  cleanup_deadline = clock.call + 20
  sleep 0.05 while owned.any? { |process| alive.call(process) } && clock.call < cleanup_deadline
  metadata[:owned_pids_after_normal_quit] = owned.select { |process| alive.call(process) }
  unless metadata[:owned_pids_after_normal_quit].empty?
    metadata[:forced_cleanup] = true
    metadata[:owned_pids_after_normal_quit].each { |process| Process.kill('TERM', process) rescue Errno::ESRCH }
    sleep 0.2
    owned.select { |process| alive.call(process) }.each { |process| Process.kill('KILL', process) rescue Errno::ESRCH }
  end
  if opener
    begin
      Timeout.timeout(5) { Process.waitpid(opener) }
      metadata[:launcher_exit] = $?.exitstatus
    rescue StandardError => error
      metadata[:launcher_error] = error.message
      Process.kill('TERM', opener) rescue Errno::ESRCH
    end
  end
  metadata[:remaining_owned_pids] = owned.select { |process| alive.call(process) }
  metadata[:app_exit_verified] = pid && !alive.call(pid)
  metadata[:cleanup_passed] = metadata[:normal_quit] && metadata[:app_exit_verified] &&
    !metadata[:forced_cleanup] && metadata[:remaining_owned_pids].empty? && metadata[:launcher_exit] == 0
  File.write(File.join(output, 'run.json'), JSON.pretty_generate(metadata))
end
puts JSON.generate(metadata.slice(:diagnostic_captured, :cleanup_passed, :error))
exit(metadata[:diagnostic_captured] && metadata[:cleanup_passed] ? 0 : 1)
