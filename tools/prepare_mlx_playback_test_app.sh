#!/bin/sh
# Isolate a smoke-target bundle from the user's running application/profile.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: prepare_mlx_playback_test_app.sh SOURCE_APP NEW_QA_APP' >&2; exit 2; }
[ ! -e "$2" ] || { echo 'QA destination already exists.' >&2; exit 2; }
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
qa_id=com.kellyjanderson.readAloud.mlxPlaybackTest
source_data="$HOME/Library/Containers/com.kellyjanderson.readAloud/Data"
qa_data="$HOME/Library/Containers/$qa_id/Data"
model_suffix='Library/Application Support/read_aloud/mlx-tts'
cp -cR "$1" "$2"
plutil -replace CFBundleIdentifier -string "$qa_id" "$2/Contents/Info.plist"
plutil -replace CFBundleName -string 'Read Aloud Playback Test' "$2/Contents/Info.plist"
mkdir -p "$qa_data/$model_suffix" "$qa_data/.cache/huggingface"
# APFS clones share disk blocks while keeping writable QA files independent.
for model in qwen3_tts_1_7b qwen3_tts_base_1_7b voxtral_4b moss_tts_8b; do
  if [ -d "$source_data/$model_suffix/$model" ] && [ ! -e "$qa_data/$model_suffix/$model" ]; then
    cp -cR "$source_data/$model_suffix/$model" "$qa_data/$model_suffix/"
  fi
done
if [ -d "$source_data/.cache/huggingface/hub" ] && [ ! -e "$qa_data/.cache/huggingface/hub" ]; then
  cp -cR "$source_data/.cache/huggingface/hub" "$qa_data/.cache/huggingface/"
fi
codesign --force --sign - --entitlements "$project_root/macos/Runner/Release.entitlements" "$2"
ruby "$project_root/tools/verify_macos_release_entitlements.rb" "$2"
