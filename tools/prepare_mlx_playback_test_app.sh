#!/bin/sh
# Isolate a smoke-target bundle from the user's running application/profile.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: prepare_mlx_playback_test_app.sh SOURCE_APP NEW_QA_APP' >&2; exit 2; }
[ ! -e "$2" ] || { echo 'QA destination already exists.' >&2; exit 2; }
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
qa_id=com.kellyjanderson.readAloud.mlxPlaybackTest
source_data="$HOME/Library/Containers/com.kellyjanderson.readAloud/Data"
qa_data="$HOME/Library/Containers/$qa_id/Data"
[ ! -e "$qa_data" ] && [ ! -L "$qa_data" ] || { echo 'QA data root already exists; refusing to overwrite it.' >&2; exit 2; }
# Metadata discovery is stdlib-only. A managed Python may be selected explicitly.
"${READALOUD_MLX_PYTHON:-python3}" "$project_root/tools/stage_mlx_qa_cache.py" "$source_data" "$qa_data"
cp -cR "$1" "$2"
plutil -replace CFBundleIdentifier -string "$qa_id" "$2/Contents/Info.plist"
plutil -replace CFBundleName -string 'Read Aloud Playback Test' "$2/Contents/Info.plist"
codesign --force --sign - --entitlements "$project_root/macos/Runner/Release.entitlements" "$2"
ruby "$project_root/tools/verify_macos_release_entitlements.rb" "$2"
