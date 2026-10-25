#!/usr/bin/env ruby
# Bounded native export probe. This measures emitted WAV and process retention;
# it does not establish audible playback, native drain, or UI responsiveness.
require 'fileutils'
require 'digest'
require 'json'
require 'timeout'
require 'open3'
require 'etc'

# Keep the three locations separate: prepareKokoroAssets and the voice manager
# reuse nonempty/installed Application Support files, even after a new build.
module NativeBaselineAssets
  def self.snapshot(root, model_directory: 'model')
    paths = Dir[File.join(root, model_directory, '*.onnx'),
                File.join(root, 'voices', '*.npy')]
    paths.to_h do |path|
      key = path.delete_prefix(root + '/').sub(/^#{model_directory}\//, 'model/')
      record = {path: path}
      begin
        record.merge!(resolved_path: File.realpath(path),
                      sha256: Digest::SHA256.file(path).hexdigest,
                      bytes: File.size(path), status: 'present')
      rescue SystemCallError => error
        record.merge!(status: 'unreadable', error: error.message)
      end
      [key, record]
    end
  end

  def self.comparisons(snapshots, required)
    keys = (snapshots.values.flat_map(&:keys) + required).uniq.sort
    keys.to_h do |key|
      records = snapshots.transform_values { |files| files[key] }
      digests = records.transform_values { |file| file && file[:sha256] }
      runtime_before = digests[:runtime_before]
      runtime_after = digests[:runtime_after]
      readable_runtime = records[:runtime_after] &&
                         records[:runtime_after][:status] == 'present' &&
                         records[:runtime_after][:bytes] > 0
      [key, {
        required_for_routes: required.include?(key),
        locations: records.transform_values { |file| file ? file[:status] : 'missing' },
        source_matches_bundle: digests[:source] && digests[:bundled] ? digests[:source] == digests[:bundled] : nil,
        bundle_matches_runtime: digests[:bundled] && runtime_after ? digests[:bundled] == runtime_after : nil,
        runtime_change: runtime_before && runtime_after ? (runtime_before == runtime_after ? 'unchanged' : 'changed') : 'not_observed_at_both_ends',
        runtime_evidence_available: !!readable_runtime
      }]
    end
  end

  def self.complete?(comparisons, routes:)
    routes && !routes.empty? && comparisons.values.all? do |entry|
      !entry[:required_for_routes] ||
        (entry[:runtime_evidence_available] && entry[:runtime_change] != 'changed')
    end
  end
end

# Loading this file permits isolated fixture checks without launching an app.
if $PROGRAM_NAME == __FILE__

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
  bundled_assets = File.expand_path('../Frameworks/App.framework/Resources/flutter_assets/assets/kokoro', File.dirname(app))
  runtime_assets = File.join(Etc.getpwuid.dir, 'Library', 'Containers', bundle_id.strip,
                            'Data', 'Library', 'Application Support', bundle_id.strip, 'kokoro')
  asset_snapshots = {
    source: NativeBaselineAssets.snapshot(File.join(root, 'assets/kokoro')),
    bundled: NativeBaselineAssets.snapshot(bundled_assets),
    runtime_before: NativeBaselineAssets.snapshot(runtime_assets, model_directory: 'models')
  }
  fixture = File.join(root, 'test/fixtures/prepared_runtime_aba.txt')
  probe_fixture = File.join(output, 'prepared_runtime_aba.txt')
  FileUtils.cp(fixture, probe_fixture)
  log_path = File.join(output, 'native.log')
  metadata = {
    bundle_id: bundle_id.strip,
    fixture_sha256: Digest::SHA256.file(fixture).hexdigest,
    app: app,
    limitation: 'Export only; process termination is not native cleanup evidence',
    asset_locations: {
      source: File.join(root, 'assets/kokoro'), bundled: bundled_assets,
      runtime: runtime_assets,
      runtime_path_basis: 'macOS sandbox Application Support path for the required bundle id'
    },
    asset_snapshots: asset_snapshots,
    asset_evidence_limit: 'Filesystem snapshots, not per-inference attestation; cached audio may predate these files'
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
    asset_snapshots[:runtime_after] = NativeBaselineAssets.snapshot(runtime_assets, model_directory: 'models')
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
  required_assets = ['model/kokoro-v1.0.onnx'] +
                    (metadata[:routes] || []).map { |route| "voices/#{route.fetch('voiceId')}.npy" }
  metadata[:asset_comparisons] = NativeBaselineAssets.comparisons(asset_snapshots, required_assets)
  metadata[:runtime_asset_evidence_complete] = !!NativeBaselineAssets.complete?(
    metadata[:asset_comparisons], routes: metadata[:routes]
  )
  metadata[:inference_observed] = metadata[:native_snapshots].any? { |entry| entry[:method] == 'runInference' }
  File.write(File.join(output, 'run.json'), JSON.pretty_generate(metadata))
  puts JSON.pretty_generate(metadata)
  failed = metadata[:timeout] || metadata[:forced_kill] ||
           !metadata[:runtime_asset_evidence_complete] ||
           (metadata[:process_exit] && metadata[:process_exit] != 0) ||
           !File.exist?(File.join(output, 'aba.wav')) ||
           !File.read(log_path).include?('Summary: 1 succeeded, 0 failed.')
  exit(failed ? 1 : 0)
end
