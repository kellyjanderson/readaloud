# frozen_string_literal: true

require 'json'
require 'digest'
require 'find'
require 'fileutils'
require 'open3'
require 'tmpdir'

# Build-time only: input is the relocated, signed standalone tree, never a venv.
# The adjacent manifest and archive become trusted resources of the signed app.
module PackagedPythonRuntime
  POLICY = 'bundled-native-data-view-v2'
  IDS = %w[mlx modernbooknlp].freeze
  def self.capture(*args)
    output, status = Open3.capture2e(*args)
    raise "Runtime command failed: #{args.inspect}\n#{output}" unless status.success?
    output.strip
  end

  def self.entries(root)
    root = File.realpath(root)
    values = []
    Find.find(root) do |path|
      next if path == root
      relative = path.delete_prefix(root + '/')
      raise "Unsafe runtime path: #{relative}" if relative.split('/').any? { |p| p.empty? || %w[. ..].include?(p) } || relative.include?('\\') || relative == '.complete.json'
      stat = File.lstat(path)
      raise "Special runtime mode is forbidden: #{relative}" unless (stat.mode & 0o7000).zero?
      value = { 'path' => relative, 'type' => nil, 'mode' => stat.mode & 0o777 }
      if stat.symlink?
        target = File.readlink(path)
        raise "Runtime link escapes or is absolute: #{relative}" if target.start_with?('/') || target.include?('\\') || !File.realpath(path).start_with?(root + '/')
        value.merge!('type' => 'link', 'target' => target)
      elsif stat.directory?
        value['type'] = 'directory'
      elsif stat.file?
        value.merge!('type' => 'file', 'size' => stat.size, 'sha256' => Digest::SHA256.file(path).hexdigest)
      else
        raise "Unsupported runtime member: #{relative}"
      end
      values << value
    end
    values.sort_by { |entry| entry.fetch('path') }
  end

  def self.identity(manifest)
    manifest.slice('policy', 'runtimeId', 'python', 'packages', 'executable', 'nativeRoot', 'entries')
  end

  MACHO_MAGICS = %w[feedface cefaedfe feedfacf cffaedfe cafebabe bebafeca cafebabf bfbafeca].freeze
  def self.macho?(path)
    header = File.binread(path, 4)
    header != nil && MACHO_MAGICS.include?(header.unpack1('H*'))
  end

  def self.native?(root, entry, executable)
    return false unless entry['type'] == 'file'
    path = File.join(root, entry.fetch('path'))
    code = macho?(path)
    if (entry['path'] == executable || entry['path'].match?(/(?:\.so(?:\.\d+)*|\.dylib)\z/)) && !code
      raise "Expected Mach-O native code: #{entry['path']}"
    end
    code || entry['path'].end_with?('.metallib')
  end

  def self.verify_native(path)
    return unless macho?(path) # Metal resources are bound as adjacent native data.
    raise "Native code must be arm64-only: #{path}" unless capture('/usr/bin/lipo', '-archs', path) == 'arm64'
    capture('/usr/bin/codesign', '--verify', '--strict', path)
  end

  def self.sign_native(root, identity, entitlements, executable)
    entries(root).each do |entry|
      next unless native?(root, entry, executable)
      path = File.join(root, entry.fetch('path'))
      next unless macho?(path)
      args = ['/usr/bin/codesign', '--force', '--sign', identity]
      args += ['--entitlements', entitlements] if entry['path'] == executable
      capture(*args, path)
    end
  end

  # Only the build-owned relocated tree may be passed here. Bytecode is a cache
  # when its exact Python source is present; retain sourceless modules. Omitting
  # these duplicates reduces first-launch resource verification without removing
  # runtime features, dependencies, signatures or licenses.
  def self.omit_redundant_bytecode(root)
    # Reject escaping links before globbing through any cache directory.
    entries(root)
    Dir.glob(File.join(root, '**/__pycache__/*.pyc')).each do |path|
      name = File.basename(path)[/\A(.+)\.cpython-\d+(?:\.opt-\d+)?\.pyc\z/, 1]
      next unless name && File.file?(File.join(File.dirname(File.dirname(path)), name + '.py'))
      File.unlink(path)
    end
    Dir.glob(File.join(root, '**/__pycache__')).each do |directory|
      Dir.rmdir(directory) if !File.symlink?(directory) && File.directory?(directory) && Dir.empty?(directory)
    end
  end

  def self.validate_resources(resources)
    IDS.to_h do |id|
      path = File.join(resources, 'python-runtimes', id + '.json')
      raise "Missing/oversized packaged runtime manifest: #{id}" unless File.file?(path) && File.size(path).between?(1, 32 * 1024 * 1024)
      manifest = JSON.parse(File.read(path))
      valid = manifest['schema'] == 2 && manifest['policy'] == POLICY && manifest['runtimeId'] == id &&
        manifest['nativeRoot'] == "python-runtimes/#{id}-native" &&
        manifest['entries'].is_a?(Array) && !manifest['entries'].empty? && manifest['entries'].size <= 100_000 &&
        manifest['signedTreeDigest'] == Digest::SHA256.hexdigest(JSON.generate(identity(manifest)))
      raise "Invalid packaged runtime identity: #{id}" unless valid
      archive = File.join(resources, 'python-runtimes', id + '.zip')
      expected = manifest.fetch('archive')
      raise "Missing/corrupt packaged runtime archive: #{id}" unless File.file?(archive) && File.size(archive) == expected['size'] && Digest::SHA256.file(archive).hexdigest == expected['sha256']
      native_root = File.join(resources, manifest.fetch('nativeRoot'))
      raise "Linked native root: #{id}" if File.symlink?(native_root)
      natives = manifest.fetch('entries').select { |entry| entry['type'] == 'bundledNative' }
      expected_paths = natives.map { |entry| entry.fetch('path') }.sort
      actual = entries(native_root).reject { |entry| entry['type'] == 'directory' }
      raise "Undeclared/missing native member: #{id}" unless actual.map { |entry| entry['path'] } == expected_paths
      natives.each do |entry|
        path = File.join(resources, entry.fetch('bundlePath'))
        raise "Invalid native binding: #{id}" unless entry['bundlePath'] == "#{manifest['nativeRoot']}/#{entry['path']}" &&
          !File.symlink?(path) && File.file?(path) && File.realpath(path).start_with?(File.realpath(native_root) + '/') &&
          File.size(path) == entry['size'] && File.stat(path).mode & 0o777 == entry['mode'] && Digest::SHA256.file(path).hexdigest == entry['sha256']
        verify_native(path)
      end
      raise "Interpreter is not bundled native: #{id}" unless natives.any? { |entry| entry['path'] == manifest['executable'] && macho?(File.join(native_root, entry['path'])) }
      expanded = File.join(resources, id == 'mlx' ? 'mlx-python' : 'modernbooknlp-python')
      raise "Obsolete expanded runtime remains: #{id}" if File.exist?(expanded) || File.symlink?(expanded)
      [id, { 'signed_tree_digest' => manifest['signedTreeDigest'], 'python' => manifest['python'], 'packages' => manifest['packages'], 'archive' => expected }]
    end
  end

  def self.package(root:, runtime_id:, executable:, output:)
    raise 'Unknown runtime' unless IDS.include?(runtime_id)
    root = File.realpath(root)
    all = entries(root)
    raise 'Missing executable' unless File.executable?(File.join(root, executable))
    # Sandboxed-inheritance executables cannot be run from an unsandboxed build
    # shell after signing. Read the exact standalone distribution's version header.
    header = Dir.glob(File.join(root, 'include/python*/patchlevel.h')).first
    version = header && File.read(header)[/^#define\s+PY_VERSION\s+"([^"]+)"/, 1]
    raise 'Missing exact standalone Python version header' unless version
    python = 'Python ' + version
    packages = Dir.glob(File.join(root, 'lib/python*/site-packages/*.dist-info/METADATA')).sort.map do |path|
      text = File.read(path)
      { 'name' => text[/^Name: (.+)$/, 1], 'version' => text[/^Version: (.+)$/, 1] }.tap do |item|
        raise "Invalid package metadata: #{path}" if item.values.any?(&:nil?)
      end
    end.sort_by { |item| [item['name'], item['version']] }
    native_relative = "python-runtimes/#{runtime_id}-native"
    native_entries = all.select { |entry| native?(root, entry, executable) }
    native_entries.each { |entry| verify_native(File.join(root, entry.fetch('path'))) }
    raise 'Interpreter must be a thin arm64 Mach-O executable' unless capture('/usr/bin/file', '-b', File.join(root, executable)) == 'Mach-O 64-bit executable arm64'
    logical = all.map do |entry|
      native_entries.include?(entry) ? entry.merge('type' => 'bundledNative', 'bundlePath' => "#{native_relative}/#{entry['path']}") : entry
    end
    manifest = { 'schema' => 2, 'policy' => POLICY, 'runtimeId' => runtime_id,
                 'python' => python, 'packages' => packages, 'executable' => executable, 'nativeRoot' => native_relative, 'entries' => logical }
    manifest['signedTreeDigest'] = Digest::SHA256.hexdigest(JSON.generate(identity(manifest)))
    FileUtils.mkdir_p(output)
    archive = File.join(output, runtime_id + '.zip')
    temporary = archive + ".#{Process.pid}.zip"
    begin
      native_root = File.join(output, runtime_id + '-native')
      # These are build-owned outputs, never source or published runtime views.
      FileUtils.rm_rf(native_root)
      FileUtils.mkdir_p(native_root)
      Dir.mktmpdir('readaloud-runtime-data-') do |data|
        capture('/usr/bin/ditto', root, data)
        native_entries.each do |entry|
          relative = entry.fetch('path')
          target = File.join(native_root, relative)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.copy_file(File.join(root, relative), target, true)
          File.unlink(File.join(data, relative))
        end
        capture('/usr/bin/ditto', '-c', '-k', '--zlibCompressionLevel', '9', '--norsrc', '--noextattr', data, temporary)
      end
      raise 'Signed input changed during packaging' unless entries(root) == all
      manifest['archive'] = { 'size' => File.size(temporary), 'sha256' => Digest::SHA256.file(temporary).hexdigest }
      File.rename(temporary, archive)
      File.write(File.join(output, runtime_id + '.json'), JSON.generate(manifest))
    ensure
      FileUtils.rm_f(temporary)
    end
    manifest
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.first == '--sign-native'
    ARGV.shift
    abort 'Usage: --sign-native ROOT IDENTITY ENTITLEMENTS EXECUTABLE' unless ARGV.size == 4
    PackagedPythonRuntime.sign_native(*ARGV)
    exit
  end
  omit_bytecode = ARGV.first == '--omit-redundant-bytecode'
  ARGV.shift if omit_bytecode
  abort 'Usage: package_python_runtime.rb [--omit-redundant-bytecode] ROOT ID EXECUTABLE OUTPUT' unless ARGV.size == 4
  root, id, executable, output = ARGV
  PackagedPythonRuntime.omit_redundant_bytecode(root) if omit_bytecode
  PackagedPythonRuntime.package(root: root, runtime_id: id, executable: executable, output: output)
end
