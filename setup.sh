#!/usr/bin/env bash
# Установка пакетов проекта в venv смонтированного каталога.
# Запуск: setup.sh [ml|gpu ...] — без аргументов интерактивное меню.
# Пишет только в $VENV_DIR (по умолчанию /workspace/.venv), образ не меняет.

set -euo pipefail

VENV_DIR="${VENV_DIR:-/workspace/.venv}"
PY="$VENV_DIR/bin/python"

# Пины направлений. Обновление — правка версии + прогон tests/run.sh.
NUMPY_VERSION=2.5.3
PANDAS_VERSION=3.0.6
SKLEARN_VERSION=1.9.1

usage() {
    cat <<EOF
Использование: setup.sh [ml|gpu ...]

Направления:
  ml   numpy==$NUMPY_VERSION, pandas==$PANDAS_VERSION,
       scikit-learn==$SKLEARN_VERSION — установка с фиксированными версиями
  gpu  инструкция по PyTorch/TensorFlow, ничего не устанавливает

Окружение: $VENV_DIR (переопределяется переменной VENV_DIR)
EOF
}

ensure_venv() {
    if [[ ! -x "$PY" ]]; then
        echo "создаю venv: $VENV_DIR"
        python3 -m venv "$VENV_DIR"
    fi
}

install_ml() {
    ensure_venv
    "$PY" -m pip install --disable-pip-version-check --quiet \
        "numpy==$NUMPY_VERSION" \
        "pandas==$PANDAS_VERSION" \
        "scikit-learn==$SKLEARN_VERSION"
    echo "установлено в $VENV_DIR:"
    "$PY" -m pip list --format=freeze
}

show_gpu() {
    cat <<EOF
Направление gpu ничего не устанавливает автоматически: сборки CUDA-пакетов
зависят от версии драйверов. После проверки драйвера ставь руками:

  PyTorch:    https://pytorch.org/get-started/locally/
  TensorFlow: https://tensorflow.org/install/pip

Проверка: $VENV_DIR/bin/python -c "import torch"
или        $VENV_DIR/bin/python -c "import tensorflow"
EOF
}

current_env() {
    if [[ -x "$PY" ]]; then
        "$PY" -m pip list --format=freeze
    else
        echo "(venv не создан)"
    fi
}

menu() {
    echo "Текущее окружение ($VENV_DIR):"
    current_env | sed 's/^/  /'
    echo
    echo "Направления:"
    echo "  1) ml   — numpy==$NUMPY_VERSION, pandas==$PANDAS_VERSION,"
    echo "            scikit-learn==$SKLEARN_VERSION (фиксированные версии)"
    echo "  2) gpu  — инструкция по PyTorch/TensorFlow, ничего не ставит"
    printf 'Выберите номер или название (Enter — выйти): '
    local choice=''
    read -r choice || { echo; return 0; }
    case "$choice" in
        ''|q|Q) return 0 ;;
        1|ml)   install_ml ;;
        2|gpu)  show_gpu ;;
        *)
            echo "неизвестный выбор: $choice" >&2
            return 1
            ;;
    esac
}

if [[ $# -eq 0 ]]; then
    menu
    exit 0
fi

for arg in "$@"; do
    case "$arg" in
        ml) install_ml ;;
        gpu) show_gpu ;;
        -h|--help) usage ;;
        *)
            echo "неизвестное направление: $arg" >&2
            usage >&2
            exit 1
            ;;
    esac
done
