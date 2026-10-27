# frozen_string_literal: true

require_relative 'release_notices'
require 'fileutils'
require 'open3'
require 'find'
require 'time'
require 'securerandom'

# Local QA admission only (Refs #83, #91, #55). Receipts are local evidence,
# not cryptographic attestations from a trusted remote builder or release clearance.
#
# Protocol, run from the exact clean build checkout:
#   ruby tools/package_macos_candidate.rb preflight
#   ruby tools/package_macos_candidate.rb build APP BUILD.json -- flutter build macos ...
#   ruby tools/package_macos_candidate.rb smoke-template APP BUILD.json > SMOKE.json
#   ruby tools/package_macos_candidate.rb profile-preflight APP BUILD.json > EMPTY.json
# Run profile-preflight BEFORE launch. After the OS creates the QA container,
# copy EMPTY.json into that container and point profile.isolation_evidence at it.
# Run the normal app in a NEW disposable profile, then fill SMOKE.json with the
# operator, UTC times, observations and absolute evidence paths. Never clear a
# user's profile. An export WAV proves synthesis; a separate live capture and
# observation prove playback. Pending/failed fields reject packaging. This is a
# basic functional smoke; #83 timing, continuity and human acceptance remain open.
# notices_ui_evidence must retain the native Help/overflow route and visible
# Open Source Notices content; record that observation in open_source_notices.
#   ruby tools/package_macos_candidate.rb package APP NEW_DIRECTORY BUILD.json SMOKE.json
#
# Build owns one foreground child process group, one bounded disk log (64 MiB),
# a unique build_id, a 30-minute deadline and TERM/KILL cleanup on timeout/interrupt.
# No parallel build is supported in a checkout; the coordinator owns serialization.
# A changed source/asset/bundle invalidates earlier success, including after copy.
module MacosCandidate
  MODEL = 'assets/kokoro/model/kokoro-v1.0.onnx'
  MODEL_SHA256 = '7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5'
  NOTICES = 'third_party/licenses/NOTICES.txt'
  DATA = %w[assets/tokenizer_vocab.json assets/lexicon.json assets/us_gold.json assets/us_silver.json assets/gb_gold.json assets/gb_silver.json assets/cmudict.dict].freeze
  ASSET_ROOT = 'Contents/Frameworks/App.framework/Resources/flutter_assets'
  STEPS = %w[startup normal_document_intake voice_choices synthesis actual_playback open_source_notices].freeze
  LOG_LIMIT = 64 * 1024 * 1024
  PRODUCTION_BUNDLE_IDENTIFIER = 'com.kellyjanderson.readAloud'
  BUILD_ENVIRONMENT_KEYS = %w[PATH HOME TMPDIR USER LOGNAME LANG LC_ALL PUB_CACHE FLUTTER_ROOT DEVELOPER_DIR SDKROOT ARCHS MACOSX_DEPLOYMENT_TARGET PRODUCT_BUNDLE_IDENTIFIER XCODE_XCCONFIG_FILE].freeze

  def self.qa_identifier(build_id)
    raise 'Invalid build UUID' unless build_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    "#{PRODUCTION_BUNDLE_IDENTIFIER}.qa.#{build_id.delete('-')}"
  end

  def self.capture(*command, chdir: ReleaseNotices::ROOT)
    output, status = Open3.capture2e(*command, chdir: chdir)
    raise "Command failed: #{command.inspect}\n#{output}" unless status.success?
    output.strip
  end

  def self.file_identity(path, allow_empty: false)
    raise "Missing/empty/unreadable file: #{path}" unless File.file?(path) && File.readable?(path) && (allow_empty || File.size(path).positive?)
    { 'size' => File.size(path), 'sha256' => Digest::SHA256.file(path).hexdigest }
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(value))
  end

  def self.write_new(path, value)
    File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.puts(JSON.pretty_generate(value)) }
  end

  def self.required_assets(root)
    catalog = File.read(File.join(root, 'lib/src/services/kokoro_voice_catalog.dart'))
    block = catalog[/bundledVoiceIds\s*=\s*<String>\[(.*?)\];/m, 1]
    raise 'Cannot establish required voice catalog' unless block
    voices = block.scan(/'([a-z_]+)'/).flatten
    raise 'Required voice catalog is empty' if voices.empty?
    ([MODEL, NOTICES] + DATA + voices.map { |id| "assets/kokoro/voices/#{id}.npy" }).sort
  end

  def self.validate_assets(directory, paths, model_sha256: MODEL_SHA256)
    paths.to_h do |relative|
      path = File.join(directory, relative)
      identity = file_identity(path)
      if relative == MODEL
        raise 'Invalid/corrupt model: expected preserved Kokoro SHA256' unless identity['sha256'] == model_sha256
      elsif relative.end_with?('.json')
        parsed = JSON.parse(File.read(path))
        raise "Invalid tokenizer JSON: #{relative}" unless parsed.is_a?(Hash) && (relative.end_with?('/lexicon.json') || !parsed.empty?)
      elsif relative.end_with?('.npy')
        File.open(path, 'rb') do |file|
          prefix = file.read(10)
          raise "Invalid voice NPY: #{relative}" unless prefix && prefix.byteslice(0, 8) == "\x93NUMPY\x01\x00".b
          length = prefix.byteslice(8, 2).unpack1('v')
          header = file.read(length)
          valid = header && header.match?(/'descr':\s*'<f4'/) && header.match?(/'fortran_order':\s*False/) && header.match?(/'shape':\s*\(510,\s*1,\s*256\)/)
          raise "Invalid/truncated voice NPY: #{relative}" unless valid && File.size(path) == 10 + length + 510 * 256 * 4
          values = file.read.unpack('e*')
          raise "Nonfinite/empty voice NPY: #{relative}" unless values.all?(&:finite?) && values.any? { |v| !v.zero? }
        end
      elsif relative.end_with?('.dict')
        raise 'Invalid pronunciation dictionary' unless File.foreach(path).any? { |line| line.match?(/^[^\s]+\s+[A-Z][A-Z0-2]*(?:\s|$)/) }
      end
      [relative, identity]
    end
  end

  def self.source(root)
    status = capture('git', 'status', '--porcelain', '--untracked-files=all', chdir: root)
    raise 'Source must be clean for candidate provenance' unless status.empty?
    paths = capture('git', 'ls-files', '-z', chdir: root).split("\0")
    tracked = paths.sort.to_h { |path| [path, file_identity(File.join(root, path), allow_empty: true)] }
    { 'root' => File.realpath(root), 'commit' => capture('git', 'rev-parse', 'HEAD', chdir: root),
      'dirty' => false, 'tracked_files_sha256' => digest(tracked) }
  end

  def self.preflight(root = ReleaseNotices::ROOT)
    { 'source' => source(root), 'assets' => validate_assets(root, required_assets(root)) }
  end

  def self.tree(app)
    raise 'Input must be an existing .app directory' unless File.directory?(app) && app.end_with?('.app')
    root = File.realpath(app)
    entries = []
    Find.find(app) do |path|
      next if path == app
      relative = path.delete_prefix(app + '/')
      if File.symlink?(path)
        raise "Bundle symlink escapes or is broken: #{relative}" unless File.realpath(path).start_with?(root + '/')
        entries << { 'path' => relative, 'symlink' => File.readlink(path) }
      elsif File.file?(path)
        entries << { 'path' => relative, 'mode' => File.stat(path).mode & 0o777 }.merge(file_identity(path, allow_empty: true))
      end
    end
    entries.sort_by { |entry| entry['path'] }
  end

  def self.bundle(app, assets)
    name = capture('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleExecutable', File.join(app, 'Contents/Info.plist'))
    raise 'Unsafe executable name' unless name.match?(/\A[^\/.]+\z/)
    identifier = capture('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier', File.join(app, 'Contents/Info.plist'))
    raise 'Candidate requires a unique QA bundle identifier distinct from production' unless identifier.match?(/\A#{Regexp.escape(PRODUCTION_BUNDLE_IDENTIFIER)}\.qa\.[0-9a-f]{32}\z/)
    minimum_os = capture('/usr/libexec/PlistBuddy', '-c', 'Print :LSMinimumSystemVersion', File.join(app, 'Contents/Info.plist'))
    executable = "Contents/MacOS/#{name}"
    binaries = [executable, 'Contents/Frameworks/App.framework/App', 'Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS']
    architectures = binaries.to_h do |relative|
      path = File.join(app, relative)
      file_identity(path)
      archs = capture('/usr/bin/lipo', '-archs', path).split.sort
      raise "Required candidate runtime binary must be arm64-only: #{relative}" unless archs == ['arm64']
      [relative, archs]
    end
    bundled = validate_assets(File.join(app, ASSET_ROOT), assets.keys)
    raise 'Bundle assets differ from preflight inputs' unless bundled == assets
    signature = capture('/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', app).gsub(app, '<APP>')
    files = tree(app)
    { 'tree_sha256' => digest(files), 'files' => files, 'executable' => executable,
      'bundle_identifier' => identifier, 'minimum_system_version' => minimum_os,
      'executable_identity' => file_identity(File.join(app, executable)), 'architectures' => architectures,
      'signature_verification' => signature, 'assets' => bundled }
  end

  def self.toolchain(root)
    flutter = ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'flutter') }.find { |path| File.executable?(path) }
    raise 'Flutter SDK executable missing from PATH' unless flutter
    flutter = File.realpath(flutter)
    dart = File.join(File.dirname(flutter), 'cache/dart-sdk/bin/dart')
    dart_architectures = capture('/usr/bin/lipo', '-archs', dart).split.sort
    raise 'Flutter SDK Dart binary lacks arm64' unless dart_architectures.include?('arm64')
    { 'flutter_path' => flutter, 'flutter_executable' => file_identity(flutter),
      'dart_executable' => file_identity(dart), 'dart_architectures' => dart_architectures,
      'flutter_version' => JSON.parse(capture(flutter, '--version', '--machine', chdir: root)),
      'xcode' => capture('/usr/bin/xcodebuild', '-version'),
      'macos_sdk' => capture('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version'),
      'macos_sdk_path' => capture('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'),
      'host_architecture' => capture('/usr/bin/uname', '-m') }
  end

  def self.build_command(command, sdk)
    raise 'Only the recorded Flutter SDK build macos command can attest a build' unless command.is_a?(Array) && command[1, 2] == %w[build macos]
    executable = command.first == 'flutter' ? sdk.fetch('flutter_path') : File.realpath(command.first)
    raise 'Build command uses a different Flutter SDK' unless executable == sdk.fetch('flutter_path')
    # A target outside this snapshot would break source-to-build correspondence.
    raise 'Alternate target/project paths are not supported for candidate builds' if command.drop(3).any? { |arg| arg == '-t' || arg.start_with?('--target', '--project', '-t=') }
    raise 'Candidate build must use release mode' if command.drop(3).any? { |arg| arg != '--release' && arg.match?(/\A--(?:no-)?(?:debug|profile|release)(?:=|\z)/) }
    [executable, 'build', 'macos', '--release', *command.drop(3).reject { |arg| arg == '--release' }]
  end

  def self.build_environment(root, sdk, build_id, override, inherited: ENV.to_h)
    variables = inherited.select { |key, _| BUILD_ENVIRONMENT_KEYS.include?(key) }
    raise 'Build PATH and absolute HOME are required' unless variables['PATH'] && !variables['PATH'].empty? && variables['HOME']&.start_with?('/')
    raise 'SDKROOT differs from recorded macOS SDK' if variables.key?('SDKROOT') && variables['SDKROOT'] != sdk.fetch('macos_sdk_path')
    raise 'ARCHS must be arm64 for candidate builds' unless !variables.key?('ARCHS') || variables['ARCHS'] == 'arm64'
    identifier = qa_identifier(build_id)
    raise 'Inherited PRODUCT_BUNDLE_IDENTIFIER differs from unique QA build identity' if variables.key?('PRODUCT_BUNDLE_IDENTIFIER') && variables['PRODUCT_BUNDLE_IDENTIFIER'] != identifier
    raise 'External XCODE_XCCONFIG_FILE is not admitted' if variables.key?('XCODE_XCCONFIG_FILE') && variables['XCODE_XCCONFIG_FILE'] != override
    targets = File.read(File.join(root, 'macos/Runner.xcodeproj/project.pbxproj')).scan(/MACOSX_DEPLOYMENT_TARGET = ([\d.]+);/).flatten.uniq
    target = variables['MACOSX_DEPLOYMENT_TARGET'] || (targets.one? && targets.first)
    raise 'Explicit numeric MACOSX_DEPLOYMENT_TARGET required' unless target && target.match?(/\A\d+(?:\.\d+){1,2}\z/)
    variables.merge('ARCHS' => 'arm64', 'PRODUCT_BUNDLE_IDENTIFIER' => identifier,
      'MACOSX_DEPLOYMENT_TARGET' => target, 'SDKROOT' => variables.fetch('SDKROOT', sdk.fetch('macos_sdk_path')),
      'XCODE_XCCONFIG_FILE' => override)
  end

  def self.xcode_override(environment)
    %w[ARCHS MACOSX_DEPLOYMENT_TARGET PRODUCT_BUNDLE_IDENTIFIER].map { |key| "#{key} = #{environment.fetch(key)}\n" }.join
  end

  def self.run_build(command, root, log, environment: {}, timeout: 1800)
    raise 'Build command is empty' if command.empty?
    pid = nil
    File.open(log, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      pid = Process.spawn(environment, *command, chdir: root, out: file, err: [:child, :out], pgroup: true, unsetenv_others: true)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        result = Process.waitpid2(pid, Process::WNOHANG)
        if result
          pid = nil
          raise "Build command failed (#{result.last.exitstatus}); see #{log}" unless result.last.success?
          break
        end
        raise 'Build timed out' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise 'Build log exceeded 64 MiB' if File.size(log) > LOG_LIMIT
        sleep 0.1
      end
    end
    raise 'Build log exceeded 64 MiB' if File.size(log) > LOG_LIMIT
  ensure
    if pid
      begin
        Process.kill('TERM', -pid)
        sleep 0.2
        reaped = Process.waitpid(pid, Process::WNOHANG)
        begin
          Process.kill('KILL', -pid)
        rescue Errno::EPERM
          # macOS can report EPERM for an already empty process group.
          # Never suppress it while the owned child is still running.
          raise unless reaped
        end
      rescue Errno::ESRCH
        # Already exited; still reap our child.
      ensure
        Process.waitpid(pid) rescue Errno::ECHILD
      end
    end
  end

  def self.build(root:, app:, receipt:, command:)
    raise 'Fresh build required: expected app output already exists' if File.exist?(app)
    raise 'Build receipt already exists' if File.exist?(receipt)
    inputs = preflight(root)
    sdk = toolchain(root)
    command = build_command(command, sdk)
    build_id = SecureRandom.uuid
    override_path = receipt + '.build.xcconfig'
    environment = build_environment(root, sdk, build_id, override_path)
    File.open(override_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(xcode_override(environment)) }
    override_identity = file_identity(override_path)
    started = Time.now.utc.iso8601(6)
    log = receipt + '.build.log'
    run_build(command, root, log, environment: environment)
    raise 'Source/assets changed during build' unless preflight(root) == inputs
    raise 'SDK changed during build' unless toolchain(root) == sdk
    raise 'Xcode override changed during build' unless file_identity(override_path) == override_identity
    identity = bundle(app, inputs.fetch('assets'))
    raise 'Built app does not match effective QA identifier/deployment target' unless identity['bundle_identifier'] == environment['PRODUCT_BUNDLE_IDENTIFIER'] && identity['minimum_system_version'] == environment['MACOSX_DEPLOYMENT_TARGET']
    value = { 'schema' => 3, 'kind' => 'build', 'build_id' => build_id, 'build_mode' => 'release',
      'started_at' => started, 'completed_at' => Time.now.utc.iso8601(6),
      'command' => command, 'cwd' => File.realpath(root), 'exit_status' => 0,
      'fresh_output' => true, 'input_app' => File.expand_path(app), 'inputs' => inputs,
      'toolchain' => sdk, 'build_log' => { 'path' => File.expand_path(log) }.merge(file_identity(log)), 'bundle' => identity }
    value['build_environment'] = environment
    value['xcode_override'] = { 'path' => override_path }.merge(override_identity)
    write_new(receipt, value)
    value
  end

  def self.read_build(root, app, path)
    value = JSON.parse(File.read(path))
    raise 'Unattested build receipt' unless value['schema'] == 3 && value['kind'] == 'build' && value['fresh_output'] == true && value['exit_status'] == 0 && value['build_id'].is_a?(String) && !value['build_id'].empty?
    raise 'Missing build command' unless value['command'].is_a?(Array) && !value['command'].empty?
    raise 'Build receipt app path mismatch' unless value['input_app'] == File.expand_path(app)
    raise 'Stale source/assets receipt' unless value['inputs'] == preflight(root)
    raise 'Stale SDK receipt' unless value['toolchain'] == toolchain(root)
    raise 'Unattested build command' unless value['command'] == build_command(value['command'], value['toolchain'])
    raise 'Unattested release build mode' unless value['build_mode'] == 'release'
    override = value.fetch('xcode_override')
    environment = build_environment(root, value['toolchain'], value['build_id'], override.fetch('path'))
    raise 'Stale/unallowlisted build environment' unless value['build_environment'] == environment
    raise 'Xcode override changed' unless override.reject { |key, _| key == 'path' } == file_identity(override['path']) && File.read(override['path']) == xcode_override(environment)
    log = value.fetch('build_log')
    raise 'Build log changed' unless log.reject { |key, _| key == 'path' } == file_identity(log.fetch('path'))
    raise 'Stale bundle receipt' unless value['bundle'] == bundle(app, value.fetch('inputs').fetch('assets'))
    raise 'Build QA identity/deployment target mismatch' unless value.dig('bundle', 'bundle_identifier') == qa_identifier(value['build_id']) && value.dig('bundle', 'minimum_system_version') == environment['MACOSX_DEPLOYMENT_TARGET']
    raise 'Invalid build timestamps' unless Time.iso8601(value.fetch('completed_at')) >= Time.iso8601(value.fetch('started_at'))
    value
  end

  def self.smoke_template(build)
    paths = profile_paths(build)
    { 'schema' => 3, 'kind' => 'smoke', 'build_id' => build.fetch('build_id'),
      'bundle_sha256' => build.fetch('bundle').fetch('tree_sha256'), 'operator' => '',
      'bundle_identifier' => build.fetch('bundle').fetch('bundle_identifier'),
      'started_at' => '', 'completed_at' => '',
      'profile' => { 'path' => paths['application_support'], 'container_path' => paths['container'], 'created_at' => '',
        'existing_model_or_audio_cache' => nil, 'isolation_evidence' => File.join(paths['application_support'], 'qualification/empty-profile.json') },
      'steps' => STEPS.to_h { |step| [step, { 'status' => 'pending', 'observation' => '' }] },
      'startup_errors' => [], 'runtime_log' => '', 'normal_document' => '', 'synthesized_wav' => '',
      'live_capture_wav' => '', 'output_provenance' => '', 'notices_ui_evidence' => '',
      'limits' => 'Basic functional smoke only; RC2 timing/continuity and residual human gate remain separate.' }
  end

  def self.profile_paths(build)
    identifier = build.fetch('bundle').fetch('bundle_identifier')
    raise 'Profile requires unique build QA identifier' unless identifier == qa_identifier(build.fetch('build_id'))
    home = build.fetch('build_environment').fetch('HOME')
    raise 'Absolute build HOME required for QA container identity' unless home.start_with?('/')
    container = File.join(home, 'Library/Containers', identifier)
    support = File.join(container, 'Data/Library/Application Support', identifier)
    { 'container' => container, 'application_support' => support,
      'cache_paths' => [File.join(support, 'kokoro/models'), File.join(support, 'kokoro/voices'),
        File.join(support, 'kokoro/cache'), File.join(container, 'Data/.read-aloud/kokoro-runtime')] }
  end

  # Read-only: capture the absence BEFORE first launch. Preserve stdout outside
  # the container, then copy it under the matching OS-created container afterward.
  def self.profile_preflight(build)
    paths = profile_paths(build)
    raise 'QA container already exists; use a new build/identifier, never clear user data' if File.exist?(paths['container']) || File.symlink?(paths['container'])
    { 'schema' => 1, 'kind' => 'empty_qa_profile', 'build_id' => build.fetch('build_id'),
      'bundle_sha256' => build.fetch('bundle').fetch('tree_sha256'),
      'bundle_identifier' => build.fetch('bundle').fetch('bundle_identifier'),
      'checked_at' => Time.now.utc.iso8601(6), 'container_path' => paths['container'],
      'application_support_path' => paths['application_support'], 'container_existed' => false,
      'runtime_cache_entries' => paths['cache_paths'].to_h { |path| [path, []] } }
  end

  # Conservative PCM16 WAV admission; validates chunk lengths, framing, nonzero
  # finite samples and >=100 ms output. It does not claim perceptual speech quality.
  def self.wav(path)
    identity = file_identity(path)
    raise 'WAV evidence exceeds 256 MiB' if identity['size'] > 256 * 1024 * 1024
    bytes = File.binread(path)
    raise "Invalid WAV: #{path}" unless bytes.byteslice(0, 4) == 'RIFF' && bytes.byteslice(8, 4) == 'WAVE' && bytes.byteslice(4, 4).unpack1('V') + 8 == bytes.bytesize
    offset = 12
    format = pcm = nil
    while offset + 8 <= bytes.bytesize
      name = bytes.byteslice(offset, 4)
      length = bytes.byteslice(offset + 4, 4).unpack1('V')
      raise 'Truncated WAV chunk' if offset + 8 + length > bytes.bytesize
      chunk = bytes.byteslice(offset + 8, length)
      format = chunk.unpack('vvVVvv') if name == 'fmt ' && length >= 16
      pcm = chunk if name == 'data'
      offset += 8 + length + (length.odd? ? 1 : 0)
    end
    raise 'WAV must contain PCM16 frames' unless format && pcm && format[0] == 1 && format[5] == 16 && [1, 2].include?(format[1]) && format[2].positive? && format[4] == format[1] * 2 && format[3] == format[2] * format[4] && (pcm.bytesize % format[4]).zero?
    duration = pcm.bytesize.to_f / format[3]
    audible = false
    pcm.unpack('s<*') { |sample| audible = true if sample.abs > 1 }
    raise 'WAV is silent or too short' unless duration >= 0.1 && audible
    identity.merge('duration_seconds' => duration, 'sample_rate' => format[2], 'channels' => format[1])
  end

  def self.validate_smoke(build, smoke)
    raise 'Unattested/stale smoke receipt' unless smoke['schema'] == 3 && smoke['kind'] == 'smoke' && smoke['build_id'] == build['build_id'] && smoke['bundle_sha256'] == build.dig('bundle', 'tree_sha256') && smoke['bundle_identifier'] == build.dig('bundle', 'bundle_identifier')
    raise 'Smoke operator missing' if smoke.fetch('operator').strip.empty?
    started = Time.iso8601(smoke.fetch('started_at'))
    raise 'Smoke predates build or has invalid timestamps' unless started >= Time.iso8601(build.fetch('completed_at')) && Time.iso8601(smoke.fetch('completed_at')) >= started
    profile = smoke.fetch('profile')
    paths = profile_paths(build)
    raise 'Profile/container does not match QA bundle identifier' unless profile['path'] == paths['application_support'] && profile['container_path'] == paths['container']
    raise 'Fresh isolated profile not attested' unless profile['existing_model_or_audio_cache'] == false && profile.fetch('path').start_with?('/') && Time.iso8601(profile.fetch('created_at')) >= Time.iso8601(build.fetch('completed_at')) && Time.iso8601(profile.fetch('created_at')) <= started
    STEPS.each do |step|
      result = smoke.fetch('steps').fetch(step)
      raise "Smoke step not passed: #{step}" unless result['status'] == 'passed' && !result.fetch('observation').strip.empty?
    end
    raise 'Startup errors reject readiness' unless smoke['startup_errors'] == []
    raise 'Output provenance missing' if smoke.fetch('output_provenance').strip.empty?
    evidence = %w[runtime_log normal_document notices_ui_evidence].to_h do |key|
      path = smoke.fetch(key)
      raise "Evidence path must be absolute: #{key}" unless path.start_with?('/')
      [key, { 'path' => path }.merge(file_identity(path))]
    end
    isolation = profile.fetch('isolation_evidence')
    raise 'Profile isolation evidence must be absolute' unless isolation.start_with?('/')
    container = paths.fetch('container')
    raise 'Profile evidence must be inside the matching QA container' unless isolation.start_with?(container + '/') && !File.symlink?(container) && File.realpath(isolation).start_with?(File.realpath(container) + '/')
    proof = JSON.parse(File.read(isolation))
    empty_entries = paths.fetch('cache_paths').to_h { |path| [path, []] }
    raise 'Missing/stale/nonempty runtime-cache isolation evidence' unless proof['schema'] == 1 && proof['kind'] == 'empty_qa_profile' && proof['build_id'] == build['build_id'] && proof['bundle_sha256'] == smoke['bundle_sha256'] && proof['bundle_identifier'] == smoke['bundle_identifier'] && proof['container_path'] == container && proof['application_support_path'] == paths['application_support'] && proof['container_existed'] == false && proof['runtime_cache_entries'] == empty_entries
    checked = Time.iso8601(proof.fetch('checked_at'))
    raise 'Runtime-cache isolation evidence must precede launch after build' unless checked >= Time.iso8601(build.fetch('completed_at')) && checked <= started && proof['checked_at'] == profile['created_at']
    evidence['profile_isolation'] = { 'path' => isolation }.merge(file_identity(isolation))
    runtime_log = File.read(smoke.fetch('runtime_log'))
    raise 'Startup/runtime error in smoke log' if runtime_log.match?(/Unable to load asset|ONNXRuntimeError|Unhandled Exception|The bundled Kokoro speech model is missing|Kokoro[^\n]*(?:unavailable|could not|failed)|Audio playback failed/i)
    %w[synthesized_wav live_capture_wav].each do |key|
      path = smoke.fetch(key)
      raise "Evidence path must be absolute: #{key}" unless path.start_with?('/')
      raise "Stale output predates smoke: #{key}" if File.mtime(path) < started
      evidence[key] = { 'path' => path }.merge(wav(path))
    end
    raise 'Live capture must be separate from synthesis output' if File.realpath(smoke['synthesized_wav']) == File.realpath(smoke['live_capture_wav']) || evidence['synthesized_wav']['sha256'] == evidence['live_capture_wav']['sha256']
    evidence
  end

  def self.package(root:, app:, output:, build_path:, smoke_path:)
    raise 'Output must not exist' if File.exist?(output)
    raise 'Output cannot be inside input app' if File.expand_path(output).start_with?(File.expand_path(app) + '/')
    inventory = ReleaseNotices.validate(root)
    raise 'Committed NOTICES.txt is stale' unless File.read(File.join(root, 'third_party/licenses/NOTICES.txt')) == ReleaseNotices.text(inventory, root)
    build = read_build(root, app, build_path)
    smoke = JSON.parse(File.read(smoke_path))
    evidence = validate_smoke(build, smoke)
    FileUtils.mkdir_p(output)
    staged_app = File.join(output, File.basename(app))
    system('/usr/bin/ditto', app, staged_app, exception: true)
    raise 'Copied bundle changed' unless bundle(staged_app, build.dig('inputs', 'assets')) == build['bundle']
    FileUtils.cp_r(File.join(root, 'third_party/licenses'), File.join(output, 'Open Source Notices'))
    FileUtils.cp(File.join(root, 'docs/release-compliance.md'), File.join(output, 'RELEASE-COMPLIANCE.md'))
    evidence.each do |key, item|
      destination = File.join(output, 'evidence', key + File.extname(item['path']))
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(item['path'], destination)
      raise 'Evidence changed while copying' unless file_identity(destination) == item.slice('size', 'sha256')
      item['staged_path'] = destination.delete_prefix(output + '/')
    end
    FileUtils.cp(build.fetch('build_log').fetch('path'), File.join(output, 'build.log'))
    raise 'Build log changed while copying' unless file_identity(File.join(output, 'build.log')) == build['build_log'].slice('size', 'sha256')
    read_build(root, app, build_path)
    value = { 'schema' => 3, 'purpose' => 'Local QA functional smoke; NOT a cleared public release or final RC2 acceptance',
      'local_qa_functional_readiness' => 'passed', 'public_release_cleared' => false,
      'release_blockers' => inventory.fetch('blockers'), 'build' => build, 'smoke' => smoke, 'evidence' => evidence }
    write_new(File.join(output, 'candidate.json'), value)
    value
  end

  def self.cli(args)
    raise 'macOS required' unless RUBY_PLATFORM.include?('darwin')
    mode = args.shift
    root = ReleaseNotices::ROOT
    case mode
    when 'preflight'
      raise 'preflight takes no arguments' unless args.empty?
      puts JSON.pretty_generate(preflight(root))
    when 'build'
      app, receipt, separator, *command = args
      raise 'build APP BUILD.json -- COMMAND...' unless app && receipt && separator == '--' && !command.empty?
      puts JSON.pretty_generate(build(root: root, app: File.expand_path(app), receipt: File.expand_path(receipt), command: command))
    when 'smoke-template'
      raise 'smoke-template APP BUILD.json' unless args.size == 2
      puts JSON.pretty_generate(smoke_template(read_build(root, File.expand_path(args[0]), File.expand_path(args[1]))))
    when 'profile-preflight'
      raise 'profile-preflight APP BUILD.json' unless args.size == 2
      puts JSON.pretty_generate(profile_preflight(read_build(root, File.expand_path(args[0]), File.expand_path(args[1]))))
    when 'package'
      raise 'package APP NEW_DIRECTORY BUILD.json SMOKE.json' unless args.size == 4
      app, output, build_path, smoke_path = args.map { |path| File.expand_path(path) }
      package(root: root, app: app, output: output, build_path: build_path, smoke_path: smoke_path)
      puts "Qualified local QA candidate staged at #{output}; public release and final RC2 acceptance remain separate."
    else
      raise 'Usage: package_macos_candidate.rb preflight | build | smoke-template | profile-preflight | package (see protocol in script)'
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    MacosCandidate.cli(ARGV.dup)
  rescue StandardError => error
    abort "Candidate rejected: #{error.message}"
  end
end
