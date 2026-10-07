# opencode-python-harness-box

> **Статус: реализовано (`1.2.0`).** Все AC зелёные: `bash tests/run.sh` →
> `итого провалено: 0`. Ниже — описание, зафиксированные решения и журнал
> изменений.

opencode с харнессом TDD/PRD-разработки, запущённый внутри контейнера с
Python-окружением разработки. Окружение воспроизводимо у всех участников
команды, а команды агента изолированы от хоста: `bash: *: allow` действует
внутри контейнера, а не на ноутбуке.

**Одна строка (для GitHub description):**

> Reproducible, sandboxed opencode environment with the TDD/PRD harness baked
> in — Python dev container edition.

## Зачем

- `git clone` + `./run.sh` на чистой машине с Docker даёт opencode с харнессом
  без установки opencode и python3 на хост.
- Одинаковое окружение у всей команды: те же версии, тот же харнесс, те же
  инструменты.
- Агент физически не может выполнить опасную команду на хосте: всё, что он
  делает, происходит в контейнере, а запись вне смонтированных каталогов
  запрещена правами.

Не является: дистрибутивом харнесса (он только потребляется), docker-in-docker,
GUI/десктоп-вариантом opencode, решением для multi-user/удалённого доступа.

## Требования к хосту

Нужны только Docker (с Compose v2), bash и git. opencode, python3 и прочие
инструменты на хост ставить не нужно — всё живёт в контейнере.

- **bash** — `run.sh`, `tests/run.sh`. Проверка: `bash --version`. macOS и
  Linux — из коробки.
- **Docker Engine + Compose v2** — сборка и запуск бокса. Проверка:
  `docker --version && docker compose version`, а `docker info` должен
  выводить версию сервера, а не ошибку подключения (демон запущен).
  Установка: macOS — `brew install --cask docker` (Docker Desktop),
  Linux — <https://docs.docker.com/engine/install/>.
- **git** — клонирование и дефолтная git-идентичность для контейнера.
  Проверка: `git --version`. macOS — `xcode-select --install`,
  Linux — `apt install git`.
- **shellcheck** *(необязательно)* — линтер шелл-скриптов. Проверка:
  `shellcheck --version`; macOS — `brew install shellcheck`,
  Linux — `apt install shellcheck`. Прогон:
  `shellcheck run.sh entrypoint.sh tests/run.sh` (ноль замечаний).

## Связь с opencode-harness

Структурной связи нет — только потребление:

- Источник правды — <https://github.com/teterkin/opencode-harness> (публичный).
- На сборке образа Dockerfile клонирует репо с пином по коммиту
  (`HARNESS_REF`, на момент планирования — `78452bf1`). Ни сабмодуля, ни форка,
  ни вендоринга. Локальная копия рядом с боксом — только для справки, в сборку
  не входит.
- Единственный контракт — `install.sh` харнесса. Если он сломается на новом
  `main`, это покажет AC3 (тесты самого харнесса внутри контейнера), а не тихая
  поломка.

## Acceptance criteria

1. `git clone` + `./run.sh` (или `docker compose up`) на чистой машине с Docker
   поднимает opencode с харнессом без предустановки opencode и python3 на хосте.
2. Внутри контейнера `opencode debug config` показывает
   `default_agent: implementer`, `opencode debug skill` — скиллы
   `tdd-workflow` и `prd-authoring` (харнесс подхватился).
3. `tests/run.sh` харнесса проходит внутри контейнера (Linux — закрытое
   «не проверено» из README харнесса).
4. Рабочий каталог проекта монтируется в контейнер, изменения файлов видны на
   хосте.
5. Git-идентификация (`user.name`/`user.email`) и API-ключ провайдера
   передаются с хоста, ключ не попадает в слои образа.
6. Агент внутри контейнера не может писать вне смонтированных каталогов
   (попытка записи в `/etc` или в `$HOME` вне mount'ов неудачна; выполняется
   не от root).
7. `docker compose down` останавливает среду, состояние opencode (история
   сессий) переживает перезапуск через volume.
8. Python-dev окружение: `python3`, `pip`, `venv` работают внутри контейнера,
   `venv` в смонтированном каталоге переживает перезапуск.
