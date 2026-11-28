class_name StoryView
extends Control
## 列传演出（视觉小说式）：整屏背景、左右各站一人（说话的人亮，另一个暗）、底部对话框逐字打出，
## 右上角自动 / 跳过 / 离开。演到 @battle 时交给 main 去打，赢了从 start_at 接着演。

signal battle_requested(stage: StageData, resume_at: int)
signal finished
signal quit_requested

const CHARS_PER_SECOND := 36.0
const AUTO_DELAY := 1.4
const PORTRAIT_HEIGHT := 600.0
const DIM := Color(0.45, 0.45, 0.45)
const IDLE := Color(0.8, 0.8, 0.8)

var story: StoryData
## 从第几条指令开始演（打完仗回来时用）
var start_at := 0

var _ops: Array[Dictionary] = []
var _bg: TextureRect
var _sides: Dictionary[String, TextureRect] = {}
var _units: Dictionary[String, UnitData] = {}
var _name_label: Label
var _text_label: Label
var _choices: VBoxContainer
var _auto_button: Button
var _typing: Tween
var _auto := false
var _skipping := false

signal _next


func _ready() -> void:
	var back := ColorRect.new()
	back.color = Color.BLACK
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for side: String in ["left", "right"]:
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		pic.flip_h = side == "right"
		pic.size = Vector2(PORTRAIT_HEIGHT * 0.78, PORTRAIT_HEIGHT)
		add_child(pic)
		if side == "left":
			pic.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE)
			pic.position.x += 40
		else:
			pic.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE)
			pic.position.x -= 40
		pic.position.y -= 120
		_sides[side] = pic

	# 点屏幕任何地方都算「下一句」
	var catcher := Control.new()
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(catcher)
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(_on_tap)

	# 对话框是一段横卷：两头木轴，上下石青锦缎，宣纸上墨字；说话人的名字盖成一方朱印
	var box := Control.new()
	var paper := PanelContainer.new()
	var scroll_style := StyleBoxTexture.new()
	scroll_style.texture = load("res://art/ui/result_paper.png")
	scroll_style.content_margin_left = 150
	scroll_style.content_margin_right = 40
	scroll_style.content_margin_top = 22
	scroll_style.content_margin_bottom = 14
	paper.add_theme_stylebox_override("panel", scroll_style)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.add_child(paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 52
	box.offset_right = -52
	box.offset_top = -184
	box.offset_bottom = -20
	_dress_scroll(box)
	var v := VBoxContainer.new()
	paper.add_child(v)
	_name_label = UiKit.brush_label("", 30, Color("f7e7c6"))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_constant_override("line_spacing", -8)
	var seal := PanelContainer.new()
	var seal_style := StyleBoxFlat.new()
	seal_style.bg_color = UiKit.CINNABAR
	seal_style.border_color = Color("f7e7c6", 0.75)
	seal_style.set_border_width_all(2)
	seal_style.set_corner_radius_all(3)
	seal_style.set_content_margin_all(7)
	seal_style.shadow_color = Color(0, 0, 0, 0.35)
	seal_style.shadow_size = 4
	seal.add_theme_stylebox_override("panel", seal_style)
	seal.add_child(_name_label)
	seal.position = Vector2(40, -30)
	seal.rotation = deg_to_rad(-3)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(seal)
	_name_label.set_meta("seal", seal)
	seal.visible = false
	_text_label = UiKit.label("", 23, UiKit.INK)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_text_label)
	var more := UiKit.label("点击继续 ▾", 14, UiKit.INK_DIM)
	more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(more)
	UiKit.ignore_mouse(box)

	var title := PanelContainer.new()
	title.add_theme_stylebox_override("panel", UiKit.note_box())
	title.add_child(UiKit.brush_label("%s列传 · %s" % [_hero_name(), story.title], 26, UiKit.INK))
	title.position = Vector2(20, 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	add_child(buttons)
	# 贴着右上角：右边缘对齐屏幕右边，按钮从右往左排
	buttons.anchor_left = 1.0
	buttons.anchor_right = 1.0
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.offset_right = -16
	buttons.offset_top = 14
	_auto_button = UiKit.copper_button("自动", 52, 19)
	_auto_button.toggle_mode = true
	_auto_button.toggled.connect(func(on: bool) -> void:
		# 开着自动时钮变成朱印
		var look := StyleBoxTexture.new()
		look.texture = load("res://art/ui/kit_seal.png" if on else "res://art/ui/kit_copper.png")
		UiKit.skin(_auto_button, look)
		_auto = on
		if on and not _is_typing():
			_next.emit())
	buttons.add_child(_auto_button)
	var skip := UiKit.copper_button("跳过", 52, 19)
	skip.tooltip_text = "跳到下一场战斗或结尾"
	skip.pressed.connect(func() -> void:
		_skipping = true
		_next.emit())
	buttons.add_child(skip)
	var leave := UiKit.seal_button("离开", 52, 19)
	leave.tooltip_text = "回到大地图，这一段下次从头开始"
	leave.pressed.connect(func() -> void: quit_requested.emit())
	buttons.add_child(leave)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 14)
	add_child(_choices)
	_choices.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	_ops = StoryScript.load_file(story.script_path)
	# 列传从头开讲时像说书人一样拍一下醒木；打完仗接着演就不拍
	if start_at == 0:
		Sfx.play(&"xingmu", -3.0)
	_run()


