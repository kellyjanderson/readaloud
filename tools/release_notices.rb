# frozen_string_literal: true

require 'json'
require 'yaml'
require 'digest'

# Offline inventory integrity, not a legal clearance decision. Never fetches or
# upgrades dependencies. The reviewed upstream texts remain ordinary Git files.
module ReleaseNotices
  ROOT = File.expand_path('..', __dir__)

  def self.validate(root = ROOT)
    directory = File.join(root, 'third_party/licenses')
    inventory = JSON.parse(File.read(File.join(directory, 'inventory.json')))
    raise 'Unsupported notice schema' unless inventory['schema'] == 1
    inventory.fetch('lockfiles').each do |path, digest|
      raise "Lockfile changed: #{path}; reconcile #55" unless Digest::SHA256.file(File.join(root, path)).hexdigest == digest
    end
    packages = YAML.load_file(File.join(root, 'pubspec.lock')).fetch('packages')
    expected = packages.reject { |_, package| package['source'] == 'sdk' }
    actual = inventory.fetch('packages').select { |item| item.fetch('id').start_with?('dart:') }
    raise 'Dart dependency inventory differs from lockfile' unless actual.map { |item| item['id'].delete_prefix('dart:') }.uniq.sort == expected.keys.sort
    actual.each do |item|
      package = expected.fetch(item['id'].delete_prefix('dart:'))
      raise "Dependency identity changed: #{item['id']}" unless item['version'] == package['version'] && item['package_source'] == package['source'] && item['archive_sha256'] == package.dig('description', 'sha256')
    end
    inventory.fetch('packages').each do |item|
      relative = item.fetch('notice')
      path = File.expand_path(relative, directory)
      raise "Unsafe notice path: #{relative}" unless path.start_with?(directory + '/')
      raise "Notice changed: #{relative}" unless File.size(path).positive? && Digest::SHA256.file(path).hexdigest == item.fetch('sha256')
    end
    asset_paths = Dir.glob(File.join(root, 'assets/**/*')).select { |path| File.file?(path) }.map { |path| path.delete_prefix(root + '/') }.sort
    # The ignored model is intentionally supplied for a candidate, not added to
    # this source snapshot. Candidate tooling records its actual identity.
    asset_paths.reject! { |path| path.end_with?('.onnx') }
    recorded = inventory.fetch('assets')
    raise 'Bundled asset set changed; reconcile #55' unless recorded.map { |item| item['path'] }.sort == asset_paths
    recorded.each do |item|
      raise "Asset changed: #{item['path']}" unless Digest::SHA256.file(File.join(root, item.fetch('path'))).hexdigest == item.fetch('sha256')
    end
    inventory
  end

  def self.text(inventory, root = ROOT)
    header = "READ ALOUD — THIRD-PARTY NOTICES\n\nConservative dependency superset, including development and other-platform packages.\nThese grants apply to their named components. They do not license Read Aloud itself.\nNative/asset coverage is incomplete; see inventory.json and docs/release-compliance.md.\n\n"
    header + inventory.fetch('packages').map do |item|
      path = File.join(root, 'third_party/licenses', item.fetch('notice'))
      body = File.read(path, encoding: 'UTF-8').scrub.lines.map(&:rstrip).join("\n")
      ["=" * 72, "#{item.fetch('id')} #{item['version']}".rstrip, "Source: #{item.fetch('source')}", item['qualification'], '', body].compact.join("\n")
    end.join("\n\n").rstrip + "\n"
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: ruby tools/release_notices.rb [--write]' unless ARGV.empty? || ARGV == ['--write']
  inventory = ReleaseNotices.validate
  output = File.join(ReleaseNotices::ROOT, 'third_party/licenses/NOTICES.txt')
  expected = ReleaseNotices.text(inventory)
  if ARGV == ['--write']
    File.write(output, expected)
  else
    abort 'NOTICES.txt is stale; run ruby tools/release_notices.rb --write' unless File.read(output) == expected
  end
  puts "Notice integrity passed: #{inventory['packages'].size} texts; #{inventory['assets'].size} assets; #{inventory['blockers'].size} release blockers remain."
end
