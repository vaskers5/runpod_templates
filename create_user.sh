#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 USERNAME /path/to/key.pub [--sudo] SERVER_ADDRESS"
  exit 1
fi

USERNAME="$1"
SSH_KEY_PATH="$2"
shift 2

SUDO_FLAG=0
if [[ "${1:-}" == "--sudo" ]]; then
  SUDO_FLAG=1
  shift
fi

SERVER="${1:-}"

if [ "$EUID" -ne 0 ]; then
  echo "This script must run as root."
  exit 1
fi

if id "$USERNAME" &>/dev/null; then
  echo "User '$USERNAME' already exists — skipping creation."
else
  adduser --disabled-password --gecos "" --shell /bin/bash "$USERNAME"
  echo "Created user: $USERNAME"
fi

HOME_DIR="/home/${USERNAME}"
SSH_DIR="${HOME_DIR}/.ssh"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
chown "$USERNAME:$USERNAME" "$SSH_DIR"

# Ensure authorized_keys exists and append to avoid overwriting
cat "$SSH_KEY_PATH" >> "${SSH_DIR}/authorized_keys"
chmod 600 "${SSH_DIR}/authorized_keys"
chown "$USERNAME:$USERNAME" "${SSH_DIR}/authorized_keys"
echo "SSH public key added to $SSH_DIR/authorized_keys"

if [ "$SUDO_FLAG" -eq 1 ]; then
  mkdir -p /etc/sudoers.d
  chmod 750 /etc/sudoers.d
  echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"
  chmod 440 "/etc/sudoers.d/${USERNAME}"
  echo "Granted passwordless sudo to '$USERNAME'"
fi

echo
echo "✅ Setup complete for user '$USERNAME'."
echo "SSH connection command:"
echo "    ssh -i /path/to/private_key ${USERNAME}@${SERVER}"
