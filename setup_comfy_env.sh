#!/usr/bin/env bash
# setup_comfy_env.sh ─ set up an isolated ComfyUI Conda env for a given user
# Usage: sudo ./setup_comfy_env.sh USERNAME [PYTHON_VERSION]

set -euo pipefail

# ──────────────────────────── arguments ──────────────────────────── #
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 USERNAME [PYTHON_VERSION]" >&2
  exit 1
fi

USERNAME="$1"
PYTHON_VERSION="${2:-3.10}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMFY_ENV_NAME="${COMFY_ENV_NAME:-comfy_env}"
COMFY_REPO_URL="${COMFY_REPO_URL:-https://github.com/comfyanonymous/ComfyUI.git}"

# Feel free to override on the command line if /data is problematic
COMFY_DATA_DIR="${COMFY_DATA_DIR:-/data/marketing}"
COMFY_DIR="${COMFY_DIR:-$COMFY_DATA_DIR/comfy}"
COMFY_EXTENSION_LIST="${COMFY_EXTENSION_LIST:-$SCRIPT_DIR/comfy_data/extension_list.txt}"
COMFY_EXTRA_MODEL_PATHS="${COMFY_EXTRA_MODEL_PATHS:-$SCRIPT_DIR/comfy_data/extra_model_paths.yaml}"

# ────────────────────────── sanity checks ────────────────────────── #
[[ $EUID -eq 0 ]] || { echo "This script must run as root." >&2; exit 1; }
id "$USERNAME" &>/dev/null || { echo "Error: user '$USERNAME' does not exist." >&2; exit 1; }

echo -e "\n--- Setting up ComfyUI environment '$COMFY_ENV_NAME' for user '$USERNAME' ---"

# ─────────────── create data dir & open permissions ─────────────── #
mkdir -p "$COMFY_DATA_DIR"
chmod -R 777 "$COMFY_DATA_DIR"
echo "✓ Set permissions 777 on $COMFY_DATA_DIR"

# ──────────────── create / activate conda env ────────────────────── #
sudo -u "$USERNAME" bash <<'EOFUSER'
set -euo pipefail
source /etc/profile.d/conda.sh || true   # adjust if conda.sh elsewhere

if ! conda env list | awk '{print $1}' | grep -qx "$COMFY_ENV_NAME"; then
  conda create -y -n "$COMFY_ENV_NAME" python="$PYTHON_VERSION"
fi

conda activate "$COMFY_ENV_NAME"
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# ────────────────── clone ComfyUI & install deps ─────────────────── #
if [[ ! -d "$COMFY_DIR" ]]; then
  git clone "$COMFY_REPO_URL" "$COMFY_DIR"
fi

cd "$COMFY_DIR"
pip install -r requirements.txt

# ─────────────── clone custom nodes (optional) ─────────────── #
if [[ -f "$COMFY_EXTENSION_LIST" ]]; then
  mkdir -p custom_nodes
  while IFS= read -r repo; do
    repo="$(echo "$repo" | xargs)"
    [[ -z "$repo" || "$repo" == \#* ]] && continue
    name="$(basename "$repo" .git)"
    [[ -d "custom_nodes/$name" ]] || git clone "$repo" "custom_nodes/$name"
  done < "$COMFY_EXTENSION_LIST"
fi

# ───────────── copy extra model paths YAML (optional) ───────────── #
[[ -f "$COMFY_EXTRA_MODEL_PATHS" ]] && cp "$COMFY_EXTRA_MODEL_PATHS" extra_model_paths.yaml
EOFUSER

# ─────────────── helper exports for the target user ─────────────── #
USER_HOME=$(eval echo ~"$USERNAME")
{
  echo
  echo "export COMFY_DATA_DIR='$COMFY_DATA_DIR'"
  echo "export COMFY_DIR='$COMFY_DIR'"
  echo "export COMFY_ENV_NAME='$COMFY_ENV_NAME'"
} | sudo -u "$USERNAME" tee -a "$USER_HOME/.bashrc" >/dev/null

echo -e "\n✅ ComfyUI environment '$COMFY_ENV_NAME' is ready."
echo    "To start using it:"
echo    "   sudo -u $USERNAME -i"
echo    "   conda activate $COMFY_ENV_NAME"
echo    "   cd \$COMFY_DIR"
