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
FASTAPI_VERSION=0.142.2
DJANGO_VERSION=6.1.2
FLASK_VERSION=3.1.3
UVICORN_VERSION=0.54.0
GUNICORN_VERSION=26.2.0

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
    printf '%sИспользование%s: setup.sh [ml|web|gpu ...]\n\n' "$C_BOLD" "$C_RESET"
    hdr "Направления:"
    printf '  %sml%s   numpy==%s, pandas==%s, scikit-learn==%s\n' \
        "$C_BOLD" "$C_RESET" "$NUMPY_VERSION" "$PANDAS_VERSION" "$SKLEARN_VERSION"
    printf '  %sweb%s  fastapi, django, flask, uvicorn, gunicorn\n' \
        "$C_BOLD" "$C_RESET"
    printf '  %sgpu%s  инструкция по PyTorch/TensorFlow, ничего не устанавливает\n\n' \
        "$C_BOLD" "$C_RESET"
    printf 'Окружение: %s (переопределяется переменной VENV_DIR)\n' "$VENV_DIR"
}

say_installing() {
    printf '%s→%s установка пакетов направления %s в %s — может занять минуту\n' \
        "$C_CYAN" "$C_RESET" "$1" "$VENV_DIR"
}

ensure_venv() {
    if [[ ! -x "$PY" ]]; then
        printf '%s→%s создаю venv: %s\n' "$C_CYAN" "$C_RESET" "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
    fi
}

install_pkgs() {
    ensure_venv
    "$PY" -m pip install --disable-pip-version-check --quiet "$@"
    printf '%s✓%s установлено в %s:\n' "$C_GREEN" "$C_RESET" "$VENV_DIR"
    "$PY" -m pip list --format=freeze
}

install_ml() {
    install_pkgs \
        "numpy==$NUMPY_VERSION" \
        "pandas==$PANDAS_VERSION" \
        "scikit-learn==$SKLEARN_VERSION"
}

install_web() {
    install_pkgs \
        "fastapi==$FASTAPI_VERSION" \
        "django==$DJANGO_VERSION" \
        "flask==$FLASK_VERSION" \
        "uvicorn==$UVICORN_VERSION" \
        "gunicorn==$GUNICORN_VERSION"
}

remove_pkgs() {
    if [[ ! -x "$PY" ]]; then
        printf 'окружение %s не создано — удалять нечего\n' "$VENV_DIR"
        return 0
    fi
    printf '%sУдалить пакеты направлений (пины ml и web) из %s? [y/N]: %s' \
        "$C_BOLD" "$VENV_DIR" "$C_RESET"
    local answer=''
    read -r answer || { echo; printf 'Отменено\n'; return 0; }
    case "$answer" in
        y|Y|yes|Yes|YES|д|Д|да|Да|ДА)
            "$PY" -m pip uninstall --disable-pip-version-check -y \
                numpy pandas scikit-learn fastapi django flask uvicorn gunicorn
            printf '%s✓%s удалены пакеты направлений из %s\n' \
                "$C_GREEN" "$C_RESET" "$VENV_DIR"
            ;;
        *)
            printf 'Отменено\n'
            ;;
    esac
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

base_toolchain() {
    [[ -x /opt/devtools/bin/python ]] || return 0
    /opt/devtools/bin/python -m pip list --format=freeze --disable-pip-version-check |
        grep -E '^(pytest|ruff|mypy|ipython)==' || true
}

menu() {
    printf '%sТекущее окружение%s (%s):\n' "$C_CYAN" "$C_RESET" "$VENV_DIR"
    current_env | sed 's/^/  /'
    if [[ -x /opt/devtools/bin/python ]]; then
        printf '\n%sБазовый тулчейн%s (/opt/devtools — из образа, остаётся при remove):\n' \
            "$C_CYAN" "$C_RESET"
        base_toolchain | sed 's/^/  /'
    fi
    echo
    hdr "Направления:"
    printf '  1) %sml%s   — numpy==%s, pandas==%s, scikit-learn==%s\n' \
        "$C_BOLD" "$C_RESET" "$NUMPY_VERSION" "$PANDAS_VERSION" "$SKLEARN_VERSION"
    printf '  2) %sweb%s  — fastapi, django, flask, uvicorn, gunicorn\n' \
        "$C_BOLD" "$C_RESET"
    printf '  3) %sgpu%s  — инструкция по PyTorch/TensorFlow, ничего не ставит\n' \
        "$C_BOLD" "$C_RESET"
    printf '  4) %sremove%s — Удалить все установленные пакеты по направлениям\n' \
        "$C_BOLD" "$C_RESET"
    printf '%sВыберите номер или название (Enter — выйти): %s' "$C_DIM" "$C_RESET"
    local choice=''
    read -r choice || { echo; return 0; }
    case "$choice" in
        ''|q|Q) return 0 ;;
        1|ml)      say_installing ml;  install_ml ;;
        2|web)     say_installing web; install_web ;;
        3|gpu)     show_gpu ;;
        4|remove)  remove_pkgs ;;
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
  ./run.sh setup.sh web      — установка веб-направления
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
        web) install_web ;;
        gpu) show_gpu ;;
        -h|--help) usage ;;
        *)
            err "неизвестное направление: $arg"
            usage >&2
            exit 1
            ;;
    esac
done
