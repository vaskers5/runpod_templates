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

# База для домашних каталогов (по умолчанию /data)
USER_BASE_DIR="${USER_BASE_DIR:-/data}"
HOME_DIR="${USER_BASE_DIR}/${USERNAME}"
SSH_DIR="${HOME_DIR}/.ssh"

mkdir -p "$USER_BASE_DIR"

if id "$USERNAME" &>/dev/null; then
  echo "User '$USERNAME' already exists — skipping creation."
  # убедимся, что домашка правильная (не переприсваиваем, только создаём при отсутствии)
  if [[ ! -d "$HOME_DIR" ]]; then
    mkdir -p "$HOME_DIR"
    chown -R "$USERNAME:$USERNAME" "$HOME_DIR"
  fi
else
  # создаём пользователя с домашкой под /data/<user>
  adduser --disabled-password --gecos "" \
    --home "$HOME_DIR" --shell /bin/bash "$USERNAME"
  echo "Created user: $USERNAME at $HOME_DIR"
fi

# .ssh и ключи
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
chown "$USERNAME:$USERNAME" "$SSH_DIR"

touch "${SSH_DIR}/authorized_keys"
chmod 600 "${SSH_DIR}/authorized_keys"
chown "$USERNAME:$USERNAME" "${SSH_DIR}/authorized_keys"

# Добавляем ключ ТОЛЬКО если его ещё нет (без дублей)
if ! grep -qxF "$(cat "$SSH_KEY_PATH")" "${SSH_DIR}/authorized_keys"; then
  cat "$SSH_KEY_PATH" >> "${SSH_DIR}/authorized_keys"
  echo "SSH public key appended to ${SSH_DIR}/authorized_keys"
else
  echo "SSH public key already present — skipping."
fi

# Sudo (точечно, идемпотентно)
if [ "$SUDO_FLAG" -eq 1 ]; then
  mkdir -p /etc/sudoers.d
  chmod 750 /etc/sudoers.d
  echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"
  chmod 440 "/etc/sudoers.d/${USERNAME}"
  echo "Granted passwordless sudo to '$USERNAME'"
fi

# На всякий случай выставим владельцев в домашке пользователя (ТОЛЬКО в его домашке)
chown -R "$USERNAME:$USERNAME" "$HOME_DIR"

echo
echo "✅ Setup complete for user '$USERNAME'."
[[ -n "$SERVER" ]] && echo "SSH connection command:" && echo "    ssh -i /path/to/private_key ${USERNAME}@${SERVER}"
