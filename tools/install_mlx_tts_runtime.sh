#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
support_root="$HOME/Library/Containers/com.kellyjanderson.readAloud/Data/Library/Application Support/read_aloud/mlx-tts"
runtime_root="$support_root/runtime"
python_root="$runtime_root/python"
venv_root="$runtime_root/venv"

command -v uv >/dev/null 2>&1 || {
  echo "Install uv before setting up the local MLX runtime." >&2
  exit 1
}

mkdir -p "$python_root"
UV_PYTHON_INSTALL_DIR="$python_root" uv python install 3.12
python_bin=$(UV_PYTHON_INSTALL_DIR="$python_root" uv python find --no-project --resolve-links 3.12)
uv venv --python "$python_bin" "$venv_root"
uv pip install --python "$venv_root/bin/python" \
  -r "$project_root/tools/mlx_tts_requirements.txt"


"$venv_root/bin/python" -c 'import importlib.metadata as m, platform; assert platform.machine() == "arm64"; assert m.version("mlx") == "0.32.4"; assert m.version("mlx-audio") == "0.6.3"; print("arm64 MLX runtime is ready")'
