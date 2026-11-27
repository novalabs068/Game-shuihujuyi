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

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.box(Color(0.08, 0.07, 0.06, 0.92), UiKit.GOLD, 2, 10))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 40
	box.offset_right = -40
	box.offset_top = -190
	box.offset_bottom = -16
	var pad := MarginContainer.new()
	for s: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, 14)
	box.add_child(pad)
	var v := VBoxContainer.new()
	pad.add_child(v)
	_name_label = UiKit.label("", 26, UiKit.GOLD)
	v.add_child(_name_label)
	_text_label = UiKit.label("", 25)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_text_label)
	var more := UiKit.label("点击继续 ▼", 16, UiKit.TEXT_DIM)
	more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(more)
	UiKit.ignore_mouse(box)

	var title := UiKit.label("%s列传 · %s" % [_hero_name(), story.title], 24, UiKit.GOLD)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.position = Vector2(24, 16)
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
	_auto_button = UiKit.button("自动", Vector2(96, 44), 20)
	_auto_button.toggle_mode = true
	_auto_button.toggled.connect(func(on: bool) -> void:
		_auto = on
		if on and not _is_typing():
			_next.emit())
	buttons.add_child(_auto_button)
	var skip := UiKit.button("跳过", Vector2(96, 44), 20)
	skip.tooltip_text = "跳到下一场战斗或结尾"
	skip.pressed.connect(func() -> void:
		_skipping = true
		_next.emit())
	buttons.add_child(skip)
	var leave := UiKit.button("离开", Vector2(96, 44), 20)
	leave.tooltip_text = "回到大地图，这一段下次从头开始"
	leave.pressed.connect(func() -> void: quit_requested.emit())
	buttons.add_child(leave)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 14)
	add_child(_choices)
	_choices.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	_ops = StoryScript.load_file(story.script_path)
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
	_name_label.text = shown_name
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
	_text_label.text = ""
	var picked := [""]
	for option: Dictionary in options:
		var button := UiKit.button(GameState.fill_text(String(option["text"])), Vector2(640, 64), 22)
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
