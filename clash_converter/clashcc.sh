#!/usr/bin/env sh
set -euo pipefail

start() {
    if pgrep -x clash_conv >/dev/null; then
        pkill -x clash_conv
    fi
    command -v clash_conv >/dev/null || { echo "未找到 clash_conv 命令，请先安装" >&2; return 1; }
    (
        unset http_proxy https_proxy all_proxy ftp_proxy \
              HTTP_PROXY HTTPS_PROXY ALL_PROXY FTP_PROXY
        trap '' HUP
        exec clash_conv >/dev/null 2>&1
    ) &
}

stop() {
    pkill -x clash_conv && echo "clash_conv 已停止" || echo "clash_conv 未在运行"
}

case "${1:-}" in
    start) start ;;
    stop)  stop  ;;
    *)     start ;;
esac

