#!/usr/bin/env ruby
# Required preflight before handing a local macOS release to a user.
require 'open3'
require 'json'

abort 'Usage: verify_macos_release_entitlements.rb APP_BUNDLE' unless ARGV.length == 1
app = File.expand_path(ARGV.first)
log, status = Open3.capture2e('codesign', '--verify', '--deep', '--strict', app)
abort "Invalid release signature: #{log}" unless status.success?
xml, error, status = Open3.capture3('codesign', '-d', '--entitlements', ':-', app)
abort "Cannot read release entitlements: #{error}" unless status.success? && xml.include?('<plist')
json, error, status = Open3.capture3('plutil', '-convert', 'json', '-o', '-', '-', stdin_data: xml)
abort "Cannot parse entitlements: #{error}" unless status.success?
entitlements = JSON.parse(json)
%w[com.apple.security.app-sandbox com.apple.security.files.user-selected.read-write com.apple.security.network.client].each do |key|
  abort "Release is missing required entitlement: #{key}" unless entitlements[key] == true
end
helper = File.join(app, 'Contents/Resources/mlx-python/bin/python3.12')
if File.exist?(helper)
  xml, error, status = Open3.capture3('codesign', '-d', '--entitlements', ':-', helper)
  abort "Cannot inspect embedded MLX helper: #{error}" unless status.success?
  json, error, status = Open3.capture3('plutil', '-convert', 'json', '-o', '-', '-', stdin_data: xml)
  abort "Invalid MLX helper entitlements: #{error}" unless status.success?
  helper_entitlements = JSON.parse(json)
  %w[com.apple.security.app-sandbox com.apple.security.inherit].each do |key|
    abort "MLX helper is missing #{key}" unless helper_entitlements[key] == true
  end
end
puts 'PASS: valid signature, sandbox, file chooser read/write access and network client entitlements'
