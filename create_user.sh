#!/usr/bin/env bash
set -e

if [ $# -lt 3 ]; then
  echo "Использование: $0 USERNAME /path/to/key.pub [--sudo] SERVER_ADDRESS"
  exit 1
fi

USERNAME="$1"; SSH_KEY="$2"; shift 2

SUDO_FLAG=0
if [[ "$1" == "--sudo" ]]; then
  SUDO_FLAG=1; shift
fi

SERVER="$1"

# Проверяем права root
if [ "$EUID" -ne 0 ]; then
  echo "Этот скрипт нужно запускать от root или через sudo."
  exit 1
fi

# Создание пользователя
if id "$USERNAME" &>/dev/null; then
  echo "Пользователь $USERNAME уже существует"
else
  adduser --disabled-password --gecos "" --shell /bin/bash "$USERNAME"
fi

# Добавление в sudo-группу (если нужно)
if [ "$SUDO_FLAG" -eq 1 ]; then
  usermod -aG sudo "$USERNAME"
  # опционально: без необходимости ввода пароля при sudo
  echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
  chmod 0440 "/etc/sudoers.d/$USERNAME"
fi

# Настройка SSH-ключей
HOME_DIR="/home/$USERNAME"
SSH_DIR="$HOME_DIR/.ssh"
mkdir -p "$SSH_DIR"
cat "$SSH_KEY" > "$SSH_DIR/authorized_keys"

chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/authorized_keys"
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"

echo "Пользователь '$USERNAME' успешно создан, ключ добавлен."

echo
echo "SSH-подключение:"
echo "    ssh -i PRIVATE_KEY_PATH $USERNAME@$SERVER"
