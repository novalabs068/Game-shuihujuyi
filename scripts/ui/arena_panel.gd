class_name ArenaPanel
extends Control
## 擂台：列出 10 关，打过的可以再打，下一关可以挑战，再往后的锁着。盖在场景上。

signal accepted(round: int)
signal closed

const INK := Color("1e1c1a")
const RED := Color("be3226")
const DIM := Color("5a4a3a")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	panel.custom_minimum_size = Vector2(900, 600)
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pad.add_child(v)
	var best := Arena.best()
	v.add_child(UiKit.brush_label("擂台　最高打到第 %d 关" % best, 34, INK))
	v.add_child(UiKit.label("一关一关往上打，每关第一次打赢有额外奖赏；打过的关可以再打，练练手。", 17, DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for n in range(1, Arena.round_count() + 1):
		var st := Arena.stage(n)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var num := UiKit.label("第 %d 关" % n, 22, RED if n == best + 1 else INK)
		num.custom_minimum_size.x = 90
		row.add_child(num)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		row.add_child(info)
		var names := PackedStringArray()
		for e in st.enemies:
			names.append(e.display_name)
		info.add_child(UiKit.label("%s　%d 级" % ["、".join(names), st.enemy_level], 20, INK))
		info.add_child(UiKit.label(("首胜奖赏：" + Arena.first_reward_text(n)) if n > best else "已打过", 15, DIM))
		var button: Button
		if n <= best:
			button = UiKit.button("再打", Vector2(110, 44), 20)
		elif n == best + 1:
			button = UiKit.button("挑战", Vector2(110, 44), 20)
		else:
			button = UiKit.button("未解锁", Vector2(110, 44), 18)
			button.disabled = true
		button.pressed.connect(func() -> void: accepted.emit(n))
		row.add_child(button)
	var close := UiKit.plaque_button("离　开", Vector2(170, 54), false, 26)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: closed.emit())
	v.add_child(close)
