# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'find'
require 'json'
require 'open3'
require 'tmpdir'

# Project-owned toolchain, independent of archived SDKs and global pub caches.
class FlutterBootstrap
  VERSION = '3.41.5'
  REVISION = '2c9eb20739dfec95e2c74bd3dfa4601b0a8a36aa'
  BASE_URL = 'https://storage.googleapis.com/flutter_infra_release/releases/stable/macos'
  # Pinned from the official releases/releases_macos.json manifest.
  ARCHIVES = {
    'arm64' => ['flutter_macos_arm64_3.41.5-stable.zip', '90d8e7d7e6c2c27ce8634a6c99eb8a218ea63ba29781b61eb9db72c62d027546'],
    'x86_64' => ['flutter_macos_3.41.5-stable.zip', 'c2f9d18e633704d58ac45f87961ead20437570476d052a7e22bcb9d985ddcecc']
  }.freeze

  def initialize(root, arch: nil)
    @root = File.expand_path(root)
    @arch = arch || native_arch
    @archive, @digest = ARCHIVES.fetch(@arch)
    @tools = File.join(@root, '.readaloud-tools')
    @sdk = File.join(@tools, "flutter-#{VERSION}-#{@arch}")
  end

  def native_arch
    raise 'Automatic Flutter setup currently supports macOS.' unless RUBY_PLATFORM.include?('darwin')
    # Prefer the hardware architecture even from a Rosetta terminal.
    arm, status = Open3.capture2('/usr/sbin/sysctl', '-n', 'hw.optional.arm64')
    return 'arm64' if status.success? && arm.strip == '1'
    'x86_64'
  end

  def compatible?(sdk)
    receipt = JSON.parse(File.read(File.join(sdk, '.readaloud-sdk.json')))
    receipt == { 'version' => VERSION, 'arch' => @arch, 'sha256' => @digest } &&
      File.executable?(File.join(sdk, 'bin/flutter')) && native_dart?(sdk) && pinned_revision?(sdk)
  rescue Errno::ENOENT, JSON::ParserError
    false
  end

  def native_dart?(sdk)
    dart = File.join(sdk, 'bin/cache/dart-sdk/bin/dart')
    return false unless File.executable?(dart)
    output, status = Open3.capture2('file', '-b', dart)
    status.success? && output.include?("Mach-O 64-bit executable #{@arch}")
  end

  def pinned_revision?(sdk)
    revision, status = Open3.capture2('git', '-C', sdk, 'rev-parse', 'HEAD')
    status.success? && revision.strip == REVISION
  end

  def writable_tree?(root)
    return false unless File.directory?(root)
    Find.find(root) do |path|
      next if File.symlink?(path)
      return false unless File.writable?(path) && (File.stat(path).mode & 0200).positive?
    end
    true
  rescue Errno::ENOENT
    false # Another Flutter invocation may still be populating its cache.
  end

  def make_writable(root)
    Find.find(root) do |path|
      next if File.symlink?(path)
      mode = File.stat(path).mode
      File.chmod(mode | (File.directory?(path) ? 0700 : 0600), path)
    end
  end

  def download(destination)
    warn "Downloading Flutter #{VERSION} for #{@arch} (first launch)…"
    run!('curl', '--fail', '--location', '--retry', '3', '--connect-timeout', '30',
         '--output', destination, "#{BASE_URL}/#{@archive}")
  end

  def run!(*command)
    raise "Command failed: #{command.first}" unless system(*command)
  end

  def install
    Dir.mktmpdir('.install-', @tools) do |stage|
      archive = File.join(stage, 'sdk.zip')
      download(archive)
      raise 'Flutter archive checksum mismatch; existing SDK was preserved.' unless Digest::SHA256.file(archive).hexdigest == @digest
      run!('ditto', '-x', '-k', archive, stage)
      extracted = File.join(stage, 'flutter')
      verify_extracted(extracted)
      make_writable(extracted)
      File.write(File.join(extracted, '.readaloud-sdk.json'), JSON.generate(
        'version' => VERSION, 'arch' => @arch, 'sha256' => @digest
      ))
      # Publish only a completely verified tree. Keep any old tree recoverable.
      if File.exist?(@sdk) || File.symlink?(@sdk)
        File.rename(@sdk, "#{@sdk}.preserved-#{Process.pid}-#{Time.now.to_i}")
      end
      File.rename(extracted, @sdk)
    end
  end

  def verify_extracted(sdk)
    raise 'Downloaded Flutter SDK has the wrong architecture.' unless native_dart?(sdk)
    raise 'Downloaded Flutter SDK has the wrong revision.' unless pinned_revision?(sdk)
  end

  def with_sdk
    FileUtils.mkdir_p(@tools)
    File.chmod(File.stat(@tools).mode | 0700, @tools)
    pub = File.join(@tools, 'pub-cache')
    # Shared lease lasts through Flutter execution. Repair/install requires an
    # exclusive lease, so another invocation cannot replace a running SDK.
    lock_path = File.join(@tools, 'bootstrap.lock')
    File.chmod(File.stat(lock_path).mode | 0600, lock_path) if File.exist?(lock_path)
    File.open(lock_path, File::RDWR | File::CREAT, 0600) do |lock|
      lock.flock(File::LOCK_SH)
      unless compatible?(@sdk) && writable_tree?(@sdk) && writable_tree?(pub)
        lock.flock(File::LOCK_UN)
        warn 'Preparing the project Flutter toolchain…'
        lock.flock(File::LOCK_EX)
        install unless compatible?(@sdk)
        make_writable(@sdk) unless writable_tree?(@sdk)
        FileUtils.mkdir_p(pub)
        make_writable(pub) unless writable_tree?(pub)
        lock.flock(File::LOCK_SH)
      end
      yield File.join(@sdk, 'bin/flutter'), pub, lock
    end
  end

  def launch(args)
    args = ['run', '-d', 'macos'] if args.empty?
    args = ['run', *args] if ['-d', '--device-id'].include?(args.first)
    with_sdk do |flutter, pub, lock|
      lock.close_on_exec = false
      Dir.chdir(@root)
      exec({ 'PUB_CACHE' => pub }, flutter, *args, close_others: false)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    FlutterBootstrap.new(File.expand_path('..', __dir__)).launch(ARGV)
  rescue StandardError => error
    warn "Read Aloud toolchain setup failed: #{error.message}"
    warn 'Check network access and write access to .readaloud-tools, then retry tools/flutter.'
    exit 1
  end
end
