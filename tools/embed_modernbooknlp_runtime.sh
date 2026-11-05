#!/bin/sh
# Independent bundled CPU runtime. No speech dependencies or model weights.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root="${READALOUD_BOOKNLP_RUNTIME_ROOT:-$HOME/Library/Application Support/ReadAloudProviderQA/runtime}"
if [ ! -x "$runtime_root/venv/bin/python" ]; then
  echo 'warning: ModernBookNLP runtime absent; its optional Settings action will report this.' >&2
  exit 0
fi
python_root=$(dirname "$(dirname "$(realpath "$runtime_root/venv/bin/python")")")
case "$python_root" in
  "$runtime_root"/python/*) ;;
  *) echo 'ModernBookNLP packaging requires a managed standalone Python under runtime/python.' >&2; exit 1 ;;
esac
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/modernbooknlp-python"
mkdir -p "$destination"
ditto "$python_root" "$destination"
ditto "$runtime_root/venv/lib/python3.11/site-packages" "$destination/lib/python3.11/site-packages"
# Torch 2.6's bundled OpenMP aborts on SHM2 in the macOS app sandbox.
# LLVM 22.1.6 handles unavailable shared memory without disabling the sandbox.
# Pin the qualified arm64 artifact; never silently inherit a Homebrew upgrade.
openmp="${READALOUD_BOOKNLP_OPENMP_LIBRARY:-/opt/homebrew/opt/libomp/lib/libomp.dylib}"
openmp_license="${READALOUD_BOOKNLP_OPENMP_LICENSE:-/opt/homebrew/opt/libomp/LICENSE.TXT}"
expected_openmp=7f07009be4fb2ec519ef62f7cc864aa2412c7ece7de41c15eb89dce5eb991650
if [ ! -f "$openmp" ] || [ ! -f "$openmp_license" ]; then
  echo 'ModernBookNLP requires the qualified arm64 LLVM OpenMP 22.1.6 library and license; see docs/modernbooknlp-provider.md.' >&2
  exit 1
fi
actual_openmp=$(shasum -a 256 "$openmp" | cut -d ' ' -f 1)
[ "$actual_openmp" = "$expected_openmp" ] || { echo 'Unqualified ModernBookNLP OpenMP artifact; see docs/modernbooknlp-provider.md.' >&2; exit 1; }
cp "$openmp" "$destination/lib/python3.11/site-packages/torch/lib/libomp.dylib"
cp "$openmp_license" "$destination/lib/python3.11/site-packages/torch/lib/LLVM-OpenMP-LICENSE.txt"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
find "$destination" -type f \( -name '*.so' -o -name '*.dylib' \) -exec codesign --force --sign "$identity" {} \;
codesign --force --sign "$identity" --entitlements "$project_root/tools/mlx_python.entitlements" "$destination/bin/python3.11"
