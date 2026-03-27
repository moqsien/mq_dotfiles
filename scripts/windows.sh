#!/bin/bash
# 1. 获取所有窗口的 JSON 数据
# 2. 提取 "ID: App名称 - 窗口标题" 格式
# 3. 传给 fuzzel (或 rofi) 让用户模糊搜索
# 4. 提取用户选择的 ID 并让 Niri 跳转

# 1. 检查 fuzzel 是否已经在运行
if pgrep -x "fuzzel" > /dev/null; then
    # 如果在运行，则杀掉进程并直接退出（实现 Toggle 关闭效果）
    pkill -x "fuzzel"
    exit 0
fi

# 2. 获取窗口列表并传递给 fuzzel
# 注意：这里增加了 --non-interactive 或确保它能正常退出
SELECTED=$(niri msg -j windows | jq -r '.[] | "\(.id): \(.app_id) - \(.title)"' | fuzzel --dmenu -l 10 -p "Jump to: ")

# 3. 如果用户选择了窗口，则跳转
if [ -n "$SELECTED" ]; then
    WINDOW_ID=$(echo "$SELECTED" | awk -F':' '{print $1}')
    niri msg action focus-window --id "$WINDOW_ID"
fi
