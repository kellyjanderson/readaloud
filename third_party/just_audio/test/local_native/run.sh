#!/bin/bash
set -euo pipefail
package_dir=$(cd "$(dirname "$0")/../.." && pwd)
# Optional source override permits the same test to reject unpatched upstream.
source_dir=${JUST_AUDIO_SOURCE_DIR:-$package_dir}
: "${FLUTTER_FRAMEWORK_DIR:?Set FLUTTER_FRAMEWORK_DIR to the directory containing FlutterMacOS.framework}"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/just-audio-queue-test.XXXXXX")
trap 'ruby -rfileutils -e '\''FileUtils.remove_entry_secure(ARGV.fetch(0))'\'' "$test_dir"' EXIT
xcrun clang -fobjc-arc -fmodules -fmodules-cache-path="$test_dir/modules" \
  -mmacosx-version-min=10.14 -Wno-deprecated-declarations \
  -F "$FLUTTER_FRAMEWORK_DIR" \
  -framework Foundation -framework AVFoundation -framework FlutterMacOS \
  -Wl,-rpath,"$FLUTTER_FRAMEWORK_DIR" \
  "$source_dir"/darwin/just_audio/Sources/just_audio/*.m \
  "$package_dir/test/local_native/queue_append_test.m" \
  -o "$test_dir/queue_append_test"
"$test_dir/queue_append_test"
