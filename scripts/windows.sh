#!/bin/bash
# 1. 获取所有窗口的 JSON 数据
# 2. 提取 "ID: App名称 - 窗口标题" 格式
# 3. 传给 fuzzel (或 rofi) 让用户模糊搜索
# 4. 提取用户选择的 ID 并让 Niri 跳转

SELECTED=$(niri msg -j windows | jq -r '.[] | "\(.id): \(.app_id) - \(.title)"' | fuzzel --dmenu -l 10 -p "Jump to: ")

# 如果用户做出了选择（没有按 Esc 取消），则提取 ID 并跳转
if [ -n "$SELECTED" ]; then
    WINDOW_ID=$(echo "$SELECTED" | awk -F':' '{print $1}')
    niri msg action focus-window --id "$WINDOW_ID"
fi
