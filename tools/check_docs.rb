#!/usr/bin/env ruby
# Deterministic repository documentation checks; no network or Flutter required.
require 'pathname'
require 'uri'
require 'json'
require 'digest'

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)
errors = []
historical = ->(p) { p.start_with?('project/archive/') && p != 'project/archive/README.md' }
files = (Dir['*.md'] + Dir['docs/**/*.md'] + Dir['tools/**/*.md'] + Dir['project/**/*.{md,acd,plan}'] + Dir['.agents/**/*.{md,acd,plan}']).select { |p| File.file?(p) }
links_for = lambda do |path|
  # Code fences may contain example links/templates rather than real references.
  text = File.read(path).gsub(/^```.*?^```[^\n]*$/m, '').gsub(/`[^`]*`/, '')
  text.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.map do |link|
    next if link.match?(/\A(?:[a-z][a-z0-9+.-]*:|#)/i)
    target = URI::DEFAULT_PARSER.unescape(link.split('#', 2).first)
    Pathname.new(File.join(File.dirname(path), target)).cleanpath.to_s
  end.compact
end

files.reject { |p| historical.call(p) || p.include?('/disabled/') }.each do |path|
  links_for.call(path).each do |target|
    errors << "#{path}: missing local target #{target}" unless File.exist?(target)
  end
end

# These locations are retired; preserved history belongs under project/archive/.
Dir['project/{acd,planning}/**/*'].select { |p| File.file?(p) }.each do |p|
  next if p.include?('/archive/') || p.end_with?('/README.md')
  errors << "#{p}: working documents belong in GitHub, not the repository"
end
Dir['project/**/*.{acd,plan}'].each do |p|
  next if p.include?('/archive/')
  errors << "#{p}: active ACD/plan must be a GitHub issue"
end

# Published interim revisions are fixed design artifacts, not live issue mirrors.
Dir['project/interim/*/manifest.json'].each do |manifest_path|
  begin
    manifest = JSON.parse(File.read(manifest_path))
    raise 'unsupported manifest schema' unless manifest['schema_version'] == 1
    %w[package_revision publication implementation_baseline].each do |key|
      raise "missing #{key}" unless manifest[key].is_a?(String) && !manifest[key].empty?
    end
    documents = manifest.fetch('documents')
    raise 'documents must be a nonempty array' unless documents.is_a?(Array) && !documents.empty?
    names = documents.map { |entry| entry.fetch('path') }
    raise 'duplicate document path' unless names.uniq == names
    directory = File.dirname(manifest_path)
    raise 'missing package README' unless File.file?(File.join(directory, 'README.md'))
    documents.each do |entry|
      name = entry.fetch('path')
      raise "invalid document path #{name.inspect}" unless name.is_a?(String) && name.match?(/\A[A-Za-z0-9_-]+\.md\z/)
      %w[revision source].each { |key| raise "missing #{key} for #{name}" unless entry[key].is_a?(String) && !entry[key].empty? }
      %w[sha256 source_section_sha256].each { |key| raise "invalid #{key} for #{name}" unless entry[key].is_a?(String) && entry[key].match?(/\A[0-9a-f]{64}\z/) }
      path = File.join(directory, name)
      raise "missing snapshot #{name}" unless File.file?(path)
      raise "published snapshot changed: #{name}; create a new revision" unless Digest::SHA256.file(path).hexdigest == entry['sha256']
    end
    unlisted = Dir[File.join(directory, '*.md')].map { |path| File.basename(path) } - names - ['README.md']
    raise "unlisted published documents: #{unlisted.join(', ')}" unless unlisted.empty?
  rescue JSON::ParserError, KeyError, TypeError, RuntimeError => error
    errors << "#{manifest_path}: #{error.message}"
  end
end

Dir['project/specifications/*.md'].reject { |p| p.end_with?('/README.md') }.each do |spec|
  text = File.read(spec)
  architecture = links_for.call(spec).select { |p| p.start_with?('project/architecture/') && File.file?(p) }
  errors << "#{spec}: no direct architecture owner" if architecture.empty?
  child_section = text.split('## Child Specifications', 2)[1].to_s.split(/^## /, 2)[0].to_s
  next if child_section.match?(/\]\([^)]*\.md\)/)
  errors << "#{spec}: no reciprocal architecture link" unless architecture.any? { |p| links_for.call(p).include?(spec) }
end

if errors.empty?
  puts "Documentation checks passed: local targets, direct leaf ownership and versioned interim snapshots."
else
  warn errors.sort.join("\n")
  abort "Documentation checks failed: #{errors.length} error(s)."
end
