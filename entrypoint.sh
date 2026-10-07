#!/usr/bin/env bash
# Рантайм-подготовка контейнера: git-идентичность из env -> /tmp/gitconfig.
# $HOME не-writable (AC6), поэтому конфиг git живёт во временной папке.

set -euo pipefail

GIT_CONFIG_FILE=/tmp/gitconfig
: > "$GIT_CONFIG_FILE"

if [[ -n "${GIT_USER_NAME:-}" ]]; then
    git config --file "$GIT_CONFIG_FILE" user.name "$GIT_USER_NAME"
fi
if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
    git config --file "$GIT_CONFIG_FILE" user.email "$GIT_USER_EMAIL"
fi
if [[ -s "$GIT_CONFIG_FILE" ]]; then
    export GIT_CONFIG_GLOBAL="$GIT_CONFIG_FILE"
fi

exec "$@"
