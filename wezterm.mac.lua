local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action
local config = wezterm.config_builder()

local function move_pane_with_wrap(window, pane, direction)
	local tab = window:active_tab()
	local panes = tab:panes_with_info()

	if #panes <= 1 then
		return
	end

	local current
	for _, item in ipairs(panes) do
		if item.pane:pane_id() == pane:pane_id() then
			current = item
			break
		end
	end
	if not current then
		return
	end

	local has_neighbor = false
	local target_pane

	if direction == "Left" then
		for _, item in ipairs(panes) do
			if item.left < current.left then
				has_neighbor = true
				break
			end
		end
		if has_neighbor then
			window:perform_action(act.ActivatePaneDirection("Left"), pane)
		else
			local max_left = -1
			for _, item in ipairs(panes) do
				if item.left > max_left then
					max_left = item.left
					target_pane = item.pane
				end
			end
		end
	elseif direction == "Right" then
		for _, item in ipairs(panes) do
			if item.left > current.left then
				has_neighbor = true
				break
			end
		end
		if has_neighbor then
			window:perform_action(act.ActivatePaneDirection("Right"), pane)
		else
			local min_left = math.huge
			for _, item in ipairs(panes) do
				if item.left < min_left then
					min_left = item.left
					target_pane = item.pane
				end
			end
		end
	elseif direction == "Up" then
		for _, item in ipairs(panes) do
			if item.top < current.top then
				has_neighbor = true
				break
			end
		end
		if has_neighbor then
			window:perform_action(act.ActivatePaneDirection("Up"), pane)
		else
			local max_top = -1
			for _, item in ipairs(panes) do
				if item.top > max_top then
					max_top = item.top
					target_pane = item.pane
				end
			end
		end
	elseif direction == "Down" then
		for _, item in ipairs(panes) do
			if item.top > current.top then
				has_neighbor = true
				break
			end
		end
		if has_neighbor then
			window:perform_action(act.ActivatePaneDirection("Down"), pane)
		else
			local min_top = math.huge
			for _, item in ipairs(panes) do
				if item.top < min_top then
					min_top = item.top
					target_pane = item.pane
				end
			end
		end
	end

	if target_pane then
		target_pane:activate()
	end
end

config.initial_cols = 200
config.initial_rows = 60

wezterm.on("gui-startup", function(cmd)
	local _, main_pane, window = mux.spawn_window(cmd or {})
	local right_pane = main_pane:split({
		direction = "Right",
		size = 20,
	})

	if right_pane then
		right_pane:split({
			direction = "Bottom",
			size = 30,
		})
	end

	main_pane:activate()
	window:gui_window():maximize()
end)

config.default_prog = { "/bin/zsh", "-l" }
config.font = wezterm.font("JetBrains Mono Nerd Font")
config.window_decorations = "RESIZE"
config.native_macos_fullscreen_mode = true
config.use_resize_increments = false
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = false
config.window_background_opacity = 0.85
config.macos_window_background_blur = 20
config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 1000 }

config.keys = {
	{ key = "]", mods = "LEADER|CTRL", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "\\", mods = "LEADER|CTRL", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "h", mods = "LEADER|CTRL", action = act.AdjustPaneSize({ "Left", 20 }) },
	{ key = "j", mods = "LEADER|CTRL", action = act.AdjustPaneSize({ "Down", 20 }) },
	{ key = "k", mods = "LEADER|CTRL", action = act.AdjustPaneSize({ "Up", 20 }) },
	{ key = "l", mods = "LEADER|CTRL", action = act.AdjustPaneSize({ "Right", 20 }) },
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
	{ key = "t", mods = "CTRL|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "n", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(1) },
	{ key = "z", mods = "CTRL", action = act.TogglePaneZoomState },
	{ key = "c", mods = "CTRL|SHIFT", action = act.ActivateCopyMode },
}

config.mouse_bindings = {
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "NONE",
		action = act.CompleteSelectionOrOpenLinkAtMouseCursor("Clipboard"),
	},
	{
		event = { Up = { streak = 2, button = "Left" } },
		mods = "NONE",
		action = act.CompleteSelection("Clipboard"),
	},
	{
		event = { Up = { streak = 3, button = "Left" } },
		mods = "NONE",
		action = act.CompleteSelection("Clipboard"),
	},
}

config.colors = {
	background = "#1a1c1d",
	foreground = "#d3c6aa",
	cursor_bg = "#a7c080",
	cursor_fg = "#1a1c1d",
	cursor_border = "#a7c080",
	selection_bg = "#425047",
	selection_fg = "#d3c6aa",
	ansi = {
		"#4a555b",
		"#e67e80",
		"#a7c080",
		"#dbbc7f",
		"#7fbbb3",
		"#d699b6",
		"#83c092",
		"#d3c6aa",
	},
	brights = {
		"#56635f",
		"#e67e80",
		"#a7c080",
		"#dbbc7f",
		"#7fbbb3",
		"#d699b6",
		"#83c092",
		"#d3c6aa",
	},
}

return config
