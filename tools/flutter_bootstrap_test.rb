# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'flutter_bootstrap'

class FixtureBootstrap < FlutterBootstrap
  def initialize(root, archive)
    super(root, arch: 'arm64')
    @fixture_archive = archive
    @digest = Digest::SHA256.file(archive).hexdigest
  end

  def download(destination)
    File.open(File.join(@root, 'downloads'), 'a') { |f| f.puts Process.pid }
    FileUtils.cp(@fixture_archive, destination)
  end

  # Network/CPU fixture substitutes only the archive and native SDK identity.
  # Checksum, extraction, atomic publication, locks and permissions are real.
  def native_dart?(sdk)
    File.read(File.join(sdk, 'bin/cache/dart-sdk/bin/dart')) == 'arm64'
  rescue Errno::ENOENT
    false
  end

  def pinned_revision?(_sdk)
    true
  end
end

class FlutterBootstrapTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('flutter-bootstrap-test-')
    source = File.join(@root, 'fixture/flutter')
    FileUtils.mkdir_p(File.join(source, 'bin/cache/dart-sdk/bin'))
    File.write(File.join(source, 'bin/cache/dart-sdk/bin/dart'), 'arm64')
    File.write(File.join(source, 'bin/flutter'), "#!/bin/sh\nexit 0\n")
    File.chmod(0755, File.join(source, 'bin/flutter'))
    File.write(File.join(source, 'bin/cache/engine.stamp'), 'engine')
    @archive = File.join(@root, 'fixture.zip')
    raise 'fixture archive failed' unless system('ditto', '-c', '-k', '--keepParent', source, @archive)
    @bootstrap = FixtureBootstrap.new(@root, @archive)
    @sdk = File.join(@root, '.readaloud-tools/flutter-3.41.5-arm64')
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_empty_checkout_bootstraps_and_reuses_without_downloading_again
    2.times { @bootstrap.with_sdk { |bin, pub, _| assert File.executable?(bin); assert Dir.exist?(pub) } }
    assert_equal 1, File.readlines(File.join(@root, 'downloads')).length
    assert_empty Dir.glob(File.join(@root, '.readaloud-tools/.install-*'))
  end

  def test_readonly_sdk_and_pub_cache_recover_without_touching_legacy_sdk
    @bootstrap.with_sdk { |_, _, _| }
    stamp = File.join(@sdk, 'bin/cache/engine.stamp')
    pub_entry = File.join(@root, '.readaloud-tools/pub-cache/package')
    File.write(pub_entry, 'package')
    legacy = File.join(@root, '.flutter-sdk')
    FileUtils.mkdir_p(legacy)
    File.write(File.join(legacy, 'untouched'), 'old SDK')
    [stamp, pub_entry, File.join(legacy, 'untouched')].each { |p| File.chmod(0444, p) }
    File.chmod(0444, File.join(@root, '.readaloud-tools/bootstrap.lock'))
    File.chmod(0555, File.join(@root, '.readaloud-tools'))
    @bootstrap.with_sdk { |_, _, _| }
    assert_equal 0200, File.stat(stamp).mode & 0200
    assert_equal 0200, File.stat(pub_entry).mode & 0200
    assert_equal 0, File.stat(File.join(legacy, 'untouched')).mode & 0200
    assert_equal 1, File.readlines(File.join(@root, 'downloads')).length
  end

  def test_bad_checksum_never_publishes_or_discards_previous_tree
    FileUtils.mkdir_p(@sdk)
    File.write(File.join(@sdk, 'prior'), 'preserve')
    @bootstrap.instance_variable_set(:@digest, '0' * 64)
    assert_raises(RuntimeError) { @bootstrap.with_sdk { flunk } }
    assert_equal 'preserve', File.read(File.join(@sdk, 'prior'))
    refute File.exist?(File.join(@sdk, '.readaloud-sdk.json'))
    assert_empty Dir.glob(File.join(@root, '.readaloud-tools/.install-*'))
  end

  def test_partial_or_wrong_architecture_tree_is_preserved_and_replaced
    @bootstrap.with_sdk { |_, _, _| }
    File.write(File.join(@sdk, 'bin/cache/dart-sdk/bin/dart'), 'intel')
    @bootstrap.with_sdk { |_, _, _| }
    assert_equal 'arm64', File.read(File.join(@sdk, 'bin/cache/dart-sdk/bin/dart'))
    old = Dir.glob("#{@sdk}.preserved-*").fetch(0)
    assert_equal 'intel', File.read(File.join(old, 'bin/cache/dart-sdk/bin/dart'))
  end

  def test_concurrent_cold_launches_publish_one_complete_install
    pids = 3.times.map do
      fork do
        @bootstrap.with_sdk { |bin, _, _| exit! File.executable?(bin) ? 0 : 1 }
      end
    end
    pids.each { |pid| assert Process.wait2(pid).last.success? }
    assert_equal 1, File.readlines(File.join(@root, 'downloads')).length
  end

  def test_process_death_releases_lease_for_next_launch
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      @bootstrap.with_sdk do |_, _, _|
        writer.write('ready')
        writer.close
        sleep 30
      end
    end
    writer.close
    assert_equal 'ready', reader.read(5)
    Process.kill('KILL', pid)
    Process.wait(pid)
    reader.close
    @bootstrap.with_sdk { |bin, _, _| assert File.executable?(bin) }
  end

  def test_launch_shorthand_uses_project_cache_and_preserves_exit_status
    @bootstrap.with_sdk do |bin, _, _|
      File.write(bin, "#!/bin/sh\nprintf '%s\\n' \"$PUB_CACHE\" \"$PWD\" \"$@\"\nexit 7\n")
    end
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      STDOUT.reopen(writer)
      writer.close
      @bootstrap.launch(['-d', 'macos'])
    end
    writer.close
    output = reader.read.lines.map(&:chomp)
    reader.close
    assert_equal 7, Process.wait2(pid).last.exitstatus
    assert_equal [File.join(@root, '.readaloud-tools/pub-cache'), File.realpath(@root),
                  'run', '-d', 'macos'], output
  end
end
