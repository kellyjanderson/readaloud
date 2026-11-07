# frozen_string_literal: true

require 'json'
require 'digest'
require 'find'
require 'fileutils'
require 'open3'

# Build-time only: input is the relocated, signed standalone tree, never a venv.
# The adjacent manifest and archive become trusted resources of the signed app.
module PackagedPythonRuntime
  POLICY = 'signed-standalone-ditto-v1'
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
    manifest.slice('policy', 'runtimeId', 'python', 'packages', 'executable', 'entries')
  end

  def self.validate_resources(resources)
    IDS.to_h do |id|
      path = File.join(resources, 'python-runtimes', id + '.json')
      raise "Missing/oversized packaged runtime manifest: #{id}" unless File.file?(path) && File.size(path).between?(1, 32 * 1024 * 1024)
      manifest = JSON.parse(File.read(path))
      valid = manifest['schema'] == 1 && manifest['policy'] == POLICY && manifest['runtimeId'] == id &&
        manifest['entries'].is_a?(Array) && !manifest['entries'].empty? && manifest['entries'].size <= 100_000 &&
        manifest['signedTreeDigest'] == Digest::SHA256.hexdigest(JSON.generate(identity(manifest)))
      raise "Invalid packaged runtime identity: #{id}" unless valid
      archive = File.join(resources, 'python-runtimes', id + '.zip')
      expected = manifest.fetch('archive')
      raise "Missing/corrupt packaged runtime archive: #{id}" unless File.file?(archive) && File.size(archive) == expected['size'] && Digest::SHA256.file(archive).hexdigest == expected['sha256']
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
    manifest = { 'schema' => 1, 'policy' => POLICY, 'runtimeId' => runtime_id,
                 'python' => python, 'packages' => packages, 'executable' => executable, 'entries' => all }
    manifest['signedTreeDigest'] = Digest::SHA256.hexdigest(JSON.generate(identity(manifest)))
    FileUtils.mkdir_p(output)
    archive = File.join(output, runtime_id + '.zip')
    temporary = archive + ".#{Process.pid}.zip"
    begin
      capture('/usr/bin/ditto', '-c', '-k', '--norsrc', '--noextattr', root, temporary)
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
  abort 'Usage: package_python_runtime.rb ROOT ID EXECUTABLE OUTPUT' unless ARGV.size == 4
  root, id, executable, output = ARGV
  PackagedPythonRuntime.package(root: root, runtime_id: id, executable: executable, output: output)
end
