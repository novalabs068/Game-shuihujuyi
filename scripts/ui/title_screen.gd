class_name TitleScreen
extends Control
## 开始界面：新游戏 / 继续游戏。背景用江湖大地图。

signal new_game_requested
signal continue_requested


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = GameDB.maps[GameState.DEFAULT_MAP].texture
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0.94, 0.9, 0.83, 0.6)
	add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title := UiKit.label("水浒聚义", 96, Color("1e1c1a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.94, 0.9, 0.83))
	v.add_child(title)
	var sub := UiKit.label("一人一刀，闯荡水浒江湖", 28, Color("5a3a2a"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_constant_override("outline_size", 8)
	sub.add_theme_color_override("font_outline_color", Color(0.94, 0.9, 0.83))
	v.add_child(sub)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(buttons)
	var resume := UiKit.button("继续游戏", Vector2(280, 72), 30)
	resume.disabled = not GameState.has_save()
	resume.pressed.connect(func() -> void: continue_requested.emit())
	buttons.add_child(resume)
	var fresh := UiKit.button("新游戏", Vector2(280, 72), 30)
	fresh.pressed.connect(func() -> void: new_game_requested.emit())
	buttons.add_child(fresh)
	if GameState.has_save():
		var note := UiKit.label("新游戏会覆盖现在的存档（%s）" % GameState.player_name, 18, Color("5a3a2a"))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buttons.add_child(note)
