class_name TitleScreen
extends Control
## 开始界面：新游戏 / 继续游戏。背景是一幅梁山泊水墨（崖上一面「替天行道」杏黄旗），左边留白处竖排大标题和按钮。

signal new_game_requested
signal continue_requested

## 开始画面背景：梁山泊水墨，崖上一面空白的杏黄旗（见 art/prompts/title_bg.txt）
const BG_TEXTURE := "res://art/ui/title_bg.jpg"
## 旗面上写「替天行道」：按背景原图像素，右一行「替天」、左一行「行道」的中线横坐标，字顶、字号
const FLAG_COLUMNS := [["替天", 1213.0], ["行道", 1167.0]]
const FLAG_TEXT_TOP := 138.0
const FLAG_TEXT_SIZE := 42.0


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = load(BG_TEXTURE)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 旗面上的「替天行道」：画里的旗是空白的，字叠上去，墨色略透，像写在旗上。
	# 位置按背景算（背景铺满会按屏幕宽窄缩放裁切），换了屏幕比例也落在旗面上。
	var flag_text: Array[Label] = []
	for col: Array in FLAG_COLUMNS:
		var l := UiKit.brush_label(UiKit.vertical_text(col[0]), int(FLAG_TEXT_SIZE), Color(0.1, 0.06, 0.04, 0.85))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("line_spacing", -int(FLAG_TEXT_SIZE * 0.3))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		flag_text.append(l)
	var place_text := func() -> void:
		var tex_size: Vector2 = bg.texture.get_size()
		var s := maxf(size.x / tex_size.x, size.y / tex_size.y)
		var offset := (size - tex_size * s) / 2
		for i in flag_text.size():
			var l := flag_text[i]
			l.add_theme_font_size_override("font_size", int(FLAG_TEXT_SIZE * s))
			l.size = Vector2(FLAG_TEXT_SIZE * 1.4, FLAG_TEXT_SIZE * 2.6) * s
			l.position = offset + Vector2(FLAG_COLUMNS[i][1] - FLAG_TEXT_SIZE * 0.7, FLAG_TEXT_TOP) * s
	resized.connect(place_text)
	place_text.call()

	# 竖排大标题，旁边一行小字和一方「聚义」印
	var title := UiKit.brush_label(UiKit.vertical_text("水浒聚义"), 118, UiKit.INK)
	title.add_theme_constant_override("line_spacing", -28)
	title.position = Vector2(340, 56)
	add_child(title)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 20)
	side.position = Vector2(270, 90)
	add_child(side)
	var sub := UiKit.brush_label(UiKit.vertical_text("一人一刀　闯荡水浒江湖"), 28, Color("5a3a22"))
	sub.add_theme_constant_override("line_spacing", -8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(sub)
	var seal := UiKit.seal_label("聚义", 22, true)
	seal.rotation = deg_to_rad(-5)
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	side.add_child(seal)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 24)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.position = Vector2(46, 150)
	buttons.custom_minimum_size = Vector2(220, 0)
	add_child(buttons)
	var resume := UiKit.plaque_button("继续游戏", Vector2(220, 70), true, 34)
	resume.disabled = not GameState.has_save()
	resume.pressed.connect(func() -> void: continue_requested.emit())
	buttons.add_child(resume)
	var fresh := UiKit.plaque_button("新游戏", Vector2(200, 62), false, 30)
	fresh.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	fresh.pressed.connect(func() -> void: new_game_requested.emit())
	buttons.add_child(fresh)
	var settings := UiKit.plaque_button("设　置", Vector2(200, 62), false, 30)
	settings.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	settings.pressed.connect(func() -> void:
		var panel := SettingsPanel.new()
		panel.allow_restart = false
		add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.closed.connect(panel.queue_free))
	buttons.add_child(settings)
	if GameState.has_save():
		var note := UiKit.label("新游戏会覆盖现在的存档\n（%s）" % GameState.player_name, 14, Color("5a3a2a"))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buttons.add_child(note)
	# 右下角的版本号
	var ver := UiKit.label("版本 %s　单机离线，没有任何付费" % UiKit.version(), 14, Color("efe3c6"))
	ver.add_theme_constant_override("outline_size", 4)
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	add_child(ver)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -420
	ver.offset_top = -40
	ver.offset_right = -16
	ver.offset_bottom = -12
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
