#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE='kcsm_demo.service'
BIN='/usr/local/bin/kcsm-watchdog-demo'
UNIT="/etc/systemd/system/${SERVICE}"
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

cleanup() {
    result=$?
    trap - EXIT
    echo
    echo '========== systemd journal =========='
    sudo journalctl -u "$SERVICE" --since "$START_TIME" --no-pager -n 100 || true
    sudo systemctl stop "$SERVICE" 2>/dev/null || true
    sudo rm -f "$UNIT" "$BIN"
    sudo systemctl daemon-reload || true
    exit "$result"
}
trap cleanup EXIT

get_pid() {
    systemctl show "$SERVICE" -p MainPID --value
}

get_restarts() {
    systemctl show "$SERVICE" -p NRestarts --value
}

wait_for_new_pid() {
    local old_pid="$1" pid
    for ((i=0; i<35; i++)); do
        pid="$(get_pid || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 && pid != old_pid )); then
            if systemctl is-active --quiet "$SERVICE"; then
                printf '%s\n' "$pid"
                return 0
            fi
        fi
        sleep 1
    done
    return 1
}

printf 'PID 1: '
ps -p 1 -o comm=
if [[ "$(ps -p 1 -o comm= | xargs)" != 'systemd' ]]; then
    echo 'ERROR: PID 1 is not systemd; use GitHub Actions ubuntu-24.04 VM.' >&2
    exit 1
fi

sudo apt-get update -qq
sudo apt-get install -y -qq gcc libsystemd-dev pkg-config

gcc -O2 -Wall -Wextra -std=c11 kcsm_demo.c -o kcsm-watchdog-demo \
    $(pkg-config --cflags --libs libsystemd)
sudo install -m 755 kcsm-watchdog-demo "$BIN"
sudo install -m 644 kcsm_demo.service "$UNIT"
sudo systemctl daemon-reload
sudo systemctl start "$SERVICE"

sleep 2
first="$(get_pid)"
[[ "$first" =~ ^[0-9]+$ ]] && ((first > 0)) || { echo 'Service did not start'; exit 1; }
echo "Normal service started: PID=$first, WatchdogUSec=$(systemctl show "$SERVICE" -p WatchdogUSec --value)"

# 模拟进程仍存活但不再向 systemd 发送 Watchdog 通知
sudo kill -USR1 "$first"
sleep 1
sudo kill -0 "$first"  # 此时进程应该仍存活
printf 'SIGUSR1 sent. The process is still alive, waiting for Watchdog timeout...\n'

second="$(wait_for_new_pid "$first")" || { echo 'FAIL: service did not recover from Hang'; exit 1; }
sleep 1
journal_text="$(sudo journalctl -u "$SERVICE" --since "$START_TIME" --no-pager -o cat)"
grep -Eiq "watchdog timeout|failed with result.*watchdog" <<< "$journal_text" || {
        echo 'FAIL: no systemd Watchdog timeout message found' >&2
        exit 1
    }
if (( $(get_restarts) < 1 )); then
    echo 'FAIL: no restart counted after Hang' >&2
    exit 1
fi
echo "PASS: Hang -> Watchdog timeout -> restart, PID $first -> $second"

# 模拟进程异常退出，验证无须等待 Watchdog 时间即可被重新启动
sudo kill -KILL "$second"
third="$(wait_for_new_pid "$second")" || { echo 'FAIL: service did not recover from Crash'; exit 1; }
if (( $(get_restarts) < 2 )); then
    echo 'FAIL: restart count did not increase after Crash' >&2
    exit 1
fi
echo "PASS: Crash -> restart, PID $second -> $third"
echo '========== ALL TESTS PASSED =========='