9. Базовый тулчейн установлен в образ с версионными пинами
   (`requirements-devtools.txt`): `pytest`, `ruff`, `mypy`, `ipython` доступны
   из `/opt/devtools`, плагины `pytest --cov` и `pytest -n auto` работают,
   `ruff check` и `ruff format --check` проходят на файле в `/workspace`.
   Каждый пин из файла присутствует в контейнере ровно в зафиксированной версии.

## Зафиксированные решения (ex open questions)

1. **Docker-клиент: ни сокета, ни dind.** docker в контейнер не ставится.
   Приоритет — изоляция (AC6); docker-сборки делаются на хосте. Возможный
   compose-profile с сокетом — вне этого проекта.
2. **Харнесс ставится при сборке образа**, пин по коммиту (`HARNESS_REF`).
   Свежий харнесс = пересборка с новым пином. Клон остаётся в
   `/opt/opencode-harness` — оттуда гоняются его тесты (AC3).
3. **Ключи и идентификация — env через `.env`** (в `.gitignore`).
   `OPENCODE_API_KEY` передаётся только в рантайме, в слои образа не попадает
   (проверяется тестом). Git: `GIT_USER_NAME` / `GIT_USER_EMAIL`, дефолты
   `run.sh` берёт из `git config` хоста; `$HOME` в контейнере не-writable
   (требование AC6), поэтому entrypoint пишет gitconfig в `/tmp` и выставляет
   `GIT_CONFIG_GLOBAL`.
4. **База — `ubuntu:24.04`** (python3 3.12 из коробки) + основные инструменты
   Python-разработки: `python3`, `python3-venv`, `python3-pip`,
   `python3-dev`, `build-essential`, `git`, `make`, `curl`, `ca-certificates`,
   `ripgrep`, `jq`. Зависимости проекта — в venv в смонтированном
   `/workspace/.venv` (живёт на хосте); pip-кэш — tmpfs. Версия opencode
   пинится (`OPENCODE_VERSION`, на момент планирования — `1.18.34`),
   обновление — через `--build-arg`.
5. **TUI — обычный `docker compose run -it`** через `run.sh`. tmux и
   переподключение к отвалившейся сессии — вне scope: история сессий и так
   живёт в volume.
6. **Рабочий каталог — только подпапка `workspace/`**, не корень репозитория:
   `./workspace:/workspace`. Проектный `AGENTS.md` берётся оттуда же; конфиг
   харнесса — в образе, не в volume. `workspace/*` в `.gitignore` (в коммит
   идёт только `.gitkeep`), чтобы код проекта не смешивался с кодом бокса.
7. **Базовый тулчейн — отдельный venv `/opt/devtools`, состав зафиксирован.**
   Служебные инструменты (pytest, ruff, mypy, ipython) не смешиваются ни с
   системным python3, ни с venv проекта: свой каталог, свои пины. Владелец —
   root, поэтому box туда ничего не доустановит: изменение состава = правка
   `requirements-devtools.txt` + пересборка образа. `/opt/devtools/bin` стоит
   в `PATH` последним — `python3` и `pip` остаются системными, а инструменты
   доступны как обычные команды. Пины — полный `pip freeze`, не только
   верхнеуровневые: свежий resolve транзитивных зависимостей в чужой
   сборке — это шанс получить несовместимые версии. Обновление — изолированной
   правкой пина с прогоном тестов.

## Архитектура

```
Dockerfile            ubuntu:24.04 + apt-пакеты + venv /opt/devtools (пины)
                      + opencode (пин) + clone харнесса (пин) + install.sh;
                      пользователь box (uid 1000), $HOME принадлежит root
                      и не-writable для box; volume-точка
                      ~/.local/share/opencode, ~/.cache — tmpfs
entrypoint.sh         пишет /tmp/gitconfig из GIT_USER_NAME/GIT_USER_EMAIL,
                      выставляет GIT_CONFIG_GLOBAL, exec "$@"
docker-compose.yml    tty/stdin, bind-mount ./workspace -> /workspace,
                      named volume состояния, env-прокидка
run.sh                сборка при первом запуске, дефолты git-идентичности
                      с хоста, docker compose run --rm
tests/run.sh          проверки AC1-AC9 в стиле тестов харнесса
                      (bash, check/FAIL)
requirements-devtools.txt  полный pip freeze тулчейна /opt/devtools
.env.example          OPENCODE_API_KEY, GIT_USER_NAME, GIT_USER_EMAIL
.gitignore            .env, workspace/* (кроме .gitkeep)
workspace/            рабочая папка проекта — единственное, что смонтировано
```

