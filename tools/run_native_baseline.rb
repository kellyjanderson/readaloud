#!/usr/bin/env ruby
# Bounded native export probe. This measures emitted WAV and process retention;
# it does not establish audible playback, native drain, or UI responsiveness.
require 'fileutils'
require 'digest'
require 'json'
require 'timeout'
require 'open3'

abort 'Usage: ruby tools/run_native_baseline.rb APP_EXECUTABLE NEW_OUTPUT_DIR' unless ARGV.length == 2
app = File.expand_path(ARGV[0])
output = File.expand_path(ARGV[1])
abort 'Output directory must not already exist' if File.exist?(output)
abort 'App executable missing' unless File.executable?(app)
plist = File.expand_path('../Info.plist', File.dirname(app))
bundle_id, status = Open3.capture2('/usr/libexec/PlistBuddy', '-c',
                                 'Print CFBundleIdentifier', plist)
abort 'Build with PRODUCT_BUNDLE_IDENTIFIER=com.kellyjanderson.readAloud.p0 first' unless
  status.success? && bundle_id.strip == 'com.kellyjanderson.readAloud.p0'
FileUtils.mkdir_p(output)
root = File.expand_path('..', __dir__)
fixture = File.join(root, 'test/fixtures/prepared_runtime_aba.txt')
probe_fixture = File.join(output, 'prepared_runtime_aba.txt')
FileUtils.cp(fixture, probe_fixture)
log_path = File.join(output, 'native.log')
metadata = {
  bundle_id: bundle_id.strip,
  fixture_sha256: Digest::SHA256.file(fixture).hexdigest,
  app: app,
  limitation: 'Export only; process termination is not native cleanup evidence',
  assets: Dir[File.join(root, 'assets/kokoro/model/*.onnx'),
              File.join(root, 'assets/kokoro/voices/*.npy')].to_h { |path|
    [path.delete_prefix(root + '/'), Digest::SHA256.file(path).hexdigest]
  }
}
pid = nil
begin
  File.open(log_path, 'w') do |log|
    pid = Process.spawn({'READALOUD_ORT_RESOURCE_TRACE' => '1'}, app,
                        '--headless', '--voice', 'af_bella', '--output',
                        File.join(output, 'aba.wav'), probe_fixture,
                        out: log, err: log, chdir: root)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    File.open(File.join(output, 'memory.csv'), 'w') do |memory|
      memory.puts 'elapsed_seconds,rss_kib'
      loop do
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        rss = IO.popen(['ps', '-o', 'rss=', '-p', pid.to_s], &:read).strip
        memory.puts "#{elapsed.round(3)},#{rss}"
        memory.flush
        if Process.waitpid(pid, Process::WNOHANG)
          metadata[:process_exit] = $?.exitstatus
          pid = nil
          break
        end
        if File.read(log_path).include?('Summary:')
          metadata[:summary_observed] = true
          break
        end
        if elapsed > 120
          metadata[:timeout] = true
          break
        end
        sleep 1
      end
    end
  end
ensure
  if pid
    Process.kill('TERM', pid) rescue Errno::ESRCH
    begin
      Timeout.timeout(5) { Process.waitpid(pid) }
    rescue Timeout::Error
      Process.kill('KILL', pid) rescue Errno::ESRCH
      Process.waitpid(pid) rescue Errno::ECHILD
      metadata[:forced_kill] = true
    rescue Errno::ECHILD
      # Already reaped.
    end
    metadata[:harness_terminated] = true
  end
  File.write(File.join(output, 'run.json'), JSON.pretty_generate(metadata))
end
trace = File.read(log_path)
counts = trace.scan(/READALOUD_ORT method=(\w+) sessions=(\d+) tensors=(\d+) error=(\w+)/)
metadata[:native_snapshots] = counts.map { |method, sessions, tensors, error|
  {method: method, sessions: sessions.to_i, tensors: tensors.to_i, error: error}
}
sidecar = File.join(output, 'aba.json')
if File.exist?(sidecar)
  metadata[:routes] = JSON.parse(File.read(sidecar)).fetch('chunks').map { |chunk|
    chunk.slice('chunkId', 'voiceId', 'castId', 'durationMillis')
  }
end
File.write(File.join(output, 'run.json'), JSON.pretty_generate(metadata))
puts JSON.pretty_generate(metadata)
failed = metadata[:timeout] || metadata[:forced_kill] ||
         (metadata[:process_exit] && metadata[:process_exit] != 0) ||
         !File.exist?(File.join(output, 'aba.wav')) ||
         !File.read(log_path).include?('Summary: 1 succeeded, 0 failed.')
exit(failed ? 1 : 0)
