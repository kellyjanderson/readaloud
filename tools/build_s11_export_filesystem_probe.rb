#!/usr/bin/env ruby
# Builds/signs, never launches, a model-free native SavePanel differential.
require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'

abort 'Usage: NEW_APP_BUNDLE PRIOR_FISH_WAV PRIOR_JSON' unless ARGV.length == 3
app, wav, json = ARGV.map { |path| File.expand_path(path) }
abort 'Preserve existing app or missing fixtures' if File.exist?(app) || !File.file?(wav) || !File.file?(json)
abort 'Fixture must be RIFF/WAVE' unless File.binread(wav, 12).then { |bytes| bytes[0, 4] == 'RIFF' && bytes[8, 4] == 'WAVE' }
JSON.parse(File.read(json))
root = File.expand_path('..', __dir__)
frozen = File.read(File.join(__dir__, 'fixtures/audio_export_pair_baseline29.swift'))
baseline = frozen[/^\/\/ Baseline origin commit: ([0-9a-f]{40})$/, 1]
native_sha = frozen[/^\/\/ Original AppDelegate SHA256: ([0-9a-f]{64})$/, 1]
expected_helper_sha = frozen[/^\/\/ Helper body SHA256: ([0-9a-f]{64})$/, 1]
marker = 'final class AudioExportPairPublication {'
abort 'Missing/ambiguous frozen helper' unless baseline && native_sha && expected_helper_sha && frozen.split(marker, -1).length == 2
helper = marker + frozen.split(marker, 2).last
abort 'Frozen helper hash mismatch' unless Digest::SHA256.hexdigest(helper) == expected_helper_sha
harness = File.join(__dir__, 's11_export_filesystem_probe.swift')
source_commit, status = Open3.capture2('git', '-C', root, 'rev-parse', 'HEAD')
abort 'Cannot identify source' unless status.success?
plist_json, status = Open3.capture2('/usr/bin/plutil', '-convert', 'json', '-o', '-', File.join(root, 'macos/Runner/Info.plist'))
abort 'Cannot load production document declarations' unless status.success?
plist = JSON.parse(plist_json)
identifier = 'com.kellyjanderson.readAloud.exportFilesystemProbe.s11-20261116'
plist.merge!('CFBundleIdentifier' => identifier, 'CFBundleExecutable' => 's11_export_probe',
  'CFBundleName' => 'S11 Export Filesystem Probe', 'CFBundleDisplayName' => 'S11 Export Filesystem Probe',
  'CFBundleShortVersionString' => '1.0', 'CFBundleVersion' => '1',
  'CFBundleDevelopmentRegion' => 'en', 'CFBundlePackageType' => 'APPL',
  'NSPrincipalClass' => 'NSApplication', 'LSMinimumSystemVersion' => '14.0',
  'NSHumanReadableCopyright' => 'Local diagnostic only')
%w[NSMainNibFile FLTEnableMergedPlatformUIThread CFBundleIconFile].each { |key| plist.delete(key) }
resources = File.join(app, 'Contents/Resources')
executables = File.join(app, 'Contents/MacOS')
FileUtils.mkdir_p([resources, executables])
File.write(File.join(app, 'Contents/Info.plist'), JSON.generate(plist))
abort 'Cannot encode app plist' unless system('/usr/bin/plutil', '-convert', 'xml1', File.join(app, 'Contents/Info.plist'))
[[wav, 'fixture.wav'], [json, 'fixture.json']].each do |source, name|
  target = File.join(resources, name)
  FileUtils.cp(source, target)
  abort 'Copied fixture changed' unless Digest::SHA256.file(source).hexdigest == Digest::SHA256.file(target).hexdigest
end
manifest = {schema: 'readaloud-export-filesystem-probe-v2', diagnosticOnly: true,
  sourceCommit: source_commit.strip, baselineHelperCommit: baseline,
  baselineNativeSourceSHA256: native_sha,
  baselineHelperSHA256: Digest::SHA256.hexdigest(helper),
  harnessSHA256: Digest::SHA256.file(harness).hexdigest,
  fixtureWavSHA256: Digest::SHA256.file(wav).hexdigest,
  fixtureJsonSHA256: Digest::SHA256.file(json).hexdigest,
  fixtureMetadataCopiedUnmodified: true,
  modes: %w[baseline29 computed-urls fresh-presenter direct-url nested-related two-phase move-notification],
  coordinationWaitDeadlineSeconds: 10,
  coordinationWaitDeadlineModes: %w[nested-related two-phase move-notification],
  deadlineScope: 'Cooperative cancellation while waiting, before accessor mutation; running filesystem I/O must drain',
  knownSourceRefusal: {'nested-related' => 'Inner writer waits for outer pair claim; source check requires timed cancellation and rollback'},
  scope: 'Filesystem publication only; no playback, model inference or acoustic acceptance',
  bundleIdentifier: identifier}
manifest[:variantIdentities] = manifest[:modes].to_h do |mode|
  [mode, Digest::SHA256.hexdigest([manifest[:baselineHelperSHA256], manifest[:harnessSHA256], mode].join("\0"))]
end
manifest[:variantIdentityDefinition] = 'SHA256(helper SHA256, NUL, harness SHA256, NUL, mode)'
File.write(File.join(resources, 'manifest.json'), JSON.pretty_generate(manifest))
Dir.mktmpdir('s11-export-native-build-') do |directory|
  helper_path = File.join(directory, 'ProductionHelper.swift')
  File.write(helper_path, "import Foundation\nimport Darwin\n#{helper}")
  executable = File.join(executables, 's11_export_probe')
  abort 'Swift compile failed' unless system('/usr/bin/xcrun', 'swiftc', '-O', '-parse-as-library',
    '-target', 'arm64-apple-macos14.0', helper_path, harness, '-o', executable)
end
entitlements = File.join(root, 'macos/Runner/Release.entitlements')
abort 'Signing failed' unless system('/usr/bin/codesign', '--force', '--sign', '-', '--options', 'runtime',
  '--entitlements', entitlements, app)
abort 'Signature verification failed' unless system('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
puts JSON.pretty_generate(manifest.merge(app: app,
  executableSHA256: Digest::SHA256.file(File.join(executables, 's11_export_probe')).hexdigest,
  launch: 'Root only: open -W -n -a APP --stdout LOG --stderr LOG --args MODE NEW_OUTPUT_INSIDE_DATA',
  cleanup: 'Root CUA Cmd-Q; observe normalQuitDrained and verify actual PID exit'))
