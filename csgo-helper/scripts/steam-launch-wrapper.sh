#!/bin/bash
# Обёртка параметров запуска Steam для CSGO Helper.
#
# Рекомендуемые параметры запуска CS:GO legacy в Steam:
#   /Users/<вы>/Applications/csgo-helper-steam.sh %command%
#
# Обёртка один раз запускает установленный helper (если он ещё не работает),
# затем выполняет команду игры, переданную Steam. Она никогда не блокирует игру,
# если helper отсутствует или не смог запуститься.
set -u

APP="${CSGO_HELPER_APP:-$HOME/Applications/CSGOHelper.app}"
BINARY="$APP/Contents/MacOS/csgo-helper"
CONFIG="${CSGO_HELPER_CONFIG:-$HOME/Library/Application Support/CSGOHelper/config.json}"
LOG_DIR="$HOME/Library/Logs/CSGOHelper"
LOG="$LOG_DIR/steam-wrapper.log"

if [ "$#" -eq 0 ]; then
    echo "использование: $0 <команда игры...>" >&2
    exit 2
fi

mkdir -p "$LOG_DIR"
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] запуск обёртки; app=$APP"
} >>"$LOG" 2>&1

if [ ! -x "$BINARY" ]; then
    # Запасной dev-путь: обёртка рядом с каталогом build репозитория.
    here="$(cd "$(dirname "$0")" && pwd)"
    for candidate in \
        "$here/../build/CSGOHelper.app/Contents/MacOS/csgo-helper" \
        "$here/CSGOHelper.app/Contents/MacOS/csgo-helper" \
        "$here/../../build/CSGOHelper.app/Contents/MacOS/csgo-helper"
    do
        if [ -x "$candidate" ]; then
            BINARY="$candidate"
            APP="$(cd "$(dirname "$candidate")/../.." && pwd)"
            break
        fi
    done
fi

started=0
if pgrep -f "$BINARY" >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] helper уже запущен; используем его" >>"$LOG"
else
    if [ -x "$BINARY" ]; then
        if [ -d "$APP" ] && [ "$(basename "$APP")" = "CSGOHelper.app" ]; then
            # open привязывает разрешения TCC к бандлу .app (стабильный путь).
            /usr/bin/open -a "$APP" --args \
                --headless --config "$CONFIG" --wait-for-game --exit-on-game-exit \
                >>"$LOG" 2>&1
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] приложение запущено через open" >>"$LOG"
        else
            nohup "$BINARY" --headless --config "$CONFIG" --wait-for-game --exit-on-game-exit \
                >>"$LOG" 2>&1 &
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] бинарник запущен напрямую (dev fallback)" >>"$LOG"
        fi
        started=1
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] helper не найден; запускаем игру без него" >>"$LOG"
    fi
fi

# Дать helper время установить event tap до того, как игра получит фокус.
if [ "$started" -eq 1 ]; then
    sleep 0.4
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] запуск игры: $*" >>"$LOG"
exec "$@"
