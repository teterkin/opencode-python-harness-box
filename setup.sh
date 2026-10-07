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

# Цвета: на TTY или по FORCE_COLOR; NO_COLOR гасит всегда. В пайпе (как в
# тестах) вывод остаётся машиночитаемым — без управляющих кодов.
if [[ -n "${NO_COLOR:-}" ]]; then
    COLOR=0
elif [[ -n "${FORCE_COLOR:-}" || -t 1 ]]; then
    COLOR=1
else
    COLOR=0
fi

if [[ "$COLOR" -eq 1 ]]; then
    C_BOLD=$'\033[1m'
    C_CYAN=$'\033[36m'
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_DIM=$'\033[2m'
    C_RESET=$'\033[0m'
else
    C_BOLD=''
    C_CYAN=''
    C_GREEN=''
    C_RED=''
    C_DIM=''
    C_RESET=''
fi

hdr() { printf '%s%s%s\n' "$C_CYAN" "$1" "$C_RESET"; }
err() { printf '%sошибка:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }

usage() {
    printf '%sИспользование%s: setup.sh [ml|gpu ...]\n\n' "$C_BOLD" "$C_RESET"
    hdr "Направления:"
    printf '  %sml%s   numpy==%s, pandas==%s,\n' \
        "$C_BOLD" "$C_RESET" "$NUMPY_VERSION" "$PANDAS_VERSION"
    printf '       scikit-learn==%s — установка с фиксированными версиями\n' \
        "$SKLEARN_VERSION"
    printf '  %sgpu%s  инструкция по PyTorch/TensorFlow, ничего не устанавливает\n\n' \
        "$C_BOLD" "$C_RESET"
    printf 'Окружение: %s (переопределяется переменной VENV_DIR)\n' "$VENV_DIR"
}

ensure_venv() {
    if [[ ! -x "$PY" ]]; then
        printf '%s→%s создаю venv: %s\n' "$C_CYAN" "$C_RESET" "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
    fi
}

install_ml() {
    ensure_venv
    "$PY" -m pip install --disable-pip-version-check --quiet \
        "numpy==$NUMPY_VERSION" \
        "pandas==$PANDAS_VERSION" \
        "scikit-learn==$SKLEARN_VERSION"
    printf '%s✓%s установлено в %s:\n' "$C_GREEN" "$C_RESET" "$VENV_DIR"
    "$PY" -m pip list --format=freeze
}

show_gpu() {
    printf '%sНаправление gpu%s ничего не устанавливает автоматически:\n' \
        "$C_CYAN" "$C_RESET"
    printf 'сборки CUDA-пакетов зависят от версии драйверов.\n'
    printf 'После проверки драйвера ставь руками:\n\n'
    printf '  %sPyTorch:%s    https://pytorch.org/get-started/locally/\n' \
        "$C_BOLD" "$C_RESET"
    printf '  %sTensorFlow:%s https://tensorflow.org/install/pip\n\n' \
        "$C_BOLD" "$C_RESET"
    printf 'Проверка: %s/bin/python -c "import torch"\n' "$VENV_DIR"
    printf 'или       %s/bin/python -c "import tensorflow"\n' "$VENV_DIR"
}

current_env() {
    if [[ -x "$PY" ]]; then
        "$PY" -m pip list --format=freeze
    else
        echo "(venv не создан)"
    fi
}

menu() {
    printf '%sТекущее окружение%s (%s):\n' "$C_CYAN" "$C_RESET" "$VENV_DIR"
    current_env | sed 's/^/  /'
    echo
    hdr "Направления:"
    printf '  1) %sml%s   — numpy==%s, pandas==%s,\n' \
        "$C_BOLD" "$C_RESET" "$NUMPY_VERSION" "$PANDAS_VERSION"
    printf '            scikit-learn==%s (фиксированные версии)\n' "$SKLEARN_VERSION"
    printf '  2) %sgpu%s  — инструкция по PyTorch/TensorFlow, ничего не ставит\n' \
        "$C_BOLD" "$C_RESET"
    printf '%sВыберите номер или название (Enter — выйти): %s' "$C_DIM" "$C_RESET"
    local choice=''
    read -r choice || { echo; return 0; }
    case "$choice" in
        ''|q|Q) return 0 ;;
        1|ml)   install_ml ;;
        2|gpu)  show_gpu ;;
        *)
            err "неизвестный выбор: $choice"
            return 1
            ;;
    esac
}

in_container() {
    [[ -f /.dockerenv || -f /.containerenv ]]
}

# --help читается где угодно, всё остальное — только в контейнере.
help_only=1
if [[ $# -eq 0 ]]; then
    help_only=0
else
    for arg in "$@"; do
        case "$arg" in
            -h|--help) ;;
            *) help_only=0 ;;
        esac
    done
fi

if [[ "$help_only" -eq 0 ]] && ! in_container; then
    printf '%sошибка:%s setup.sh запускается только внутри контейнера:\n' \
        "$C_RED" "$C_RESET" >&2
    printf 'пакеты должны попасть в venv смонтированного каталога (%s),\n' \
        "$VENV_DIR" >&2
    printf 'а не в окружение хоста.\n\n' >&2
    cat >&2 <<EOF
  ./run.sh setup.sh          — интерактивное меню
  ./run.sh setup.sh ml       — установка ml-направления
  ./run.sh setup.sh gpu      — инструкция по PyTorch/TensorFlow
EOF
    exit 1
fi

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
            err "неизвестное направление: $arg"
            usage >&2
            exit 1
            ;;
    esac
done
