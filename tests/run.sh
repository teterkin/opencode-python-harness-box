#!/usr/bin/env bash
# Проверки бокса: AC1–AC10 из README. Запуск: bash tests/run.sh
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

expect_fail() {
    # Ожидает ненулевой код выхода (отказ валидации, а не сбой среды).
    local label="$1"; shift
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [[ "$rc" -ne 0 ]]; then
        ok "$label"
    else
        bad "$label (ожидал ненулевой rc, команда прошла: $*)"
    fi
}

box() { dc run --rm -T box sh -lc "$1"; }

probe_file() { printf '%s' "$ROOT_DIR/workspace/.ac-probe-$$"; }

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

HARNESS_AGENTS="$(box 'cat /opt/opencode-harness/AGENTS.md')"
check "AGENTS.md: правило 7 (пины)" "Pin every dependency" "$HARNESS_AGENTS"
check "AGENTS.md: напоминание про git init" "git init" "$HARNESS_AGENTS"

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
expect_ok "корень репо не смонтирован (нет /workspace/Dockerfile)" \
    box 'test ! -f /workspace/Dockerfile'
rm -f "$PROBE"

echo
echo "== AC5: env и ключ только в рантайме =="
check_eq "git user.name совпадает с хостом" "$HOST_GIT_NAME" "$(box 'git config --get user.name')"
check_eq "git user.email совпадает с хостом" "$HOST_GIT_EMAIL" "$(box 'git config --get user.email')"
if [[ -n "$HOST_KEY" ]]; then
    # shellcheck disable=SC2016  # переменная раскрывается в контейнере
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
# shellcheck disable=SC2016  # переменная раскрывается в контейнере
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
rm -rf "$ROOT_DIR/workspace/.venv-ac8"
dc down --remove-orphans >/dev/null 2>&1

echo
echo "== AC9: базовый тулчейн /opt/devtools =="
DEVTOOLS_PINS="$ROOT_DIR/requirements-devtools.txt"
expect_ok "requirements-devtools.txt существует" test -f "$DEVTOOLS_PINS"

for tool in pytest ruff mypy ipython; do
    expect_ok "$tool запускается" box "$tool --version"
    check "$tool в PATH — /opt/devtools" "/opt/devtools/bin/$tool" "$(box "command -v $tool" 2>/dev/null)"
done

FREEZE="$(box '/opt/devtools/bin/pip list --format=freeze' 2>/dev/null)"
while IFS= read -r req; do
    [[ -z "$req" || "$req" == \#* ]] && continue
    check "пин установлен: $req" "$req" "$FREEZE"
done < "$DEVTOOLS_PINS"

expect_ok "pytest --cov работает (pytest-cov)" \
    box 'mkdir -p /tmp/ac9 && printf "%s\n" "def test_ok():" "    assert True" > /tmp/ac9/test_ok.py && cd /tmp/ac9 && pytest --cov=. -q'
expect_ok "pytest -n auto работает (pytest-xdist)" \
    box 'mkdir -p /tmp/ac9 && printf "%s\n" "def test_ok():" "    assert True" > /tmp/ac9/test_ok.py && cd /tmp/ac9 && pytest -n auto -q'

expect_ok "ruff check и ruff format --check проходят на файле в /workspace" \
    box 'printf "x = 1\n" > /workspace/ac9_probe.py && ruff check /workspace/ac9_probe.py && ruff format --check /workspace/ac9_probe.py'
rm -f "$ROOT_DIR/workspace/ac9_probe.py"
dc down --remove-orphans >/dev/null 2>&1

echo
echo "== AC10: setup.sh и направления стека =="
AC10_VENV='/workspace/.venv-ac10'
expect_ok "setup.sh существует и исполняем на хосте" test -x "$ROOT_DIR/setup.sh"
# VENV_DIR указывает в несуществующее место: даже без guard'а скрипт на хосте
# уйдёт в быстрый отказ python3 -m venv, а не в установку пакетов.
HOST_OUT="$(VENV_DIR=/dev/null/x/.venv "$ROOT_DIR/setup.sh" ml 2>&1)"; HOST_RC=$?
if [[ "$HOST_RC" -ne 0 ]]; then
    ok "setup.sh на хосте отказывается работать"
else
    bad "setup.sh на хосте ушёл в установку (rc=0)"
fi
check "отказ подсказывает запуск через контейнер" "./run.sh setup.sh" "$HOST_OUT"
expect_ok "setup.sh --help читается на хосте" "$ROOT_DIR/setup.sh" --help
expect_ok "setup.sh смонтирован в контейнер" \
    box 'test -f /usr/local/bin/setup.sh && test -x /usr/local/bin/setup.sh'

MENU_OUT="$(box "VENV_DIR=$AC10_VENV setup.sh </dev/null" 2>&1)"; MENU_RC=$?
if [[ "$MENU_RC" -eq 0 ]]; then
    ok "без аргументов setup.sh печатает меню и завершается (rc=0)"
else
    bad "без аргументов setup.sh упал (rc=$MENU_RC: $(printf '%s' "$MENU_OUT" | tail -n 2 | tr '\n' ' | '))"
fi
check "меню перечисляет направления" "ml" "$MENU_OUT"
check "меню показывает текущее окружение" "Текущее окружение" "$MENU_OUT"
check_absent "в не-TTY цветов нет (вывод машиночитаем)" $'\033[' "$MENU_OUT"
check "FORCE_COLOR включает цвет" $'\033[' \
    "$(FORCE_COLOR=1 "$ROOT_DIR/setup.sh" --help 2>&1)"
check_absent "NO_COLOR гасит цвет даже при FORCE_COLOR" $'\033[' \
    "$(FORCE_COLOR=1 NO_COLOR=1 "$ROOT_DIR/setup.sh" --help 2>&1)"
expect_fail "неизвестное направление — отказ" box 'setup.sh no-such-direction'

expect_ok "setup.sh ml ставит пакеты" box "VENV_DIR=$AC10_VENV setup.sh ml"
for spec in 'numpy:NUMPY_VERSION' 'pandas:PANDAS_VERSION' 'sklearn:SKLEARN_VERSION'; do
    pkg="${spec%%:*}"; var="${spec##*:}"
    pin="$(grep -E "^${var}=" "$ROOT_DIR/setup.sh" | head -n1 | cut -d= -f2)"
    if [[ -z "$pin" ]]; then
        bad "пин $var не найден в setup.sh"
        continue
    fi
    check "$pkg по пину из setup.sh ($pin)" "$pin" \
        "$(box "$AC10_VENV/bin/python -c \"import $pkg; print($pkg.__version__)\"" 2>&1)"
done

GPU_OUT="$(box 'setup.sh gpu' 2>&1)"
check "gpu-направление отдаёт инструкцию по PyTorch" "pytorch" "$GPU_OUT"
check "gpu-направление отдаёт инструкцию по TensorFlow" "tensorflow" "$GPU_OUT"

rm -rf "$ROOT_DIR/workspace/.venv-ac10"
dc down --remove-orphans >/dev/null 2>&1

echo
printf 'итого провалено: %d\n' "$FAILED"
[[ "$FAILED" -eq 0 ]]
