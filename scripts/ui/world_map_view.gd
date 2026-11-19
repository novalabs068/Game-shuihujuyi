class_name WorldMapView
extends Control
## 江湖大地图：点地名，主角沿道路走过去；没开放的地点盖着云雾；路上可能遇敌。
## 打仗、编队都交给 main.gd 切换画面，回来时用 resume_* 接着走完剩下的路。

signal battle_requested(stage: StageData, destination: StringName, progress: float)
signal team_requested
signal scene_requested(scene_id: String)

const MAP_SIZE := Vector2(1280, 720)
const WALK_SPEED := 260.0
const ENCOUNTER_AT := 0.5
const PAPER := Color("efe7d4")
const INK := Color("1e1c1a")
const CINNABAR := Color("be3226")

var map: WorldMapData
## 从战斗回来时由 main.gd 设置：接着从 resume_progress 处走到 resume_destination
var resume_destination: StringName = &""
var resume_progress := 0.0

var _layer: Control
var _avatar: Control
var _tags: Dictionary[StringName, PanelContainer] = {}
var _clouds: Dictionary[StringName, Control] = {}
var _panel: PanelContainer
var _panel_title: Label
var _panel_desc: Label
var _panel_buttons: HBoxContainer
var _toast: Label
var _walking := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var bg := ColorRect.new()
	bg.color = PAPER
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_layer = Control.new()
	_layer.size = MAP_SIZE
	add_child(_layer)
	var tex := TextureRect.new()
	tex.texture = map.texture
	tex.size = MAP_SIZE
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(tex)

	for loc in map.locations:
		_build_location(loc)
	_avatar = _build_avatar()
	_layer.add_child(_avatar)
	_build_top_bar()
	_build_panel()
	_toast = UiKit.label("", 26, PAPER)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", INK)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)

	resized.connect(_layout)
	_layout()
	_refresh_locks()
	_place_avatar(map.location(GameState.location_id).map_position)
	if resume_destination != &"":
		_travel(resume_destination, resume_progress, false)
	else:
		_show_panel(map.location(GameState.location_id))


# --- 搭界面 ---

func _build_location(loc: LocationData) -> void:
	# 地名竖签：墨底金边，一字一行
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UiKit.box(Color(INK, 0.88), UiKit.GOLD, 2, 4))
	var chars := PackedStringArray()
	for i in loc.display_name.length():
		chars.append(loc.display_name[i])
	var name_label := UiKit.label("\n".join(chars), 24, PAPER)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_child(name_label)
	_layer.add_child(tag)
	tag.position = loc.label_position - Vector2(20, 0)
	UiKit.ignore_mouse(tag)
	tag.gui_input.connect(_on_location_input.bind(loc))
	_tags[loc.id] = tag

	# 道路上的落脚点
	var dot := Panel.new()
	dot.add_theme_stylebox_override("panel", UiKit.box(CINNABAR, INK, 3, 14))
	dot.size = Vector2(26, 26)
	dot.position = loc.map_position - dot.size / 2
	dot.gui_input.connect(_on_location_input.bind(loc))
	_layer.add_child(dot)

	# 没开放时盖住的云雾
	var cloud := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(PAPER, 0.97))
	gradient.set_color(1, Color(PAPER, 0.0))
	gradient.set_offset(0, 0.45)
	var fog := GradientTexture2D.new()
	fog.gradient = gradient
	fog.fill = GradientTexture2D.FILL_RADIAL
	fog.fill_from = Vector2(0.5, 0.5)
	fog.fill_to = Vector2(1.0, 0.5)
	cloud.texture = fog
	cloud.size = Vector2(320, 380)
	cloud.position = Vector2(loc.map_position.x, (loc.map_position.y + loc.label_position.y) / 2) - cloud.size / 2
	cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mystery := UiKit.label("？", 56, Color(INK, 0.55))
	mystery.position = cloud.size / 2 - Vector2(28, 40)
	cloud.add_child(mystery)
	_layer.add_child(cloud)
	_clouds[loc.id] = cloud


func _build_avatar() -> Control:
	var root := Control.new()
	root.size = Vector2(72, 92)
	root.pivot_offset = Vector2(36, 92)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := Panel.new()
	frame.size = Vector2(72, 72)
	frame.add_theme_stylebox_override("panel", UiKit.box(PAPER, CINNABAR, 4, 36))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	root.add_child(frame)
	var leader := GameState.team()
	var face := UiKit.picture(leader[0].face if not leader.is_empty() else null, 64)
	face.position = Vector2(4, 4)
	face.size = Vector2(64, 64)
	frame.add_child(face)
	var pin := UiKit.label("▼", 22, CINNABAR)
	pin.position = Vector2(26, 64)
	root.add_child(pin)
	UiKit.ignore_mouse(root)
	return root


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiKit.box(Color(INK, 0.85), Color(0, 0, 0, 0), 0, 0))
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 56
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	var title := UiKit.label(map.title, 26, PAPER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var team_button := UiKit.button("编队", Vector2(100, 40), 20)
	team_button.pressed.connect(func() -> void:
		if not _walking:
			team_requested.emit())
	row.add_child(team_button)
	var reset_button := UiKit.button("重开", Vector2(90, 40), 18)
	reset_button.tooltip_text = "清空存档，从头开始（原型调试用）"
	reset_button.pressed.connect(_on_reset)
	row.add_child(reset_button)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.box(Color(INK, 0.9), UiKit.GOLD, 2, 10))
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_panel_title = UiKit.label("", 26, UiKit.GOLD)
	v.add_child(_panel_title)
	_panel_desc = UiKit.label("", 18, PAPER)
	_panel_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_desc.custom_minimum_size.x = 640
	v.add_child(_panel_desc)
	_panel_buttons = HBoxContainer.new()
	_panel_buttons.add_theme_constant_override("separation", 12)
	v.add_child(_panel_buttons)


