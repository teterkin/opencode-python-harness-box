#!/usr/bin/env bash
# Проверки бокса: AC1–AC8 из README. Запуск: bash tests/run.sh
# Нужен только Docker на хосте; всё остальное происходит в контейнере.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }

check() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        ok "$label"
    else
        bad "$label (ожидал: $expected)"
    fi
}

check_absent() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        ok "$label"
    else
        bad "$label (не ожидалось: $needle)"
    fi
}

check_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        ok "$label"
    else
        bad "$label (ожидал: [$expected], получено: [$actual])"
    fi
}

expect_ok() {
    local label="$1"; shift
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [[ "$rc" -eq 0 ]]; then
        ok "$label"
    else
        bad "$label (rc=$rc: $(printf '%s' "$out" | tail -n 3 | tr '\n' ' | '))"
    fi
}

expect_denied() {
    # Ожидает отказ прав доступа, а не любой ошибочный rc.
    local label="$1"; shift
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [[ "$rc" -ne 0 && "$out" == *"Permission denied"* ]]; then
        ok "$label"
    elif [[ "$rc" -eq 0 ]]; then
        bad "$label (команда неожиданно прошла: $*)"
    else
        bad "$label (не отказ прав доступа: $(printf '%s' "$out" | tail -n 1))"
    fi
}

dc() { (cd "$ROOT_DIR" && docker compose "$@"); }

box() { dc run --rm -T box sh -lc "$1"; }

probe_file() { printf '%s' "$ROOT_DIR/.ac-probe-$$"; }

# shellcheck disable=SC1091
[[ -f "$ROOT_DIR/.env" ]] && set -a && . "$ROOT_DIR/.env" && set +a
HOST_KEY="${OPENCODE_API_KEY:-}"
HOST_GIT_NAME="$(git config --global --get user.name 2>/dev/null || git config --get user.name 2>/dev/null)"
HOST_GIT_EMAIL="$(git config --global --get user.email 2>/dev/null || git config --get user.email 2>/dev/null)"
# Дефолты те же, что подставляет run.sh: git-идентичность хоста.
export GIT_USER_NAME="${GIT_USER_NAME:-$HOST_GIT_NAME}"
export GIT_USER_EMAIL="${GIT_USER_EMAIL:-$HOST_GIT_EMAIL}"

echo "== AC1: запуск на чистой машине =="
expect_ok "run.sh существует и исполняем" test -x "$ROOT_DIR/run.sh"
expect_ok "образ собирается" dc build
expect_ok "opencode запускается в контейнере" box 'opencode --version'

echo
echo "== AC2: харнесс подхватился =="
CONFIG="$(box 'opencode debug config')"
check "агент по умолчанию" '"default_agent": "implementer"' "$CONFIG"
SKILLS="$(box 'opencode debug skill')"
check "скилл tdd-workflow" "tdd-workflow" "$SKILLS"
check "скилл prd-authoring" "prd-authoring" "$SKILLS"

echo
echo "== AC3: тесты харнесса внутри контейнера =="
expect_ok "bash /opt/opencode-harness/tests/run.sh" \
    box 'bash /opt/opencode-harness/tests/run.sh'

echo
echo "== AC4: mount проекта виден на хосте =="
PROBE="$(probe_file)"
rm -f "$PROBE"
box "printf mounted > /workspace/$(basename "$PROBE")"
if [[ -f "$PROBE" ]]; then
    ok "файл, записанный в контейнере, виден на хосте"
else
    bad "файл из контейнера не появился на хосте: $PROBE"
fi
rm -f "$PROBE"

echo
echo "== AC5: env и ключ только в рантайме =="
check_eq "git user.name совпадает с хостом" "$HOST_GIT_NAME" "$(box 'git config --get user.name')"
check_eq "git user.email совпадает с хостом" "$HOST_GIT_EMAIL" "$(box 'git config --get user.email')"
if [[ -n "$HOST_KEY" ]]; then
    check_eq "OPENCODE_API_KEY доехал до контейнера" "$HOST_KEY" \
        "$(box 'printf %s "$OPENCODE_API_KEY"')"
fi
IMAGE="$(dc config --images 2>/dev/null | head -n1)"
IMAGE_ENV="$(docker image inspect --format '{{json .Config.Env}}' "$IMAGE" 2>/dev/null)"
IMAGE_HISTORY="$(docker history --no-trunc "$IMAGE" 2>/dev/null)"
if [[ -n "$IMAGE" && -n "$IMAGE_ENV" ]]; then
    check_absent "OPENCODE_API_KEY не в env образа" "OPENCODE_API_KEY" "$IMAGE_ENV"
    check_absent "OPENCODE_API_KEY не в слоях образа" "OPENCODE_API_KEY" "$IMAGE_HISTORY"
    if [[ -n "$HOST_KEY" ]]; then
        check_absent "значение ключа не в слоях образа" "$HOST_KEY" "$IMAGE_ENV$IMAGE_HISTORY"
    fi
else
    bad "образ не собран, проверка env образа невозможна (image=[$IMAGE])"
fi

echo
echo "== AC6: изоляция =="
check "контейнер не от root" "1000" "$(box 'id -u')"
expect_denied "запись в /etc неудачна" box 'touch /etc/.box-probe'
expect_denied "запись в \$HOME вне mount'ов неудачна" box 'touch "$HOME/.box-probe"'

echo
echo "== AC7: состояние переживает перезапуск =="
STATE='.local/share/opencode/.ac7-probe'
expect_ok "подготовка состояния" \
    box "mkdir -p \"\$HOME/$(dirname "$STATE")\" && printf v1 > \"\$HOME/$STATE\""
if dc down --remove-orphans >/dev/null 2>&1 && [[ -z "$(dc ps -a -q 2>/dev/null)" ]]; then
    ok "docker compose down останавливает среду"
else
    bad "docker compose down не остановил среду"
fi
check_eq "состояние пережило остановку" "v1" \
    "$(box "cat \"\$HOME/$STATE\"")"
expect_ok "запись после перезапуска" \
    box "printf v2 > \"\$HOME/$STATE\""
check_eq "запись после перезапуска читается" "v2" \
    "$(box "cat \"\$HOME/$STATE\"")"
box "rm -f \"\$HOME/$STATE\""

echo
echo "== AC8: python-dev окружение =="
expect_ok "python3 работает" box 'python3 --version'
expect_ok "pip работает" box 'python3 -m pip --version'
expect_ok "venv создаётся в /workspace" box 'python3 -m venv /workspace/.venv-ac8'
expect_ok "python из venv работает" box '/workspace/.venv-ac8/bin/python --version'
dc down --remove-orphans >/dev/null 2>&1
expect_ok "venv пережил перезапуск" box '/workspace/.venv-ac8/bin/python --version'
rm -rf "$ROOT_DIR/.venv-ac8"
dc down --remove-orphans >/dev/null 2>&1

echo
printf 'итого провалено: %d\n' "$FAILED"
[[ "$FAILED" -eq 0 ]]
