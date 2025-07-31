#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Использование: $0 USERNAME /path/to/key.pub [--sudo] SERVER_ADDRESS"
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
  echo "Этот скрипт должен запускаться как root или через sudo."
  exit 1
fi

# Проверка существования пользователя
if id "$USERNAME" &>/dev/null; then
  echo "Пользователь '$USERNAME' уже существует, пропускаем создание."
else
  adduser --disabled-password --gecos "" --shell /bin/bash "$USERNAME"
fi

# Создание .ssh и копирование ключа
HOME_DIR="/home/${USERNAME}"
SSH_DIR="${HOME_DIR}/.ssh"
mkdir -p "$SSH_DIR"
cat "$SSH_KEY_PATH" > "${SSH_DIR}/authorized_keys"

chown -R "${USERNAME}:${USERNAME}" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "${SSH_DIR}/authorized_keys"

echo "SSH ключ установлен для пользователя '$USERNAME'."

# Создать sudoers.d, если нужно sudo‑прав
if [ "$SUDO_FLAG" -eq 1 ]; then
  if [ ! -d /etc/sudoers.d ]; then
    mkdir -p /etc/sudoers.d
    chown root:root /etc/sudoers.d
    chmod 755 /etc/sudoers.d
  fi
  echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"
  chown root:root "/etc/sudoers.d/${USERNAME}"
  chmod 0440 "/etc/sudoers.d/${USERNAME}"
  echo "Пользователь '$USERNAME' добавлен в sudoers без запроса пароля."
fi

echo
echo "Пользователь '$USERNAME' успешно настроен."
echo "Команда для подключения по SSH:"
echo "    ssh -i /путь/к/приватному_ключу ${USERNAME}@${SERVER}"
