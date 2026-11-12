#!/bin/bash
set -euo pipefail
cd /Users/k/.codex/worktrees/s7-play-position-snapshot/readaloud
export FLUTTER_FRAMEWORK_DIR=/Users/k/.codex/worktrees/reader-feedback-s8/readaloud/.readaloud-tools/flutter-3.41.5-arm64/bin/cache/artifacts/engine/darwin-x64-release/FlutterMacOS.xcframework/macos-arm64_x86_64
bash third_party/just_audio/test/local_native/run.sh > tmp/s7-play-position-snapshot/fixed-native.log 2>&1
printf 'fixed-native exit=0\n' > tmp/s7-play-position-snapshot/status.txt
mkdir -p tmp/s7-play-position-snapshot/old-source
git archive a721106 third_party/just_audio/darwin | tar -x -C tmp/s7-play-position-snapshot/old-source
set +e
READALOUD_PLAY_POSITION_SCENARIO=startup-lock JUST_AUDIO_SOURCE_DIR="$PWD/tmp/s7-play-position-snapshot/old-source/third_party/just_audio" bash third_party/just_audio/test/local_native/run.sh > tmp/s7-play-position-snapshot/old-source-negative.log 2>&1
negative_status=$?
set -e
printf 'old-source-negative exit=%s (expected=1)\n' "$negative_status" >> tmp/s7-play-position-snapshot/status.txt
test "$negative_status" -eq 1
rg -q 'FAIL: Play read AVPlayerItem.currentTime while rate activation owns the startup clock lock' tmp/s7-play-position-snapshot/old-source-negative.log
git diff --check
