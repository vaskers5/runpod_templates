#!/bin/bash
# usage: ./create_user_ssh.sh username /path/to/public_key.pub [--sudo] server_address

if [ $# -lt 3 ]; then
  echo "Использование: $0 USERNAME /path/to/key.pub [--sudo] SERVER_ADDRESS"
  exit 1
fi

USERNAME="$1"
SSH_PUBKEY_PATH="$2"
shift 2

SUDO_FLAG=0
if [ "$1" == "--sudo" ]; then
  SUDO_FLAG=1
  shift
fi

SERVER="$1"

# 1. Создать пользователя без пароля, без дополнительных вопросов
adduser --disabled-password --gecos "" "$USERNAME"

# 2. При желании дать sudo-права
if [ "$SUDO_FLAG" -eq 1 ]; then
  usermod -aG sudo "$USERNAME"
fi

# 3. Создать каталог .ssh и добавить ключ
mkdir -p "/home/$USERNAME/.ssh"
cat "$SSH_PUBKEY_PATH" >> "/home/$USERNAME/.ssh/authorized_keys"

# 4. Установить правильные разрешения
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
chmod 700 "/home/$USERNAME/.ssh"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"

echo "Пользователь '$USERNAME' успешно создан."
echo "Его публичный SSH ключ добавлен."
echo
echo "Команда для подключения по SSH:"
echo "    ssh -i /путь/к/ключу_пользователя $USERNAME@$SERVER"
