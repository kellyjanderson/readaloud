#!/bin/sh
# Isolate a smoke-target bundle from the user's running application/profile.
set -eu
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo 'Usage: prepare_mlx_playback_test_app.sh SOURCE_APP NEW_QA_APP [QA_BUNDLE_ID]' >&2; exit 2; }
[ ! -e "$2" ] && [ ! -L "$2" ] || { echo 'QA destination already exists.' >&2; exit 2; }
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
qa_prefix=com.kellyjanderson.readAloud.mlxPlaybackTest
qa_id=${3:-$qa_prefix}
# Repeat runs can use e.g. "$qa_prefix.run-20261113-02". Keep prior QA data;
# callers must also target this fresh identity in their smoke runner.
case "$qa_id" in
  "$qa_prefix"|"$qa_prefix".*) ;;
  *) echo "QA bundle ID must be $qa_prefix or a suffixed identity." >&2; exit 2 ;;
esac
case "$qa_id" in
  *[!A-Za-z0-9.-]*|*..*|*.) echo 'Invalid QA bundle ID.' >&2; exit 2 ;;
esac
[ -f "$1/Contents/Info.plist" ] || { echo 'Source app must contain Contents/Info.plist.' >&2; exit 2; }
source_data="$HOME/Library/Containers/com.kellyjanderson.readAloud/Data"
qa_data="$HOME/Library/Containers/$qa_id/Data"
[ ! -e "$qa_data" ] && [ ! -L "$qa_data" ] || { echo "QA data root already exists; pass a fresh suffixed QA_BUNDLE_ID as the third argument. Existing data is preserved." >&2; exit 2; }
# Metadata discovery is stdlib-only. A managed Python may be selected explicitly.
"${READALOUD_MLX_PYTHON:-python3}" "$project_root/tools/stage_mlx_qa_cache.py" "$source_data" "$qa_data"
cp -cR "$1" "$2"
plutil -replace CFBundleIdentifier -string "$qa_id" "$2/Contents/Info.plist"
plutil -replace CFBundleName -string 'Read Aloud Playback Test' "$2/Contents/Info.plist"
codesign --force --sign - --entitlements "$project_root/macos/Runner/Release.entitlements" "$2"
ruby "$project_root/tools/verify_macos_release_entitlements.rb" "$2"
