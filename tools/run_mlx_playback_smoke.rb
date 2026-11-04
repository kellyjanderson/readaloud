#!/usr/bin/env ruby
# Pass the native executable built with tools/mlx_playback_smoke.dart.
require 'json'
require 'fileutils'
require 'timeout'
require 'digest'
require 'rbconfig'

abort 'Usage: run_mlx_playback_smoke.rb APP_EXECUTABLE NEW_OUTPUT_DIRECTORY [ENGINE...]' if ARGV.length < 2
app, output, *engines = ARGV
bundle = File.expand_path('../..', File.dirname(app))
abort 'Release signing/entitlement preflight failed' unless system(RbConfig.ruby, File.join(__dir__, 'verify_macos_release_entitlements.rb'), bundle)
engines = %w[voxtral_4b qwen3_tts_1_7b moss_tts_8b] if engines.empty?
abort 'Output already exists' if File.exist?(output)
FileUtils.mkdir_p(output)
if ENV['READALOUD_SMOKE_DOCUMENT_PATH']
  source = ENV.fetch('READALOUD_SMOKE_DOCUMENT_PATH')
  File.write(File.join(output, 'fixture.json'), JSON.pretty_generate({sourcePath: source, bytes: File.size(source), sha256: Digest::SHA256.file(source).hexdigest}))
else
  File.write(File.join(output, 'fixture.txt'), ENV.fetch('READALOUD_SMOKE_TEXT', 'Default dialogue in tools/mlx_playback_smoke.dart'))
end
File.write(File.join(output, 'executable.sha256'), Digest::SHA256.file(app).hexdigest)
failures = []
engines.each do |engine|
  pid = nil
  receipt = File.join(output, "#{engine}.json")
  begin
    File.open(File.join(output, "#{engine}.log"), 'w') do |log|
      pid = Process.spawn(app, engine, receipt, out: log, err: log, pgroup: true)
      _, status = Timeout.timeout(360) { Process.wait2(pid) }
      raise "App exited #{status.inspect} without a receipt; see #{engine}.log" unless File.file?(receipt)
      result = JSON.parse(File.read(receipt))
      raise "Playback failed: #{result}" unless status.success? && result['passed'] && result['positionMs'] >= 500 && result['peakPcm16'] >= 100
      puts "PASS #{engine}: position=#{result['positionMs']}ms, peak=#{result['peakPcm16']}, elapsed=#{result['elapsedMs']}ms"
    end
  rescue => error
    failures << engine
    warn "FAIL #{engine}: #{error}"
  ensure
    # Also reap inference children after failure/timeout; never leave a test app.
    if pid
      begin
        Process.kill('TERM', -pid)
      rescue Errno::ESRCH
      end
      begin
        Timeout.timeout(5) { Process.waitpid(pid) }
      rescue Timeout::Error
        Process.kill('KILL', -pid) rescue Errno::ESRCH
        Process.waitpid(pid) rescue Errno::ECHILD
      rescue Errno::ECHILD
      end
    end
  end
end
abort "Failed engines: #{failures.join(', ')}" unless failures.empty?
