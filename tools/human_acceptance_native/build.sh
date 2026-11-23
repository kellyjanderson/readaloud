#!/bin/bash
set -euo pipefail

if [[ $# != 1 || $1 != *.app ]]; then
    echo "Usage: $0 OUTPUT.app" >&2
    exit 2
fi

source_dir="$(cd "$(dirname "$0")" && pwd)"
output="$1"
if [[ -e "$output" || -L "$output" ]]; then
    echo "Output already exists: $output" >&2
    exit 1
fi
parent="$(dirname "$output")"
mkdir -p "$parent"
staging="$(mktemp -d "$parent/.read-aloud-user-tests.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
bundle="$staging/Read Aloud User Tests.app"
mkdir -p "$bundle/Contents/MacOS"

xcrun swiftc -swift-version 5 -target arm64-apple-macosx12.0 -parse-as-library -O \
    "$source_dir/Session.swift" "$source_dir/RunnerModel.swift" "$source_dir/Main.swift" \
    -o "$bundle/Contents/MacOS/ReadAloudUserTests"

cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Read Aloud User Tests</string>
    <key>CFBundleExecutable</key><string>ReadAloudUserTests</string>
    <key>CFBundleIdentifier</key><string>com.kellyjanderson.readAloud.userTests</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Read Aloud User Tests</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
/usr/bin/codesign --sign - "$bundle"
mv "$bundle" "$output"
printf '%s\n' "$output"
