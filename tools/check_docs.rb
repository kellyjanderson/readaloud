#!/usr/bin/env ruby
# Deterministic repository documentation checks; no network or Flutter required.
require 'pathname'
require 'uri'

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)
errors = []
historical = ->(p) { p.start_with?('project/archive/', 'project/planning/archive/', 'project/acd/archive/') }
files = (Dir['*.md'] + Dir['docs/**/*.md'] + Dir['project/**/*.{md,acd,plan}'] + Dir['.agents/**/*.{md,acd,plan}']).select { |p| File.file?(p) }
links_for = lambda do |path|
  # Code fences may contain example links/templates rather than real references.
  text = File.read(path).gsub(/^```.*?^```[^\n]*$/m, '').gsub(/`[^`]*`/, '')
  text.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.map do |link|
    next if link.match?(/\A(?:[a-z][a-z0-9+.-]*:|#)/i)
    target = URI::DEFAULT_PARSER.unescape(link.split('#', 2).first)
    Pathname.new(File.join(File.dirname(path), target)).cleanpath.to_s
  end.compact
end

files.reject { |p| historical.call(p) || p.include?('/archive/') || p.include?('/disabled/') }.each do |path|
  links_for.call(path).each do |target|
    errors << "#{path}: missing local target #{target}" unless File.exist?(target)
  end
end

acds = Dir['project/acd/*.acd']
plans = Dir['project/planning/*.plan']
acds.each do |p|
  paired = "project/planning/#{File.basename(p, '.acd')}.plan"
  errors << "#{p}: missing paired plan" unless plans.include?(paired)
end
plans.each do |p|
  paired = "project/acd/#{File.basename(p, '.plan')}.acd"
  errors << "#{p}: missing paired ACD" unless acds.include?(paired)
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
  puts "Documentation checks passed: local targets, direct leaf ownership and #{acds.length} ACD/plan pair(s)."
else
  warn errors.sort.join("\n")
  abort "Documentation checks failed: #{errors.length} error(s)."
end
