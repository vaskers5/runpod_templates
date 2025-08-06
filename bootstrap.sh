#!/usr/bin/env bash
# -------------------------------------------------
#  Bootstrap script for RunPod container
# -------------------------------------------------
set -Eeuo pipefail

# ────────────────────────────────────────────────
#  Часть 1: Первоначальная настройка (-- один раз)
# ────────────────────────────────────────────────
if [[ ! -f /opt/runpod_setup_complete ]]; then
  echo "--- Выполняется первоначальная настройка контейнера ---"

  # 1. Системные пакеты
  echo "Установка системных пакетов…"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    openssh-server sudo git ca-certificates nano wget tmux \
    && rm -rf /var/lib/apt/lists/*

  # 2. Miniconda
  echo "Установка/обновление Miniconda в /opt/conda…"
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
  bash /tmp/miniconda.sh -b -u -p /opt/conda
  rm -f /tmp/miniconda.sh
  ln -sf /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh

  # 3. Скрипты
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Ошибка: переменная GITHUB_TOKEN не задана." >&2
    exit 1
  fi
  echo "Клонирование репозитория со скриптами…"
  rm -rf /opt/scripts
  git clone --depth 1 "https://github.com/vaskers5/runpod_templates" /opt/scripts
  chmod +x /opt/scripts/*.sh
  rm -rf /opt/scripts/.git

  # 4. SSH-сервер
  echo "Настройка SSH…"
  mkdir -p /var/run/sshd
  sed -i \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
    -e 's/^#\?UsePAM.*/UsePAM yes/' \
    /etc/ssh/sshd_config

  # 5. Файл-флаг
  touch /opt/runpod_setup_complete
  echo "--- Первоначальная настройка завершена ---"
else
  echo "--- Первоначальная настройка уже выполнена, пропускается. ---"
fi

# ────────────────────────────────────────────────
#  Часть 2: Запуск сервисов и пользователи (-- всегда)
# ────────────────────────────────────────────────

# 1. SSH-server (background)
/usr/sbin/sshd -D &

# 2. Пользователи
create_admin_users() {
  local entry username userkey usersudo sudo_arg key_file
  IFS=';' read -ra entries <<< "${ADMIN_USERS}"
  for entry in "${entries[@]}"; do
    IFS=':' read -r username userkey usersudo <<< "${entry}"
    username="${username//[[:space:]]/}"          # trim spaces
    [[ -z "${username}" ]] && continue

    echo "--- Настройка пользователя ${username} ---"
    key_file=$(mktemp)
    printf '%s\n' "${userkey}" > "${key_file}"

    sudo_arg=""
    [[ "${usersudo,,}" == "true" ]] && sudo_arg="--sudo"

    /opt/scripts/create_user.sh "${username}" "${key_file}" ${sudo_arg} "pod_ip_or_domain"
    /opt/scripts/setup_conda_env.sh "${username}" "${PYTHON_VERSION:-3.10}"
    rm -f "${key_file}"
    echo "--- Пользователь ${username} полностью настроен ---"
  done
}

if [[ -n "${ADMIN_USERS:-}" ]]; then
  create_admin_users
elif [[ -n "${ADMIN_USER_NAME:-}" && -n "${ADMIN_USER_PUBKEY:-}" ]]; then
  echo "--- Настройка пользователя ${ADMIN_USER_NAME} ---"
  key_file=$(mktemp)
  printf '%s\n' "${ADMIN_USER_PUBKEY}" > "${key_file}"

  sudo_arg=""
  [[ "${ADMIN_USER_SUDO:-false}" == "true" ]] && sudo_arg="--sudo"

  /opt/scripts/create_user.sh "${ADMIN_USER_NAME}" "${key_file}" ${sudo_arg} "pod_ip_or_domain"
  /opt/scripts/setup_conda_env.sh "${ADMIN_USER_NAME}" "${PYTHON_VERSION:-3.10}"
  rm -f "${key_file}"
  echo "--- Пользователь ${ADMIN_USER_NAME} полностью настроен ---"
else
  echo "Переменные ADMIN_USERS или ADMIN_USER_NAME не заданы – пользователь не создан."
fi

# 3. S3-монтирование (не критично, если упадёт)
/opt/scripts/mount_s3.sh || echo "mount_s3.sh завершился с ошибкой, продолжаем…"

echo "--- Контейнер готов к работе. Ожидание подключения… ---"
exec sleep infinity
