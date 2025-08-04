#!/usr/bin/env bash
# setup_comfy_env.sh ─ set up an isolated ComfyUI Conda env for a given user
# Usage: sudo ./setup_comfy_env.sh USERNAME [PYTHON_VERSION]
# ---------------------------------------------------------------------------

set -euo pipefail

# ────────────────────── argument & variable handling ────────────────────── #
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 USERNAME [PYTHON_VERSION]" >&2
  exit 1
fi

USERNAME="$1"
PYTHON_VERSION="${2:-3.10}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMFY_ENV_NAME="${COMFY_ENV_NAME:-comfy_env}"
COMFY_REPO_URL="${COMFY_REPO_URL:-https://github.com/comfyanonymous/ComfyUI.git}"

# You may point this somewhere else (e.g. /home/$USERNAME/comfy_data) if /data
# is not writable on your platform.
COMFY_DATA_DIR="${COMFY_DATA_DIR:-/data/marketing}"
COMFY_DIR="${COMFY_DIR:-$COMFY_DATA_DIR/comfy}"
COMFY_EXTENSION_LIST="${COMFY_EXTENSION_LIST:-$SCRIPT_DIR/comfy_data/extension_list.txt}"
COMFY_EXTRA_MODEL_PATHS="${COMFY_EXTRA_MODEL_PATHS:-$SCRIPT_DIR/comfy_data/extra_model_paths.yaml}"

# ────────────────────────────── pre-flight checks ───────────────────────── #
[[ $EUID -eq 0 ]] || { echo "This script must run as root." >&2; exit 1; }
id "$USERNAME" &>/dev/null || { echo "Error: user '$USERNAME' does not exist." >&2; exit 1; }

echo -e "\n--- Setting up ComfyUI environment '$COMFY_ENV_NAME' for user '$USERNAME' ---"

# ───────────────────── ensure data dir & permissions ────────────────────── #
mkdir -p "$COMFY_DATA_DIR"

if chown -R "$USERNAME":"$USERNAME" "$COMFY_DATA_DIR" 2>/dev/null; then
  echo "✓ Ownership of $COMFY_DATA_DIR set to $USERNAME"
else
  echo "⚠️  chown failed on $COMFY_DATA_DIR (likely a root-squashed mount)."
  if command -v setfacl &>/dev/null; then
    echo "→ Granting ACL rwx to $USERNAME instead…"
    setfacl -m u:"$USERNAME":rwx "$COMFY_DATA_DIR"
  else
    cat >&2 <<EOF
Error: cannot change ownership of $COMFY_DATA_DIR and \`setfacl\` is unavailable.
Either:

  • Run this script on a filesystem that allows chown, or
  • Install ACL support \(apt install acl\), or
  • Redefine COMFY_DATA_DIR to a directory you own, e.g.:
        COMFY_DATA_DIR=/home/$USERNAME/comfy_data $0 $USERNAME $PYTHON_VERSION
EOF
    exit 1
  fi
fi

# ───────────────────────- create/activate conda env -────────────────────── #
sudo -u "$USERNAME" bash <<'EOFUSER'
set -euo pipefail
source /etc/profile.d/conda.sh || true   # adapt if conda.sh lives elsewhere

if ! conda env list | awk '{print $1}' | grep -qx "$COMFY_ENV_NAME"; then
  echo "→ Creating Conda env $COMFY_ENV_NAME (python=$PYTHON_VERSION)…"
  conda create -y -n "$COMFY_ENV_NAME" python="$PYTHON_VERSION"
fi

echo "→ Activating $COMFY_ENV_NAME…"
conda activate "$COMFY_ENV_NAME"

# Upgrade pip and install CUDA PyTorch build
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# ───────────────- clone ComfyUI repo & install deps ─────────────── #
if [[ ! -d "$COMFY_DIR" ]]; then
  git clone "$COMFY_REPO_URL" "$COMFY_DIR"
fi

cd "$COMFY_DIR"
pip install -r requirements.txt

# ─────────────- optional: clone custom nodes listed in file ───────────── #
if [[ -f "$COMFY_EXTENSION_LIST" ]]; then
  mkdir -p custom_nodes
  while IFS= read -r repo; do
    repo="$(echo "$repo" | xargs)"          # trim whitespace
    [[ -z "$repo" || "$repo" == \#* ]] && continue
    name="$(basename "$repo" .git)"
    target="custom_nodes/$name"
    [[ -d "$target" ]] || git clone "$repo" "$target"
  done < "$COMFY_EXTENSION_LIST"
fi

# ───────────- optional: extra model search paths YAML ─────────── #
[[ -f "$COMFY_EXTRA_MODEL_PATHS" ]] && cp "$COMFY_EXTRA_MODEL_PATHS" extra_model_paths.yaml
EOFUSER

# ──────────────────- shell helpers for the target user ─────────────────── #
USER_HOME=$(eval echo ~"$USERNAME")
{
  echo
  echo "export COMFY_DATA_DIR='$COMFY_DATA_DIR'"
  echo "export COMFY_DIR='$COMFY_DIR'"
  echo "export COMFY_ENV_NAME='$COMFY_ENV_NAME'"
} | sudo -u "$USERNAME" tee -a "$USER_HOME/.bashrc" >/dev/null

echo -e "\n✅ ComfyUI environment '$COMFY_ENV_NAME' is ready."
echo    "To start using it:"
echo    "   sudo -u $USERNAME -i     # if you aren't that user"
echo    "   conda activate $COMFY_ENV_NAME"
echo    "   cd \$COMFY_DIR"
