#!/usr/bin/env bash
# Запустить opencode с харнессом в контейнере.
# Аргументы уходят в контейнер: ./run.sh bash — шелл вместо TUI.
# Образ собирается при первом запуске.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi
export GIT_USER_NAME="${GIT_USER_NAME:-$(git config --get user.name 2>/dev/null || true)}"
export GIT_USER_EMAIL="${GIT_USER_EMAIL:-$(git config --get user.email 2>/dev/null || true)}"

IMAGE="$(docker compose config --images | head -n1)"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker compose build
fi

if [[ $# -eq 0 ]]; then
    exec docker compose run --rm box
else
    exec docker compose run --rm box "$@"
fi
