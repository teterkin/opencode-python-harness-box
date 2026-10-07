#!/usr/bin/env bash
# Запустить opencode с харнессом в контейнере.
# Аргументы уходят в контейнер: ./run.sh bash — шелл вместо TUI.
# Образ собирается при первом запуске.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

IMAGE="$(docker compose config --images | head -n1)"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker compose build
fi

if [[ $# -eq 0 ]]; then
    exec docker compose run --rm box
else
    exec docker compose run --rm box "$@"
fi
