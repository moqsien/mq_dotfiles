local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action
local config = wezterm.config_builder()

-- ====================================================
-- 辅助函数：带边缘循环的面板切换 (Wrap-around Navigation)
-- ====================================================
local function move_pane_with_wrap(window, pane, direction)
	local tab = window:active_tab()
	local panes = tab:panes_with_info()

	-- 如果当前只有一个面板，不需要切换，直接返回
	if #panes <= 1 then
		return
	end

	-- 找到当前面板的坐标信息
	local current = nil
	for _, p in ipairs(panes) do
		if p.pane:pane_id() == pane:pane_id() then
			current = p
			break
		end
	end
	if not current then
		return
	end

	local has_neighbor = false
	local target_pane = nil

	if direction == "Left" then
		-- 检查左边是否还有面板
		for _, p in ipairs(panes) do
			if p.left < current.left then
				has_neighbor = true
				break
			end
		end
		if has_neighbor then
			window:perform_action(act.ActivatePaneDirection("Left"), pane)
		else
			-- 已经是最左边了，寻找 left 坐标最大（最右边）的面板
			local max_left = -1
			for _, p in ipairs(panes) do
				if p.left > max_left then
					max_left = p.left
					target_pane = p.pane
				end
			end
		end
	elseif direction == "Right" then
		-- 检查右边是否还有面板
		for _, p in ipairs(panes) do
			if p.left > current.left then
				has_neighbor = true
				break
			end
		end
		if has_neighbor then
			window:perform_action(act.ActivatePaneDirection("Right"), pane)
		else
			-- 已经是最右边了，寻找 left 坐标最小（最左边）的面板
			local min_left = 999999
			for _, p in ipairs(panes) do
				if p.left < min_left then
					min_left = p.left
					target_pane = p.pane
				end
			end
		end
	elseif direction == "Up" then
		-- 检查上面是否还有面板
		for _, p in ipairs(panes) do
			if p.top < current.top then
				has_neighbor = true
				break
			end
		end
		if has_neighbor then
			window:perform_action(act.ActivatePaneDirection("Up"), pane)
		else
			-- 已经是最上面了，寻找 top 坐标最大（最底下）的面板
			local max_top = -1
			for _, p in ipairs(panes) do
				if p.top > max_top then
					max_top = p.top
					target_pane = p.pane
				end
			end
		end
	elseif direction == "Down" then
		-- 检查下面是否还有面板
		for _, p in ipairs(panes) do
			if p.top > current.top then
				has_neighbor = true
				break
			end
		end
		if has_neighbor then
			window:perform_action(act.ActivatePaneDirection("Down"), pane)
		else
			-- 已经是最底下了，寻找 top 坐标最小（最顶上）的面板
			local min_top = 999999
			for _, p in ipairs(panes) do
				if p.top < min_top then
					min_top = p.top
					target_pane = p.pane
				end
			end
		end
	end

	-- 如果触发了边界循环切换，激活目标面板
	if target_pane then
		target_pane:activate()
	end
end

-- ====================================================
-- 1. 启动事件：自动全屏与 tmux 风格的初始分屏
-- ====================================================
config.initial_cols = 200
config.initial_rows = 60

wezterm.on("gui-startup", function(cmd)
	local tab, main_pane, window = mux.spawn_window(cmd or {})

	-- 1. 右边占 10%：总宽 200 列的 10% 就是 20 列
	local right_pane = main_pane:split({
		direction = "Right",
		size = 20,
	})

	if right_pane then
		-- 2. 右边上下各 50%：总高 60 行的 50% 就是 30 行
		right_pane:split({
			direction = "Bottom",
			size = 30,
		})
	end

	main_pane:activate()

	-- 3. 0.5 秒后 Niri 执行最大化时，窗口被瞬间拉满屏幕
	-- 此时 WezTerm 会将这 20列 和 30行 完美等比拉伸，永远保持 10% 和 50% 的比例！
	wezterm.background_child_process({
		"sh",
		"-c",
		"sleep 0.5 && niri msg action maximize-column",
	})
end)

-- wezterm.on("gui-startup", function(cmd)
-- 	local tab, main_pane, window = mux.spawn_window(cmd or {})
--
-- 	-- 【核心破局点 1：使用整数绝对值】
-- 	-- 绝对不能用 0.15 这种小数！Wayland 启动瞬间窗口像素是 0，算小数直接崩溃。
-- 	-- 直接传整数，代表“字符列数/行数”。WezTerm 在 0 像素时依然能分配出逻辑字符网格。
-- 	local right_pane = main_pane:split({
-- 		direction = "Right",
-- 		size = 40, -- 直接划出 40 个字符宽度的面板（千万不要加 {cells=}，直接写数字）
-- 	})
--
-- 	if right_pane then
-- 		right_pane:split({
-- 			direction = "Bottom",
-- 			size = 20, -- 直接划出 20 个字符高度的面板
-- 		})
-- 	end
--
-- 	main_pane:activate()
--
-- 	-- 【核心破局点 2：把最大化踢给系统 Shell】
-- 	-- 不要用 wezterm.time 去猜时间了。直接起一个脱离 WezTerm 控制的 Linux 后台进程。
-- 	-- 让 Shell 也就是 Bash 自己去睡 0.5 秒，等 WezTerm 彻底画出来后，一脚把 Niri 撑满。
-- 	wezterm.background_child_process({
-- 		"sh",
-- 		"-c",
-- 		"sleep 0.5 && niri msg action maximize-column",
-- 	})
-- end)

