#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 4 ]; then
  echo "Usage: $0 USERNAME COMFY_DIR PYTHON_VERSION EXTENSION_LIST_NAME" >&2
  exit 1
fi

USERNAME="$1"
COMFY_DIR="$2"
PYTHON_VERSION="$3"
EXT_LIST_NAME="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMFY_ENV_NAME="${COMFY_ENV_NAME:-comfy_env}"
COMFY_REPO_URL="${COMFY_REPO_URL:-https://github.com/comfyanonymous/ComfyUI.git}"
COMFY_DATA_DIR="$(dirname "$COMFY_DIR")"
COMFY_EXTENSION_LIST_DIR="${COMFY_EXTENSION_LIST_DIR:-$SCRIPT_DIR/comfy_data/extension_lists}"
COMFY_EXTENSION_LIST="$COMFY_EXTENSION_LIST_DIR/${EXT_LIST_NAME}.txt"
COMFY_EXTRA_MODEL_PATHS="${COMFY_EXTRA_MODEL_PATHS:-$SCRIPT_DIR/comfy_data/extra_model_paths.yaml}"

if [ "$EUID" -ne 0 ]; then
  echo "This script must run as root." >&2
  exit 1
fi

if ! id "$USERNAME" &>/dev/null; then
  echo "Error: User '$USERNAME' does not exist." >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "Installing tmux..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tmux
  rm -rf /var/lib/apt/lists/*
fi

echo "--- Setting up ComfyUI environment '${COMFY_ENV_NAME}' for user '${USERNAME}'... ---"

mkdir -p "$COMFY_DATA_DIR"
chown -R "$USERNAME":"$USERNAME" "$COMFY_DATA_DIR"

EXT_LIST="$COMFY_EXTENSION_LIST"
EXTRA_MODELS="$COMFY_EXTRA_MODEL_PATHS"

sudo -u "$USERNAME" bash <<EOFUSER
set -e
source /etc/profile.d/conda.sh
if ! conda env list | awk '{print \$1}' | grep -qx "$COMFY_ENV_NAME"; then
  conda create -y -n "$COMFY_ENV_NAME" -c conda-forge --override-channels python="$PYTHON_VERSION"
fi
conda activate "$COMFY_ENV_NAME"
pip3 install --upgrade pip
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

if [ ! -d "$COMFY_DIR" ]; then
  git clone "$COMFY_REPO_URL" "$COMFY_DIR"
fi

cd "$COMFY_DIR"
pip3 install -r requirements.txt

if [ -f "$EXT_LIST" ]; then
  mkdir -p custom_nodes
  while IFS= read -r line; do
    line="\$(echo "\$line" | xargs)"
    [ -z "\$line" ] && continue
    [[ "\$line" == \#* ]] && continue
    repo="\$(echo "\$line" | cut -d ' ' -f1)"
    flag="\$(echo "\$line" | cut -s -d ' ' -f2 | tr '[:upper:]' '[:lower:]')"
    name="\$(basename "\$repo" .git)"
    target="custom_nodes/\$name"
    if [ ! -d "\$target" ]; then
      git clone "\$repo" "\$target"
    fi
    if [ -f "\$target/requirements.txt" ] && [[ "\$flag" == "true" || "\$flag" == "pip_install_true" ]]; then
      (cd "\$target" && pip3 install -r requirements.txt)
    fi
  done < "$EXT_LIST"
fi

if [ -f "$EXTRA_MODELS" ]; then
  cp "$EXTRA_MODELS" extra_model_paths.yaml
fi
EOFUSER

USER_HOME=$(eval echo ~"$USERNAME")
printf '\nexport COMFY_DATA_DIR="%s"\nexport COMFY_DIR="%s"\nexport COMFY_ENV_NAME="%s"\n' "$COMFY_DATA_DIR" "$COMFY_DIR" "$COMFY_ENV_NAME" | sudo -u "$USERNAME" tee -a "$USER_HOME/.bashrc" >/dev/null

echo "✅ ComfyUI environment '$COMFY_ENV_NAME' set up at '$COMFY_DIR' for user '$USERNAME'."
echo "To use it run: conda activate $COMFY_ENV_NAME && cd $COMFY_DIR"
