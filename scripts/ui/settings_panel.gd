class_name SettingsPanel
extends Control
## 设置：音乐开关和音量、战斗默认 2 倍速、震动开关、重新开始（要点两次确认）。盖在大地图或开始界面上。

signal closed
## 玩家确认清空存档、从头开始
signal restart_requested

## 在开始界面打开时没有存档可清，不显示「重新开始」
var allow_restart := true

## 鸣谢：CC-BY 授权要求写明作者、曲名和授权（素材都从 OpenGameArt、Kenney 来）
const CREDITS := "鸣谢　战斗配乐：Blackmoor Ninjas（Matthew Pablo，CC-BY 3.0）、Drums of Dawn（magnesus，CC-BY 3.0）、Samurai（tad，CC-BY 4.0），均来自 OpenGameArt.org。战斗音效录音：Kenney（CC0）。字体：思源宋体 Noto Serif SC、马善政毛笔楷书 Ma Shan Zheng（均为 SIL OFL 1.1）。"

var _restart: Button
var _armed := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)
	v.add_child(UiKit.brush_label("设置", 36, UiKit.INK))

	var music := CheckButton.new()
	music.text = "背景音乐"
	music.add_theme_font_size_override("font_size", 20)
	music.button_pressed = Music.enabled
	music.toggled.connect(func(on: bool) -> void: Music.enabled = on)
	v.add_child(music)

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 16)
	v.add_child(volume_row)
	volume_row.add_child(UiKit.label("音乐音量", 20, UiKit.INK))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Music.volume
	slider.custom_minimum_size = Vector2(360, 40)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void: Music.volume = value)
	volume_row.add_child(slider)

	var sfx := CheckButton.new()
	sfx.text = "音效"
	sfx.add_theme_font_size_override("font_size", 20)
	sfx.button_pressed = Sfx.enabled
	sfx.toggled.connect(func(on: bool) -> void:
		Sfx.enabled = on
		Sfx.play(&"ui_click"))
	v.add_child(sfx)
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 16)
	v.add_child(sfx_row)
	sfx_row.add_child(UiKit.label("音效音量", 20, UiKit.INK))
	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = Sfx.volume
	sfx_slider.custom_minimum_size = Vector2(300, 40)
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.drag_ended.connect(func(_changed: bool) -> void: Sfx.play(&"hit_slash"))
	sfx_slider.value_changed.connect(func(value: float) -> void: Sfx.volume = value)
	sfx_row.add_child(sfx_slider)

	var fast := CheckButton.new()
	fast.text = "战斗默认 2 倍速"
	fast.add_theme_font_size_override("font_size", 20)
	fast.button_pressed = Prefs.get_value("battle", "fast", false)
	fast.toggled.connect(func(on: bool) -> void: Prefs.set_value("battle", "fast", on))
	v.add_child(fast)

	var vibrate := CheckButton.new()
	vibrate.text = "震动（招募等时候手机震一下）"
	vibrate.add_theme_font_size_override("font_size", 20)
	vibrate.button_pressed = Haptics.enabled()
	vibrate.toggled.connect(func(on: bool) -> void:
		Haptics.set_enabled(on)
		Haptics.pulse(Haptics.Level.MEDIUM))
	v.add_child(vibrate)

	if allow_restart:
		_restart = UiKit.button("重新开始", Vector2(220, 48), 22)
		_restart.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_restart.pressed.connect(_on_restart)
		v.add_child(_restart)

	v.add_child(UiKit.label("《水浒聚义》 版本 %s　单机离线，没有任何付费" % UiKit.version(), 15, UiKit.INK_DIM))
	var credits := UiKit.label(CREDITS, 13, UiKit.INK_DIM)
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.custom_minimum_size.x = 560
	v.add_child(credits)
	var close := UiKit.plaque_button("返　回", Vector2(170, 54), false, 26)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: closed.emit())
	v.add_child(close)


## 第一次点只是提醒，再点一次才真的清空存档。
func _on_restart() -> void:
	if not _armed:
		_armed = true
		_restart.text = "清空存档？再点一次确认"
		_restart.add_theme_color_override("font_color", Color("ff8a6a"))
		return
	restart_requested.emit()