func _layout() -> void:
	_layer.position = ((size - MAP_SIZE) / 2).floor()
	_panel.reset_size()
	_panel.position = Vector2((size.x - _panel.size.x) / 2, size.y - _panel.size.y - 14)
	_toast.size = Vector2(size.x, 60)
	_toast.position = Vector2(0, size.y * 0.42)


# --- 交互 ---

func _on_location_input(event: InputEvent, loc: LocationData) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or _walking:
		return
	if not GameState.has_flag(loc.unlock_flag):
		_flash_toast("剧情还没走到这里")
		return
	if loc.id == GameState.location_id:
		_show_panel(loc)
	else:
		_travel(loc.id, 0.0, true)


## 沿道路走向 destination。can_encounter 时走到一半可能被拦下打一仗。
func _travel(destination: StringName, from_progress: float, can_encounter: bool) -> void:
	var points := map.route(GameState.location_id, destination)
	if points.size() < 2:
		return
	_walking = true
	_panel.visible = false
	var encounter := can_encounter and map.encounter_stage_id != "" and _rng.randf() < map.encounter_chance
	var stop_at := ENCOUNTER_AT if encounter else 1.0
	var duration := _length(points) * (stop_at - from_progress) / WALK_SPEED
	var bob := _avatar.create_tween().set_loops()
	bob.tween_property(_avatar, "rotation", 0.08, 0.15)
	bob.tween_property(_avatar, "rotation", -0.08, 0.15)
	var walk := create_tween()
	walk.tween_method(func(p: float) -> void: _place_avatar(_sample(points, p)), from_progress, stop_at, maxf(duration, 0.1))
	await walk.finished
	bob.kill()
	_avatar.rotation = 0.0
	if encounter:
		var stage: StageData = GameDB.stages[map.encounter_stage_id]
		_flash_toast("%s！" % stage.title)
		await get_tree().create_timer(0.9).timeout
		battle_requested.emit(stage, destination, ENCOUNTER_AT)
		return
	_walking = false
	_arrive(map.location(destination))


func _arrive(loc: LocationData) -> void:
	GameState.location_id = loc.id
	var first_time := loc.arrive_flag != "" and not GameState.has_flag(loc.arrive_flag)
	GameState.set_flag(loc.arrive_flag)
	GameState.save_game()
	_refresh_locks()
	_show_panel(loc)
	if first_time and loc.arrive_text != "":
		_panel_desc.text = loc.arrive_text
		_layout()


func _show_panel(loc: LocationData) -> void:
	_panel.visible = true
	_panel_title.text = loc.display_name
	_panel_desc.text = loc.description
	for child in _panel_buttons.get_children():
		_panel_buttons.remove_child(child)
		child.queue_free()
	if loc.scene_id != "":
		var enter := UiKit.button("进入", Vector2(140, 52), 22)
		var ready := GameDB.scenes.has(loc.scene_id)
		enter.pressed.connect(func() -> void:
			if ready:
				scene_requested.emit(loc.scene_id)
			else:
				_flash_toast("这里还在建设中"))
		_panel_buttons.add_child(enter)
	if loc.stage_id != "" and GameDB.stages.has(loc.stage_id):
		var stage: StageData = GameDB.stages[loc.stage_id]
		var cleared := GameState.has_flag("clear_" + loc.stage_id)
		var fight := UiKit.button("主线 %s「%s」%s" % [stage.id, stage.title, "（已通关）" if cleared else ""], Vector2(260, 52), 22)
		fight.pressed.connect(func() -> void: battle_requested.emit(stage, &"", 0.0))
		_panel_buttons.add_child(fight)
	if _panel_buttons.get_child_count() == 0:
		_panel_buttons.add_child(UiKit.label("点地图上的地名前往别处。", 17, UiKit.TEXT_DIM))
	_layout()


func _refresh_locks() -> void:
	for loc in map.locations:
		var open := GameState.has_flag(loc.unlock_flag)
		_clouds[loc.id].visible = not open
		_tags[loc.id].modulate = Color.WHITE if open else Color(1, 1, 1, 0.35)


func _on_reset() -> void:
	if _walking:
		return
	GameState.reset()
	GameState.save_game()
	_refresh_locks()
	_place_avatar(map.location(GameState.location_id).map_position)
	_show_panel(map.location(GameState.location_id))
	_flash_toast("已重新开始")


func _flash_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var t := _toast.create_tween()
	t.tween_interval(1.0)
	t.tween_property(_toast, "modulate:a", 0.0, 0.4)


# --- 工具 ---

func _place_avatar(point: Vector2) -> void:
	_avatar.position = point - Vector2(36, 96)


func _length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## 折线上按长度比例 t（0～1）取一个点。
func _sample(points: PackedVector2Array, t: float) -> Vector2:
	var target := _length(points) * clampf(t, 0.0, 1.0)
	for i in range(1, points.size()):
		var seg := points[i - 1].distance_to(points[i])
		if target <= seg:
			return points[i - 1].lerp(points[i], target / seg if seg > 0.0 else 0.0)
		target -= seg
	return points[points.size() - 1]
