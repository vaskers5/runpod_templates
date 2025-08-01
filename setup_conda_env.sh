#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 USERNAME [PYTHON_VERSION]"
  exit 1
fi

USERNAME="$1"
PYTHON_VERSION="${2:-3.10}" # Default to Python 3.10 if not provided

if [ "$EUID" -ne 0 ]; then
  echo "This script must run as root."
  exit 1
fi

if ! id "$USERNAME" &>/dev/null; then
  echo "Error: User '$USERNAME' does not exist. Cannot create Conda environment."
  exit 1
fi

echo "--- Setting up Conda environment for '$USERNAME' with Python $PYTHON_VERSION... ---"

# Run commands as the new user to ensure correct file permissions
sudo -u "$USERNAME" bash <<EOF
source /etc/profile.d/conda.sh
conda create -n base -y python=$PYTHON_VERSION
conda init bash
echo "Conda environment 'base' created and shell initialized."
EOF

echo "✅ Conda setup complete for user '$USERNAME'."