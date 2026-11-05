#!/bin/sh
# Isolated optional CPU provider runtime; never touches the MLX environment.
set -eu
root=${1:?Usage: tools/install_modernbooknlp_runtime.sh RUNTIME_DIRECTORY [python3.11]}
python=${2:-python3.11}
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$root"
root=$(CDPATH= cd -- "$root" && pwd)
"$python" -m venv "$root/venv"
"$root/venv/bin/python" -m pip install -r "$project_root/tools/modernbooknlp_requirements.txt"
archive="$root/upstream.tar.gz"
revision=84f1f34f6f0ec7c6e9c558b4371e61ea2354d95b
if [ ! -f "$archive" ]; then
  curl --fail --location --max-time 180 "https://github.com/gasmichel/ModernBookNLP_QA/archive/$revision.tar.gz" -o "$archive.partial"
  mv "$archive.partial" "$archive"
fi
expected=9dbd060df5448bf5e802975e2b117acbb99dd4fc5b8192e4cbd92b78f2b47db6
actual=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
[ "$actual" = "$expected" ] || { echo 'Upstream archive checksum mismatch' >&2; exit 1; }
staging=$(mktemp -d "$root/source-XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
tar -xzf "$archive" -C "$staging"
cd "$staging/ModernBookNLP_QA-$revision/ModernBookNLP"
patch -p1 < "$project_root/tools/modernbooknlp-local-runtime.patch"
"$root/venv/bin/python" -m pip install --no-deps .
"$root/venv/bin/python" "$project_root/tools/prepare_modernbooknlp_assets.py" "$root/assets"
