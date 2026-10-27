# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'rbconfig'
require_relative 'package_macos_candidate'

class MacosCandidateTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('readaloud-candidate-test-')
    @assets = [MacosCandidate::MODEL, 'assets/kokoro/voices/af_heart.npy', 'assets/tokenizer_vocab.json', 'assets/cmudict.dict']
    @assets.each { |relative| FileUtils.mkdir_p(File.dirname(File.join(@root, relative))) }
    File.binwrite(File.join(@root, MacosCandidate::MODEL), 'known fixture model; not ONNX')
    @model_hash = Digest::SHA256.file(File.join(@root, MacosCandidate::MODEL)).hexdigest
    header = "{'descr': '<f4', 'fortran_order': False, 'shape': (510, 1, 256), }\n"
    @voice = File.join(@root, 'assets/kokoro/voices/af_heart.npy')
    File.binwrite(@voice, "\x93NUMPY\x01\x00".b + [header.bytesize].pack('v') + header + ([0.25] * (510 * 256)).pack('e*'))
    File.write(File.join(@root, 'assets/tokenizer_vocab.json'), '{"a":1}')
    File.write(File.join(@root, 'assets/cmudict.dict'), "HELLO  HH AH0 L OW1\n")
    @app = File.join(@root, 'Fixture.app')
    @build_path = File.join(@root, 'build.json')
    @log = File.join(@root, 'build.log')
    File.write(@log, "Synthetic build fixture\n")
    @inputs = { 'source' => { 'commit' => 'fixture', 'dirty' => false, 'tracked_files_sha256' => 'tracked' }, 'assets' => { 'fixture' => 'hash' } }
    @bundle = { 'tree_sha256' => 'bundle', 'executable_identity' => { 'sha256' => 'executable' } }
    @sdk = { 'flutter_version' => 'fixture sdk', 'flutter_path' => File.realpath(RbConfig.ruby) }
    @build = { 'schema' => 2, 'kind' => 'build', 'build_id' => 'fixture-id', 'fresh_output' => true,
      'input_app' => @app, 'command' => [File.realpath(RbConfig.ruby), 'build', 'macos'], 'cwd' => @root, 'exit_status' => 0,
      'started_at' => '2026-10-26T10:00:00Z', 'completed_at' => '2026-10-26T10:01:00Z',
      'inputs' => @inputs, 'toolchain' => @sdk, 'bundle' => @bundle,
      'build_log' => { 'path' => @log }.merge(MacosCandidate.file_identity(@log)) }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def assets
    MacosCandidate.validate_assets(@root, @assets, model_sha256: @model_hash)
  end

  def test_valid_assets_and_production_catalog
    assert_equal @assets.sort, assets.keys.sort
    production = MacosCandidate.required_assets(ReleaseNotices::ROOT)
    assert_equal 5, production.count { |path| path.end_with?('.npy') }
    assert_includes production, MacosCandidate::MODEL
    assert_includes production, 'assets/tokenizer_vocab.json'
  end

  def test_missing_empty_and_corrupt_model_rejected
    model = File.join(@root, MacosCandidate::MODEL)
    File.delete(model)
    assert_match(/Missing\/empty/, assert_raises(RuntimeError) { assets }.message)
    File.write(model, '')
    assert_match(/Missing\/empty/, assert_raises(RuntimeError) { assets }.message)
    File.write(model, 'corrupt fixture')
    assert_match(/Invalid\/corrupt model/, assert_raises(RuntimeError) { assets }.message)
  end

  def test_missing_voice_and_tokenizer_rejected
    File.delete(@voice)
    assert_match(/Missing\/empty/, assert_raises(RuntimeError) { assets }.message)
    File.write(@voice, 'bad voice')
    assert_match(/Invalid voice/, assert_raises(RuntimeError) { assets }.message)
    File.write(File.join(@root, 'assets/tokenizer_vocab.json'), '{bad json')
    assert_raises(JSON::ParserError) { MacosCandidate.validate_assets(@root, ['assets/tokenizer_vocab.json']) }
  end

  def test_truncated_nonfinite_and_zero_voice_rejected
    data = File.binread(@voice)
    File.binwrite(@voice, data.byteslice(0, data.bytesize - 4))
    assert_match(/truncated voice/, assert_raises(RuntimeError) { assets }.message)
    File.binwrite(@voice, data.byteslice(0, data.bytesize - 4) + [Float::NAN].pack('e'))
    assert_match(/Nonfinite/, assert_raises(RuntimeError) { assets }.message)
    start = 10 + data.byteslice(8, 2).unpack1('v')
    File.binwrite(@voice, data.byteslice(0, start) + "\0" * (510 * 256 * 4))
    assert_match(/Nonfinite\/empty/, assert_raises(RuntimeError) { assets }.message)
  end

  def read_build
    File.write(@build_path, JSON.generate(@build))
    with_stubs(preflight: @inputs, toolchain: @sdk, bundle: @bundle) do
      MacosCandidate.read_build(@root, @app, @build_path)
    end
  end

  def with_stubs(values)
    originals = values.to_h { |name, _| [name, MacosCandidate.method(name)] }
    values.each do |name, value|
      if value.is_a?(Proc)
        MacosCandidate.define_singleton_method(name, value)
      else
        MacosCandidate.define_singleton_method(name) { |*| value }
      end
    end
    yield
  ensure
    originals.each { |name, implementation| MacosCandidate.define_singleton_method(name, implementation) }
  end

  def test_matching_build_receipt_accepted
    assert_equal 'fixture-id', read_build['build_id']
  end

  def test_inventory_only_and_legacy_receipt_rejected
    @build = { 'schema' => 1, 'source_commit' => 'fixture' }
    assert_match(/Unattested build/, assert_raises(RuntimeError) { read_build }.message)
  end

  def test_stale_source_assets_bundle_sdk_and_log_rejected
    saved = Marshal.load(Marshal.dump(@build))
    [['inputs', { 'source' => 'other' }, /Stale source/], ['bundle', { 'tree_sha256' => 'old' }, /Stale bundle/], ['toolchain', {}, /Stale SDK/]].each do |key, value, error|
      @build = Marshal.load(Marshal.dump(saved))
      @build[key] = value
      assert_match error, assert_raises(RuntimeError) { read_build }.message
    end
    @build = saved
    File.write(@log, 'changed')
    assert_match(/Build log changed/, assert_raises(RuntimeError) { read_build }.message)
  end

  def test_wrong_app_and_missing_build_command_rejected
    @build['input_app'] = '/other.app'
    assert_match(/path mismatch/, assert_raises(RuntimeError) { read_build }.message)
    @build['input_app'] = @app
    @build.delete('command')
    assert_match(/Missing build command/, assert_raises(RuntimeError) { read_build }.message)
  end

  def test_arbitrary_copy_alternate_sdk_or_external_target_cannot_attest_build
    assert_match(/Only the recorded Flutter/, assert_raises(RuntimeError) { MacosCandidate.build_command(['cp', 'old.app', @app], @sdk) }.message)
    assert_match(/different Flutter SDK/, assert_raises(RuntimeError) { MacosCandidate.build_command(['/bin/sh', 'build', 'macos'], @sdk) }.message)
    assert_match(/Alternate target/, assert_raises(RuntimeError) { MacosCandidate.build_command(['flutter', 'build', 'macos', '--target=/outside.dart'], @sdk) }.message)
    assert_equal [@sdk['flutter_path'], 'build', 'macos', '--debug'], MacosCandidate.build_command(['flutter', 'build', 'macos', '--debug'], @sdk)
  end

  def wav(path, sample: 1000)
    pcm = ([sample, -sample] * 2400).pack('s<*')
    fmt = [1, 1, 24_000, 48_000, 2, 16].pack('vvVVvv')
    File.binwrite(path, 'RIFF' + [36 + pcm.bytesize].pack('V') + 'WAVEfmt ' + [16].pack('V') + fmt + 'data' + [pcm.bytesize].pack('V') + pcm)
  end

  def smoke
    value = MacosCandidate.smoke_template(@build)
    value['operator'] = 'Synthetic test fixture (no native execution)'
    value['started_at'] = '2026-10-26T10:02:00Z'
    value['completed_at'] = '2026-10-26T10:03:00Z'
    value['profile'] = { 'path' => File.join(@root, 'fresh-profile'), 'created_at' => '2026-10-26T10:01:30Z', 'existing_model_or_audio_cache' => false, 'isolation_evidence' => File.join(@root, 'isolation.log') }
    File.write(value['profile']['isolation_evidence'], 'Fixture profile created empty with isolated application support')
    MacosCandidate::STEPS.each { |step| value['steps'][step] = { 'status' => 'passed', 'observation' => 'Fixture observation' } }
    %w[runtime_log normal_document].each do |key|
      value[key] = File.join(@root, key + '.txt')
      File.write(value[key], 'Fixture ordinary input or successful runtime event')
    end
    value['synthesized_wav'] = File.join(@root, 'synthesis.wav')
    value['live_capture_wav'] = File.join(@root, 'capture.wav')
    wav(value['synthesized_wav'])
    wav(value['live_capture_wav'], sample: 500)
    value['output_provenance'] = 'Fixture only: normal app synthesis and separate system output capture'
    value
  end

  def test_complete_smoke_protocol_and_evidence_hashes
    evidence = MacosCandidate.validate_smoke(@build, smoke)
    assert_equal 5, evidence.size
    assert_in_delta 0.2, evidence['synthesized_wav']['duration_seconds']
    assert evidence['runtime_log']['sha256']
  end

  def test_pending_startup_error_cache_and_stale_smoke_rejected
    value = smoke
    value['steps']['startup']['status'] = 'pending'
    assert_match(/step not passed/, assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }.message)
    value = smoke
    value['startup_errors'] = ['model unavailable']
    assert_match(/Startup errors/, assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }.message)
    value = smoke
    value['profile']['existing_model_or_audio_cache'] = true
    assert_match(/Fresh isolated profile/, assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }.message)
    value = smoke
    value['bundle_sha256'] = 'stale'
    assert_match(/stale smoke/, assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }.message)
    value = smoke
    File.write(value['runtime_log'], 'Unable to load asset: assets/kokoro/model/kokoro-v1.0.onnx')
    assert_match(/runtime error/, assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }.message)
  end

  def test_invalid_silent_empty_and_reused_outputs_rejected
    value = smoke
    File.write(value['synthesized_wav'], '')
    assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }
    wav(value['synthesized_wav'], sample: 0)
    assert_match(/silent/, assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }.message)
    wav(value['synthesized_wav'])
    File.binwrite(value['live_capture_wav'], 'corrupt WAV')
    assert_match(/Invalid WAV/, assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }.message)
    value['live_capture_wav'] = value['synthesized_wav']
    assert_match(/separate/, assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }.message)
  end

  def test_tree_catches_changed_binary_and_escaping_symlink
    FileUtils.mkdir_p(@app)
    File.write(File.join(@app, 'binary'), 'one')
    first = MacosCandidate.digest(MacosCandidate.tree(@app))
    File.write(File.join(@app, 'binary'), 'two')
    refute_equal first, MacosCandidate.digest(MacosCandidate.tree(@app))
    File.symlink(@log, File.join(@app, 'outside'))
    assert_match(/escapes/, assert_raises(RuntimeError) { MacosCandidate.tree(@app) }.message)
  end

  def test_bundle_requires_runtime_binaries_before_asset_or_signature_admission
    FileUtils.mkdir_p(@app)
    with_stubs(capture: 'fixture') do
      assert_match(/Contents\/MacOS\/fixture/, assert_raises(RuntimeError) { MacosCandidate.bundle(@app, {}) }.message)
      FileUtils.mkdir_p(File.join(@app, 'Contents/MacOS'))
      File.write(File.join(@app, 'Contents/MacOS/fixture'), 'synthetic Mach-O placeholder')
      assert_match(/lacks arm64/, assert_raises(RuntimeError) { MacosCandidate.bundle(@app, {}) }.message)
    end
  end

  def test_bundle_identity_survives_staging_path_and_rejects_changed_assets
    %w[Contents/MacOS/fixture Contents/Frameworks/App.framework/App Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS].each do |relative|
      path = File.join(@app, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, 'Synthetic binary fixture; never executed')
    end
    asset_root = File.join(@app, MacosCandidate::ASSET_ROOT)
    FileUtils.mkdir_p(File.join(asset_root, 'assets'))
    FileUtils.cp(File.join(@root, 'assets/tokenizer_vocab.json'), File.join(asset_root, 'assets/tokenizer_vocab.json'))
    identities = MacosCandidate.validate_assets(@root, ['assets/tokenizer_vocab.json'])
    inspector = lambda do |*command|
      case command.first
      when '/usr/libexec/PlistBuddy' then 'fixture'
      when '/usr/bin/lipo' then 'arm64'
      when '/usr/bin/codesign' then "#{command.last}: valid on disk"
      else raise "Unexpected fixture inspection: #{command.inspect}"
      end
    end
    with_stubs(capture: inspector) do
      original = MacosCandidate.bundle(@app, identities)
      copy = File.join(@root, 'Copied.app')
      FileUtils.cp_r(@app, copy)
      assert_equal original, MacosCandidate.bundle(copy, identities)
      File.write(File.join(copy, MacosCandidate::ASSET_ROOT, 'assets/tokenizer_vocab.json'), '{"changed":2}')
      assert_match(/differ from preflight/, assert_raises(RuntimeError) { MacosCandidate.bundle(copy, identities) }.message)
    end
  end

  def test_stale_output_and_invalid_riff_size_rejected
    value = smoke
    File.utime(Time.utc(2026, 1, 1), Time.utc(2026, 1, 1), value['synthesized_wav'])
    assert_match(/Stale output/, assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }.message)
    value = smoke
    bytes = File.binread(value['synthesized_wav'])
    bytes[4, 4] = [1].pack('V')
    File.binwrite(value['synthesized_wav'], bytes)
    assert_match(/Invalid WAV/, assert_raises(RuntimeError) { MacosCandidate.validate_smoke(@build, value) }.message)
  end

  def test_source_snapshot_rejects_dirty_git_state_and_includes_empty_files
    repository = File.join(@root, 'source')
    FileUtils.mkdir_p(repository)
    MacosCandidate.capture('git', 'init', '-q', chdir: repository)
    MacosCandidate.capture('git', 'config', 'user.name', 'Candidate Fixture', chdir: repository)
    MacosCandidate.capture('git', 'config', 'user.email', 'fixture@example.invalid', chdir: repository)
    File.write(File.join(repository, 'empty'), '')
    MacosCandidate.capture('git', 'add', 'empty', chdir: repository)
    MacosCandidate.capture('git', 'commit', '-qm', 'Fixture', chdir: repository)
    identity = MacosCandidate.source(repository)
    assert_equal false, identity['dirty']
    assert_match(/\A[0-9a-f]{64}\z/, identity['tracked_files_sha256'])
    File.write(File.join(repository, 'empty'), 'dirty')
    assert_match(/Source must be clean/, assert_raises(RuntimeError) { MacosCandidate.source(repository) }.message)
  end

  def test_build_refuses_existing_app_before_running_command
    FileUtils.mkdir_p(@app)
    assert_match(/Fresh build required/, assert_raises(RuntimeError) { MacosCandidate.build(root: @root, app: @app, receipt: @build_path, command: ['never-run']) }.message)
  end

  def test_build_wrapper_records_only_success_with_unchanged_inputs
    runner = ->(_command, _root, log) { File.write(log, 'Synthetic successful build fixture') }
    with_stubs(preflight: @inputs, toolchain: @sdk, bundle: @bundle, run_build: runner) do
      value = MacosCandidate.build(root: @root, app: @app, receipt: @build_path, command: ['flutter', 'build', 'macos'])
      assert_equal @inputs, value['inputs']
      assert_equal @bundle, value['bundle']
      assert_equal @sdk, value['toolchain']
      assert_equal [@sdk['flutter_path'], 'build', 'macos'], value['command']
      assert_equal value, JSON.parse(File.read(@build_path))
    end
    File.delete(@build_path)
    File.delete(@build_path + '.build.log')
    calls = 0
    changing = ->(*) { calls += 1; calls == 1 ? @inputs : { 'source' => 'changed during build' } }
    with_stubs(preflight: changing, toolchain: @sdk, bundle: @bundle, run_build: runner) do
      assert_match(/changed during build/, assert_raises(RuntimeError) { MacosCandidate.build(root: @root, app: @app, receipt: @build_path, command: ['flutter', 'build', 'macos']) }.message)
    end
    refute File.exist?(@build_path), 'Failed provenance must never emit a success receipt'
  end

  def test_build_runner_success_failure_and_timeout_are_bounded
    success = File.join(@root, 'success.log')
    MacosCandidate.run_build([RbConfig.ruby, '-e', 'puts "fixture build"'], @root, success, timeout: 2)
    assert_match(/fixture build/, File.read(success))
    assert_match(/failed/, assert_raises(RuntimeError) { MacosCandidate.run_build([RbConfig.ruby, '-e', 'exit 7'], @root, File.join(@root, 'failure.log'), timeout: 2) }.message)
    marker = File.join(@root, 'should-not-exist')
    assert_match(/timed out/, assert_raises(RuntimeError) { MacosCandidate.run_build([RbConfig.ruby, '-e', 'sleep 0.7; File.write(ARGV[0], "late")', marker], @root, File.join(@root, 'timeout.log'), timeout: 0.1) }.message)
    sleep 0.7
    refute File.exist?(marker), 'Timed-out build must not leave its child running'
  end
end