## Состав образа

Четыре бандла, всё с версионными пинами — окружение одинаковое у всей команды.

### 1. Системный слой (apt)

Основа — `ubuntu:24.04`, `python3` 3.12 из коробки.

| Пакет | Назначение |
|---|---|
| `python3` | интерпретатор системного python |
| `python3-venv` | создание venv в `/workspace/.venv` (AC8) |
| `python3-pip` | pip для системного python (PEP 668: в систему не ставит, только в venv) |
| `python3-dev` | заголовочные файлы Python — для сборки C-расширений |
| `build-essential` | компилятор и линковщик — для пакетов с C/C++-компонентом |
| `git` | клон харнесса и git внутри бокса |
| `make` | запуск `Makefile` проекта |
| `curl` | скачивание установщика opencode |
| `ca-certificates` | корневые сертификаты для HTTPS |
| `ripgrep` | быстрый поиск по коду для агента |
| `jq` | работа с JSON в скриптах и проверках |

### 2. Базовый тулчейн — `/opt/devtools` (venv, пины)

Отдельный venv, владелец root; `/opt/devtools/bin` в конце `PATH`.

| Инструмент | Назначение |
|---|---|
| `pytest==9.1.1` | запуск тестов |
| `pytest-cov==7.1.0` | `pytest --cov` — отчёт о покрытии |
| `pytest-xdist==3.8.0` | `pytest -n auto` — распараллеливание тестов |
| `ruff==0.16.10` | линт и формат: `ruff check`, `ruff format --check` |
| `mypy==2.4.0` | проверка типов |
| `ipython==9.17.1` | интерактивный REPL |

Остальные строки `requirements-devtools.txt` — транзитивные зависимости,
снятые `pip list --format=freeze` после сборки. Файл проверяется тестом
(AC9): каждый пин обязан присутствовать в контейнере.

### 3. opencode

`OPENCODE_VERSION=1.18.34` — CLI агента, официальный установочный скрипт,
версия проверяется после установки. Обновление — `--build-arg`.

### 4. opencode-harness

`HARNESS_REF=78452bf1` — агент `implementer`, скиллы `tdd-workflow` и
`prd-authoring`, правила TDD/PRD. `install.sh` кладёт конфиг в
`~/.config/opencode`; сам клон остаётся в `/opt/opencode-harness` (оттуда
идёт AC3).

### Пока не входит в образ

Зависимости самого проекта (ml-направление: numpy, pandas, scikit-learn, и
всё остальное) ставятся не в образ, а в venv проекта на смонтированном
`/workspace/.venv` — планеруется `setup.sh` с интерактивным меню направлений.

## Журнал изменений

Версии и связанные коммиты. Каждый цикл TDD — один коммит и одна запись.

| Версия | Что | Коммит |
|---|---|---|
| `0.1.0` | README (этот файл), скелет тестов AC — RED | `da6a189` |
| `0.2.0` | Контейнер: python-dev + opencode + харнесс (AC1–AC3) | `87ddc1d` |
| `0.3.0` | Изоляция: не-root, запись вне mount'ов запрещена (AC6) | `6575ff4` |
| `0.4.0` | Bind-mount, env-ключи, git-идентичность, volume (AC4, AC5, AC7, AC8) | `f05bedf`, `9fb2dbe` |
| `1.0.0` | Все AC зелёные, финальный прогон | `351feaf` |
| `1.1.0` | Mount только `workspace/`, корень репо не виден в контейнере (TDD3) | `9e6db68` |
| `1.2.0` | Тулчейн `/opt/devtools` c полным freeze, AC9, состав образа в README (TDD1) | — |

## Открытые пункты

- **SSH из контейнера** — ключи хоста не монтируются (осознанная изоляция),
  `git push` по ssh из бокса работать не будет; только https. Если понадобится
  иначе — mount `~/.ssh` как компромисс, отдельным решением.

## Разработка

Тесты бокса: `bash tests/run.sh`. Линтер: `shellcheck run.sh entrypoint.sh
tests/run.sh`. Цикл: RED — один падающий AC-тест, показать вывод; GREEN —
минимальная правка, показать вывод; REFACTOR — при зелёных тестах.
Коммит — один на цикл.
