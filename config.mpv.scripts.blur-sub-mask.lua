-- sub-blur-pro.lua (修正版：修复语法截断与滤镜堆叠问题)
local msg = require("mp.msg")

local is_masked = false
local mask_y_pct = 0.85 -- 初始垂直位置：距顶部 85%
local mask_h_pct = 0.15 -- 初始高度：占屏幕 15%
local blur_radius = 15 -- 模糊强度，可修改为 10(轻微) 或 25(极糊)

function update_mask()
	-- 无论如何先尝试移除旧滤镜，防止调整尺寸时滤镜重复堆叠导致失效
	pcall(function()
		mp.commandv("vf", "remove", "@submask")
	end)

	if not is_masked then
		return
	end

	-- 安全限制，防止滤镜面积越界导致播放器报错崩溃
	if mask_y_pct < 0 then
		mask_y_pct = 0
	end
	if mask_y_pct > 0.99 then
		mask_y_pct = 0.99
	end
	if mask_h_pct < 0.01 then
		mask_h_pct = 0.01
	end
	if mask_y_pct + mask_h_pct > 1 then
		mask_h_pct = 1 - mask_y_pct
	end

	-- 构建 lavfi 滤镜图
	local graph = string.format(
		"[split[m][b];[b]crop=w=iw:h=ih*%f:x=0:y=ih*%f,boxblur=%d[blurred];[m][blurred]overlay=x=0:y=H*%f]",
		mask_h_pct,
		mask_y_pct,
		blur_radius,
		mask_y_pct
	)

	-- 使用 commandv 进行安全的参数传递
	mp.commandv("vf", "add", "@submask:lavfi=" .. graph)
end

function toggle_mask()
	is_masked = not is_masked
	update_mask()
	if is_masked then
		mp.osd_message("毛玻璃遮罩: 开启")
	else
		mp.osd_message("毛玻璃遮罩: 关闭")
	end
end

-- 调整位置
function adjust_y(delta)
	mask_y_pct = mask_y_pct + delta
	if is_masked then
		update_mask()
	end
	mp.osd_message(string.format("毛玻璃位置: 距顶部 %d%%", math.floor(mask_y_pct * 100)))
end

-- 调整高度
function adjust_h(delta)
	mask_h_pct = mask_h_pct + delta
	if is_masked then
		update_mask()
	end
	mp.osd_message(string.format("毛玻璃高度: 占屏幕 %d%%", math.floor(mask_h_pct * 100)))
end

-- 绑定快捷键
mp.add_key_binding("b", "toggle_sub_blur", toggle_mask)

mp.add_key_binding("Ctrl+UP", "blur_move_up", function()
	adjust_y(-0.02)
end)
mp.add_key_binding("Ctrl+DOWN", "blur_move_down", function()
	adjust_y(0.02)
end)

mp.add_key_binding("Alt+UP", "blur_taller", function()
	adjust_h(0.02)
end)
mp.add_key_binding("Alt+DOWN", "blur_shorter", function()
	adjust_h(-0.02)
end)
