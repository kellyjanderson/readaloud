# frozen_string_literal: true

require_relative 'release_notices'
require 'fileutils'
require 'open3'
require 'find'

# Copies an existing app into a new review folder; never builds, signs, installs,
# notarizes, modifies the input bundle or publishes it. Retain blockers visibly.
abort 'Usage: ruby tools/package_macos_candidate.rb APP_PATH NEW_OUTPUT_DIRECTORY' unless ARGV.size == 2
abort 'macOS required' unless RUBY_PLATFORM.include?('darwin')
app, output = ARGV.map { |path| File.expand_path(path) }
abort 'Input must be an existing .app directory' unless File.directory?(app) && app.end_with?('.app')
abort 'Output must not exist' if File.exist?(output)
abort 'Output cannot be inside the input app' if output.start_with?(app + '/')
root = ReleaseNotices::ROOT
inventory = ReleaseNotices.validate
abort 'Committed NOTICES.txt is stale' unless File.read(File.join(root, 'third_party/licenses/NOTICES.txt')) == ReleaseNotices.text(inventory)
git_status, status = Open3.capture2('git', '-C', root, 'status', '--porcelain', '--untracked-files=all')
abort 'Cannot establish source state' unless status.success?
abort 'Source must be clean for candidate provenance' unless git_status.empty?
head, status = Open3.capture2('git', '-C', root, 'rev-parse', 'HEAD')
abort 'Cannot establish source revision' unless status.success?
executable, status = Open3.capture2('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleExecutable', File.join(app, 'Contents/Info.plist'))
abort 'Cannot identify app executable' unless status.success?
binary = File.join(app, 'Contents/MacOS', executable.strip)
architecture, status = Open3.capture2('/usr/bin/lipo', '-archs', binary)
abort 'App executable requires arm64' unless status.success? && architecture.split.include?('arm64')
signature, signature_status = Open3.capture2e('/usr/bin/codesign', '--verify', '--deep', '--strict', '--verbose=2', app)
signing_details, = Open3.capture2e('/usr/bin/codesign', '-d', '--verbose=4', app)
staged_app = File.join(output, File.basename(app))
FileUtils.mkdir_p(output)
begin
  system('/usr/bin/ditto', app, staged_app, exception: true)
  FileUtils.cp_r(File.join(root, 'third_party/licenses'), File.join(output, 'Open Source Notices'))
  FileUtils.cp(File.join(root, 'docs/release-compliance.md'), File.join(output, 'RELEASE-COMPLIANCE.md'))
  files = []
  Find.find(staged_app) do |path|
    next unless File.file?(path)
    files << { 'path' => path.delete_prefix(output + '/'), 'size' => File.size(path), 'sha256' => Digest::SHA256.file(path).hexdigest }
  end
  receipt = {
    'schema' => 1, 'purpose' => 'Local review candidate; NOT a cleared public release',
    'source_commit' => head.strip, 'input_app' => app,
    'source_to_app_build_provenance' => 'Not established by packaging: attach exact build command/log and source/model/SDK identities in #91',
    'main_executable_architectures' => architecture.strip,
    'signature_verification_passed' => signature_status.success?, 'signature_verification' => signature,
    'signing_details' => signing_details, 'release_blockers' => inventory.fetch('blockers'),
    'files' => files.sort_by { |file| file['path'] }
  }
  File.write(File.join(output, 'candidate.json'), JSON.pretty_generate(receipt) + "\n")
  puts "Candidate staged at #{output}; #{inventory['blockers'].size} release blockers retained. Signature verification: #{signature_status.success?}. No release clearance implied."
rescue Exception
  warn "Candidate staging failed. Partial output retained for inspection: #{output}"
  raise
end
