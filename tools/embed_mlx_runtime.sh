#!/bin/sh
# Xcode build phase: embed executable code; keep model weights in the cache.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root="${READALOUD_MLX_RUNTIME_ROOT:-$HOME/Library/Containers/com.kellyjanderson.readAloud/Data/Library/Application Support/read_aloud/mlx-tts/runtime}"
if [ ! -x "$runtime_root/venv/bin/python" ]; then
  echo 'warning: MLX runtime is not installed; this build supports Kokoro only. Run tools/install_mlx_tts_runtime.sh to package MLX engines.' >&2
  exit 0
fi
python_root=$(dirname "$(dirname "$(realpath "$runtime_root/venv/bin/python")")")
case "$python_root" in
  "$runtime_root"/python/*) ;;
  *) echo 'Refusing to embed an interpreter outside the managed MLX runtime.' >&2; exit 1 ;;
esac
# Assemble outside the bundle: expanded executable trees slow cold app admission.
resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
destination=$(mktemp -d "${TARGET_TEMP_DIR:-${TMPDIR:-/tmp}}/mlx-python.XXXXXX")
trap 'rm -rf "$destination"' EXIT HUP INT TERM
ditto "$python_root" "$destination"
ditto "$runtime_root/venv/lib/python3.12/site-packages" "$destination/lib/python3.12/site-packages"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
find "$destination" -type f \( -name '*.so' -o -name '*.dylib' \) -exec codesign --force --sign "$identity" {} \;
codesign --force --sign "$identity" --entitlements "$project_root/tools/mlx_python.entitlements" "$destination/bin/python3.12"

ruby "$project_root/tools/package_python_runtime.rb" --omit-redundant-bytecode "$destination" mlx bin/python3.12 "$resources/python-runtimes"
# Delete only obsolete expanded output, never the source runtime.
rm -rf "$resources/mlx-python"
