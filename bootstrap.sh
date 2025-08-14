#!/usr/bin/env bash
# -------------------------------------------------
#  Bootstrap script for RunPod container (safe)
# -------------------------------------------------
set -Eeuo pipefail

log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }

# ────────────────────────────────────────────────
#  Часть 1: Первоначальная настройка (один раз)
# ────────────────────────────────────────────────
if [[ ! -f /opt/runpod_setup_complete ]]; then
  log "--- Выполняется первоначальная настройка контейнера ---"

  # 1) Системные пакеты
  log "Установка системных пакетов…"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends \
    openssh-server sudo git ca-certificates nano wget tmux \
    && rm -rf /var/lib/apt/lists/*

  # 2) Miniconda
  log "Установка/обновление Miniconda в /opt/conda…"
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
  bash /tmp/miniconda.sh -b -u -p /opt/conda
  rm -f /tmp/miniconda.sh
  ln -sf /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh

  # 3) Скрипты
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Ошибка: переменная GITHUB_TOKEN не задана." >&2
    exit 1
  fi
  log "Клонирование репозитория со скриптами…"
  rm -rf /opt/scripts
  git clone --depth 1 "https://github.com/vaskers5/runpod_templates" /opt/scripts
  chmod +x /opt/scripts/*.sh || true
  rm -rf /opt/scripts/.git || true

  # 4) SSH
  log "Настройка SSH…"
  mkdir -p /var/run/sshd
  sed -i \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
    -e 's/^#\?UsePAM.*/UsePAM yes/' \
    /etc/ssh/sshd_config

  # 5) Файл-флаг
  touch /opt/runpod_setup_complete
  log "--- Первоначальная настройка завершена ---"
else
  log "--- Первоначальная настройка уже выполнена, пропускается. ---"
fi

# ────────────────────────────────────────────────
#  Часть 2: Сервисы и пользователи (каждый запуск)
# ────────────────────────────────────────────────

# 1) SSH-server (background)
log "Запуск SSH-сервера…"
/usr/sbin/sshd -D &

# 2) Пользователи
# Разбор ADMIN_USERS безопасно: "username:pubkey:flag;username2:pubkey2:true;..."
# where pubkey = всё между первым и последним ':' (колонки 2..N-1) — сохраняем возможные ':' внутри комментария ключа.
create_admin_users() {
  local entry username usersudo userkey middle
  local server_hint="${POD_ADDRESS:-pod_ip_or_domain}"
  local pyver="${PYTHON_VERSION:-3.10}"

  IFS=';' read -ra entries <<< "${ADMIN_USERS}"
  for entry in "${entries[@]}"; do
    # пропускаем пустые элементы
    [[ -z "${entry//[[:space:]]/}" ]] && continue

    # username = до первого ':'
    username="${entry%%:*}"
    # usersudo = после последнего ':'
    usersudo="${entry##*:}"
    # userkey = всё между первым и последним ':'
    middle="${entry#*:}"; userkey="${middle%:*}"

    # trim spaces
    username="${username//[[:space:]]/}"
    usersudo="${usersudo//[[:space:]]/}"

    [[ -z "$username" ]] && continue
    [[ -z "${userkey//[[:space:]]/}" ]] && { log "WARN: пустой ключ у $username — пропускаю"; continue; }

    log "--- Настройка пользователя ${username} ---"
    key_file="$(mktemp)"
    printf '%s\n' "${userkey}" > "${key_file}"

    sudo_arg=()
    [[ "${usersudo,,}" == "true" ]] && sudo_arg=("--sudo")

    # Без падения всего скрипта, если на одном пользователе ошибка:
    if ! /opt/scripts/create_user.sh "${username}" "${key_file}" "${sudo_arg[@]:-}" "${server_hint}"; then
      log "ERROR: create_user.sh failed for ${username}; продолжаю со следующими."
      rm -f "${key_file}"
      continue
    fi
    rm -f "${key_file}"

    if ! /opt/scripts/setup_conda_env.sh "${username}" "${pyver}"; then
      log "ERROR: setup_conda_env.sh failed for ${username}; продолжаю со следующими."
    fi
    log "--- Пользователь ${username} полностью настроен ---"
  done
}

if [[ -n "${ADMIN_USERS:-}" ]]; then
  create_admin_users
elif [[ -n "${ADMIN_USER_NAME:-}" && -n "${ADMIN_USER_PUBKEY:-}" ]]; then
  log "--- Настройка пользователя ${ADMIN_USER_NAME} ---"
  key_file="$(mktemp)"
  printf '%s\n' "${ADMIN_USER_PUBKEY}" > "${key_file}"

  sudo_arg=()
  [[ "${ADMIN_USER_SUDO:-false}" == "true" ]] && sudo_arg=("--sudo")

  /opt/scripts/create_user.sh "${ADMIN_USER_NAME}" "${key_file}" "${sudo_arg[@]:-}" "${POD_ADDRESS:-pod_ip_or_domain}" || \
    log "ERROR: create_user.sh failed for ${ADMIN_USER_NAME}"

  rm -f "${key_file}"

  /opt/scripts/setup_conda_env.sh "${ADMIN_USER_NAME}" "${PYTHON_VERSION:-3.10}" || \
    log "ERROR: setup_conda_env.sh failed for ${ADMIN_USER_NAME}"

  log "--- Пользователь ${ADMIN_USER_NAME} полностью настроен ---"
else
  log "Переменные ADMIN_USERS или ADMIN_USER_NAME не заданы – пользователь не создан."
fi

# 3) S3-монтирование (по желанию, оставлено выключенным)
# /opt/scripts/mount_s3.sh || log "mount_s3.sh завершился с ошибкой, продолжаем…"

log "--- Контейнер готов к работе. Ожидание подключения… ---"
exec sleep infinity
