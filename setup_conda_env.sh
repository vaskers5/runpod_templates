#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 USERNAME [PYTHON_VERSION]"
  exit 1
fi

USERNAME="$1"
PYTHON_VERSION="${2:-3.10}"          # по умолчанию Python 3.10
CONDA_ENV_NAME="${CONDA_ENV_NAME:-work}"  # имя окружения по умолчанию (НЕ 'base')

if [ "$EUID" -ne 0 ]; then
  echo "This script must run as root."
  exit 1
fi

if ! id "$USERNAME" &>/dev/null; then
  echo "Error: User '$USERNAME' does not exist. Cannot create Conda environment."
  exit 1
fi

# проверим наличие conda
if [[ ! -f /etc/profile.d/conda.sh ]]; then
  echo "Warning: /etc/profile.d/conda.sh not found — conda may be missing. Skipping env setup."
  exit 0
fi

echo "--- Setting up Conda environment for '$USERNAME' with Python $PYTHON_VERSION (env: $CONDA_ENV_NAME)… ---"

sudo -u "$USERNAME" bash <<'EOF'
set -Eeuo pipefail
source /etc/profile.d/conda.sh

# Если 'conda' не доступна для пользователя — ничего не делаем
if ! command -v conda >/dev/null 2>&1; then
  echo "Warning: conda not found in PATH for user. Skipping."
  exit 0
fi
EOF

# Передаём переменные внутрь heredoc корректно
sudo -u "$USERNAME" bash <<EOF
set -Eeuo pipefail
source /etc/profile.d/conda.sh

# Проверяем, есть ли уже окружение с именем ${CONDA_ENV_NAME}
if conda env list | awk '{print \$1}' | grep -qx "${CONDA_ENV_NAME}"; then
  echo "Conda env '${CONDA_ENV_NAME}' уже существует — пропускаю создание."
else
  conda create -n "${CONDA_ENV_NAME}" -y python="${PYTHON_VERSION}"
  echo "Conda environment '${CONDA_ENV_NAME}' создан."
fi

# Инициализация оболочки один раз (если не сделана)
if ! grep -q 'conda initialize' "\$HOME/.bashrc" 2>/dev/null; then
  conda init bash
fi

echo "Conda setup complete for user."
EOF

echo "✅ Conda setup complete for user '$USERNAME'."