-- ====================================================
-- 2. 基础行为与 UI 外观 (深度复刻 tmux 体验)
-- ====================================================
-- 默认使用 zsh
config.default_prog = { "zsh", "-l" }

-- 保持纯血 Wayland 运行
config.enable_wayland = true

-- 禁用自己绘制的调整边缘，避免和 Niri 冲突
config.window_decorations = "NONE"

-- 允许非网格整数倍的无级缩放
config.use_resize_increments = false
-- 去除系统原生标题栏，保留拖拽边缘调整大小的能力
-- config.window_decorations = "RESIZE"

-- 打造 tmux 风格的底部极简 Tab 栏
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = false

-- 设置 85% 的不透明度
config.window_background_opacity = 0.85
-- macOS 用户开启毛玻璃模糊 (非 Mac 用户可删掉此行)
config.macos_window_background_blur = 20

-- 设置 Leader 键为 Ctrl+B (等待时间 1000ms)
config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 1000 }

-- copy mode
config.key_tables = {
	copy_mode = {
		-- ================= 你的自定义键位 =================
		{ key = "H", mods = "SHIFT", action = act.CopyMode("MoveToStartOfLine") },
		{ key = "L", mods = "SHIFT", action = act.CopyMode("MoveToEndOfLineContent") },
		{ key = "^", mods = "SHIFT", action = act.CopyMode("MoveToStartOfLineContent") },

		-- ================= 基础移动 (h/j/k/l) =================
		{ key = "h", action = act.CopyMode("MoveLeft") },
		{ key = "j", action = act.CopyMode("MoveDown") },
		{ key = "k", action = act.CopyMode("MoveUp") },
		{ key = "l", action = act.CopyMode("MoveRight") },

		-- ================= 单词移动 (w/b/e) =================
		{ key = "w", action = act.CopyMode("MoveForwardWord") },
		{ key = "b", action = act.CopyMode("MoveBackwardWord") },
		{ key = "e", action = act.CopyMode("MoveForwardWordEnd") },

		-- ================= 行首/行尾 (0/$) =================
		{ key = "0", action = act.CopyMode("MoveToStartOfLine") },
		{ key = "$", mods = "SHIFT", action = act.CopyMode("MoveToEndOfLineContent") },

		-- ================= 翻页 (Ctrl+u/d/b/f) =================
		{ key = "u", mods = "CTRL", action = act.CopyMode("PageUp") },
		{ key = "d", mods = "CTRL", action = act.CopyMode("PageDown") },
		{ key = "b", mods = "CTRL", action = act.CopyMode("PageUp") },
		{ key = "f", mods = "CTRL", action = act.CopyMode("PageDown") },

		-- ================= 顶部/底部 (g/G) =================
		{ key = "g", action = act.CopyMode("MoveToScrollbackTop") },
		{ key = "G", mods = "SHIFT", action = act.CopyMode("MoveToScrollbackBottom") },

		-- ================= 选择模式 (v/V/Ctrl+v) =================
		{ key = "v", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
		{ key = "V", mods = "SHIFT", action = act.CopyMode({ SetSelectionMode = "Line" }) },
		{ key = "v", mods = "CTRL", action = act.CopyMode({ SetSelectionMode = "Block" }) },

		-- ================= 复制与退出 (y/Esc) =================
		{ key = "y", action = act.CopyTo("ClipboardAndPrimarySelection") },
		{ key = "p", action = act.Multiple({
			act.PasteFrom("Clipboard"),
			act.CopyMode("Close"),
		}) },
		{ key = "Escape", action = act.CopyMode("Close") },
		{ key = "q", action = act.CopyMode("Close") },

		-- ================= 搜索功能 =================
		{ key = "/", action = act.CopyMode("EditPattern") },
		{ key = "n", action = act.CopyMode("NextMatch") },
		{ key = "N", mods = "SHIFT", action = act.CopyMode("PriorMatch") },
	},
	-- ================= 新增：搜索输入模式 (search_mode) =================
	search_mode = {
		-- 按 Enter 确认搜索词，并返回到 copy_mode (这样 n/N 才能生效)
		{ key = "Enter", action = act.CopyMode("AcceptPattern") },

		-- 按 Esc 直接退出整个 Copy Mode (可选)
		{ key = "Escape", action = act.CopyMode("Close") },
	},
}

-- ====================================================
-- 3. 快捷键配置 (Key Bindings)
-- ====================================================
config.keys = {

	-- 【面板分割 (Splits)】
	-- 对应: bind -r C-] split-window -h
	{ key = "]", mods = "LEADER|CTRL", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	-- 对应: bind -r C-\ split-window -v
	{ key = "\\", mods = "LEADER|CTRL", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

	-- 【调整面板大小 (Resize Panes)】
	-- 对应: bind -r C-h/j/k/l resize-pane -L/D/U/R 5
	{ key = "h", mods = "LEADER|CTRL", action = act.AdjustPaneSize({ "Left", 20 }) },
	{ key = "j", mods = "LEADER|CTRL", action = act.AdjustPaneSize({ "Down", 20 }) },
	{ key = "k", mods = "LEADER|CTRL", action = act.AdjustPaneSize({ "Up", 20 }) },
	{ key = "l", mods = "LEADER|CTRL", action = act.AdjustPaneSize({ "Right", 20 }) },

	-- 【选择面板 (Select Panes) - 无需 Leader 键】
	-- 对应: bind -n C-h select-pane -L  |  bind -n C-k select-pane -U
	{
		key = "h",
		mods = "CTRL",
		action = wezterm.action_callback(function(win, pane)
			move_pane_with_wrap(win, pane, "Left")
		end),
	},
	{
		key = "k",
		mods = "CTRL",
		action = wezterm.action_callback(function(win, pane)
			move_pane_with_wrap(win, pane, "Up")
		end),
	},

	-- 【窗口/标签页管理 (Windows/Tabs) - 无需 Leader 键】
	-- 对应: bind-key -n C-S-t new-window -c "#{pane_current_path}"
	{ key = "t", mods = "CTRL|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
	-- 对应: bind-key -n C-S-n next-window
	{ key = "n", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(1) },

	-- 【最大化/缩放面板 (Zoom) - 无需 Leader 键】
	-- 对应: bind-key -n C-z resize-pane -Z
	{ key = "z", mods = "CTRL", action = act.TogglePaneZoomState },

	-- 【进入复制模式 (Copy Mode) - 无需 Leader 键】
	-- 对应: bind -n C-S-c copy-mode
	{ key = "c", mods = "CTRL|SHIFT", action = act.ActivateCopyMode },
}

-- 设置鼠标绑定：选中即复制到系统剪贴板（并在点击链接时打开它）
-- 设置鼠标绑定：选中即复制到系统剪贴板（并在点击链接时打开它）
config.enable_wayland = true

config.mouse_bindings = {
	-- 1. 单次点击拖拽松开
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "NONE",
		-- 删除了 PrimarySelection，只保留纯系统剪贴板
		action = act.CompleteSelectionOrOpenLinkAtMouseCursor("Clipboard"),
	},
	-- 2. 双击选中单词并松开
	{
		event = { Up = { streak = 2, button = "Left" } },
		mods = "NONE",
		action = act.CompleteSelection("Clipboard"),
	},
	-- 3. 三击选中整行并松开
	{
		event = { Up = { streak = 3, button = "Left" } },
		mods = "NONE",
		action = act.CompleteSelection("Clipboard"),
	},
}

-- config.color_scheme = "Everforest Dark Medium (Gogh)"
config.colors = {
	-- 【极致黑背景】从 #272e33 进一步加深到 #1a1c1d，彻底消除灰色雾感
	background = "#1a1c1d",
	-- 【高亮前景色】文字稍微调亮到 #d3c6aa，在黑背景下极其锐利
	foreground = "#d3c6aa",

	cursor_bg = "#a7c080",
	cursor_fg = "#1a1c1d",
	cursor_border = "#a7c080",

	-- 【选中区域】加大对比，让选中的文字一眼就能看清
	selection_bg = "#425047",
	selection_fg = "#d3c6aa",

	-- 【鲜艳 ANSI 色彩】使用最鲜艳的色彩库，确保图标和文字颜色不再“灰暗”
	ansi = {
		"#4a555b", -- 0: 黑
		"#e67e80", -- 1: 红
		"#a7c080", -- 2: 绿 (更有活力的森林绿)
		"#dbbc7f", -- 3: 黄
		"#7fbbb3", -- 4: 蓝
		"#d699b6", -- 5: 品红
		"#83c092", -- 6: 青
		"#d3c6aa", -- 7: 白
	},
	brights = {
		"#56635f", -- 8: 亮黑
		"#e67e80",
		"#a7c080",
		"#dbbc7f",
		"#7fbbb3",
		"#d699b6",
		"#83c092",
		"#d3c6aa",
	},
}

-- config.font = wezterm.font("JetBrainsMono Nerd Font")
config.font = wezterm.font("MesloLGS Nerd Font")
config.font_size = 12.0

-- 开启 kitty 键盘协议：让终端能把 Ctrl+Shift+O 等组合键与 Ctrl+O 区分开，
-- Neovim 0.10+ 检测到终端支持后会自动启用增强键盘处理。
config.enable_kitty_keyboard = true

return config
