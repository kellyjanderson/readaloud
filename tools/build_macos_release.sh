#!/bin/sh
# Local ad-hoc release, preserving the configured sandbox/file entitlements.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
target="${1:-lib/main.dart}"
settings="${TMPDIR:-/tmp}/readaloud-release-settings-$$.json"
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  -showBuildSettings -json > "$settings"
app_bundle=$(ruby -rjson -e 's=JSON.parse(File.read(ARGV[0])).find { |v| v["target"] == "Runner" }.fetch("buildSettings"); puts File.join(s.fetch("TARGET_BUILD_DIR"), s.fetch("WRAPPER_NAME"))' "$settings")
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  FLUTTER_TARGET="$target" build
# Always reseal after Flutter's incremental embed and the Python build phase.
# Preserve the embedded helper's own inheritance signature (no --deep signing).
codesign --force --sign - --entitlements macos/Runner/Release.entitlements "$app_bundle"
ruby tools/verify_macos_release_entitlements.rb "$app_bundle"
printf '%s\n' "$app_bundle"