func _run() -> void:
	# 打完仗回来：先把之前的背景和站位摆好
	for i in mini(start_at, _ops.size()):
		_apply_stage_op(_ops[i])
	var i := start_at
	while i < _ops.size():
		var op := _ops[i]
		match op["op"]:
			"say":
				await _say(op["speaker"], op["text"])
			"choice":
				var label: String = op["options"][0]["label"] if _skipping else await _choose(op["options"])
				i = StoryScript.find_label(_ops, label)
			"goto":
				i = StoryScript.find_label(_ops, op["label"])
			"battle":
				var stage: StageData = load(story.script_path.get_base_dir().path_join(op["stage"] + ".tres"))
				battle_requested.emit(stage, i + 1)
				return
			_:
				_apply_stage_op(op)
		i += 1
	finished.emit()


func _apply_stage_op(op: Dictionary) -> void:
	match op["op"]:
		"bg":
			var path := StoryScript.background_path(op["key"])
			_bg.texture = load(path) if path != "" else GameDB.maps[GameState.DEFAULT_MAP].texture
			_bg.modulate = Color.WHITE if path != "" else Color(0.55, 0.55, 0.55)
		"show":
			var unit := _unit(op["id"])
			_units[op["side"]] = unit
			var pic := _sides[op["side"]]
			pic.texture = null if unit == null else (unit.portrait if unit.portrait != null else unit.bust)
			pic.modulate = IDLE


func _say(speaker: String, text: String) -> void:
	if _skipping:
		return
	var me := GameState.protagonist()
	var shown_name := me.display_name if speaker == "我" else speaker
	_name_label.text = UiKit.vertical_text(shown_name)
	(_name_label.get_meta("seal") as Control).visible = shown_name != ""
	_text_label.text = GameState.fill_text(text)
	# 说话的人亮起来，另一个变暗；旁白时两边都半亮
	for side in _sides:
		var unit: UnitData = _units.get(side)
		if unit == null:
			continue
		var talking := speaker != "" and unit.display_name == shown_name
		_sides[side].modulate = Color.WHITE if talking else (IDLE if speaker == "" else DIM)
	_text_label.visible_ratio = 0.0
	_typing = create_tween()
	_typing.tween_property(_text_label, "visible_ratio", 1.0, _text_label.text.length() / CHARS_PER_SECOND)
	if _auto:
		_typing.finished.connect(func() -> void:
			get_tree().create_timer(AUTO_DELAY).timeout.connect(func() -> void:
				if _auto and _text_label.text == GameState.fill_text(text):
					_next.emit()))
	await _next


func _choose(options: Array) -> String:
	_name_label.text = ""
	(_name_label.get_meta("seal") as Control).visible = false
	_text_label.text = ""
	var picked := [""]
	for option: Dictionary in options:
		var button := UiKit.button(GameState.fill_text(String(option["text"])), Vector2(640, 62), 21)
		# 选项是一张宣纸条，墨字
		var slip := UiKit.note_box()
		UiKit.skin(button, slip)
		button.add_theme_font_override("font", UiKit.cjk_font())
		for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(c, UiKit.INK)
		button.pressed.connect(func() -> void:
			picked[0] = option["label"]
			_next.emit())
		_choices.add_child(button)
	_choices.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_choices.position.y -= 80
	await _next
	for child in _choices.get_children():
		child.queue_free()
	# 选项出来时点了「跳过」：默认选第一个
	return picked[0] if picked[0] != "" else options[0]["label"]


func _on_tap(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if _choices.get_child_count() > 0:
		return
	if _is_typing():
		_typing.kill()
		_text_label.visible_ratio = 1.0
	else:
		_next.emit()


func _is_typing() -> bool:
	return _typing != null and _typing.is_running()


func _unit(id: String) -> UnitData:
	match id:
		"none":
			return null
		"me":
			return GameState.protagonist()
	var hero := GameDB.hero(StringName(id))
	if hero != null:
		return hero
	var path := "res://data/enemies/%s.tres" % id
	return load(path) if ResourceLoader.exists(path) else null


func _hero_name() -> String:
	var hero := GameDB.hero(story.hero)
	return hero.display_name if hero != null else ""


## 横卷两头的木轴、上下两道锦缎边（加在对话框上，跟着它一起摆）。
func _dress_scroll(box: Control) -> void:
	var brocade: Texture2D = load("res://art/ui/result_brocade.png")
	for top: bool in [true, false]:
		var band := TextureRect.new()
		band.texture = brocade
		band.stretch_mode = TextureRect.STRETCH_TILE
		band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(band)
		band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			band.offset_bottom = 10
		else:
			band.offset_top = -10
	for left: bool in [true, false]:
		var rod := Panel.new()
		var s := StyleBoxFlat.new()
		s.bg_color = Color("6a4429")
		s.border_color = Color("3a2414")
		s.set_border_width_all(2)
		s.set_corner_radius_all(9)
		s.shadow_color = Color(0, 0, 0, 0.5)
		s.shadow_size = 5
		rod.add_theme_stylebox_override("panel", s)
		rod.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rod)
		rod.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE if left else Control.PRESET_RIGHT_WIDE)
		rod.offset_top = -10
		rod.offset_bottom = 10
		if left:
			rod.offset_left = -14
			rod.offset_right = 4
		else:
			rod.offset_left = -4
			rod.offset_right = 14
