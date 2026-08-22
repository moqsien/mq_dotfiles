#!/usr/bin/env sh
set -euo pipefail

start() {
    if pgrep -x clash_conv >/dev/null; then
        echo "clash_conv 已在运行"
        return 0
    fi
    command -v clash_conv >/dev/null || { echo "未找到 clash_conv 命令，请先安装" >&2; return 1; }
    ( trap '' HUP; exec clash_conv >/dev/null 2>&1 ) &
}

stop() {
    pkill -x clash_conv && echo "clash_conv 已停止" || echo "clash_conv 未在运行"
}

case "${1:-}" in
    start) start ;;
    stop)  stop  ;;
    *)     echo "用法: $0 {start|stop}" >&2; exit 1 ;;
esac
