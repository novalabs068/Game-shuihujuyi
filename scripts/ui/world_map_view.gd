class_name WorldMapView
extends Control
## 江湖大地图：点地名，主角沿道路走过去；没开放的地点盖着云雾；路上可能遇敌。
## 打仗、编队都交给 main.gd 切换画面，回来时用 resume_* 接着走完剩下的路。

## bonus：打赢后额外的奖励和标记，见 main.gd 的 _start_battle()
signal battle_requested(stage: StageData, destination: StringName, progress: float, bonus: Dictionary)
signal team_requested
signal scene_requested(scene_id: String)
signal recruit_requested

const MAP_SIZE := Vector2(1280, 720)
const WALK_SPEED := 260.0
const ENCOUNTER_AT := 0.5
## 一程路上没遇敌时，碰上奇遇的概率
const EVENT_CHANCE := 0.3
## 第一次到一个地点给的聚义令
const FIRST_VISIT_TOKENS := 3
const PAPER := Color("efe7d4")
const INK := Color("1e1c1a")
const CINNABAR := Color("be3226")

var map: WorldMapData
## 从战斗回来时由 main.gd 设置：接着从 resume_progress 处走到 resume_destination
var resume_destination: StringName = &""
var resume_progress := 0.0
## 打开地图时先提示一句，比如升级
var notice := ""

var _layer: Control
var _avatar: Control
var _tags: Dictionary[StringName, PanelContainer] = {}
var _clouds: Dictionary[StringName, Control] = {}
var _panel: PanelContainer
var _panel_title: Label
var _panel_desc: Label
var _panel_buttons: HBoxContainer
var _toast: Label
var _event_panel: EventPanel
var _status: Label
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
	_event_panel = EventPanel.new()
	add_child(_event_panel)
	_event_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	if notice != "":
		_flash_toast(notice)


# --- 搭界面 ---

func _build_location(loc: LocationData) -> void:
	# 地名竖签：墨底金边，一字一行
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UiKit.box(Color(INK, 0.88), UiKit.GOLD, 2, 4))
	var chars := PackedStringArray()
	for i in loc.display_name.length():
		chars.append(loc.display_name[i])
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	tag.add_child(column)
	var name_label := UiKit.label("\n".join(chars), 24, PAPER)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	# 危险星级竖排在地名下面
	var star_lines := PackedStringArray()
	for i in loc.danger:
		star_lines.append("★")
	var stars := UiKit.label("\n".join(star_lines), 14, UiKit.GOLD)
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(stars)
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
	row.add_child(title)
	_status = UiKit.label("", 20, UiKit.GOLD)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_status)
	_refresh_status()
	var recruit_button := UiKit.button("招募", Vector2(100, 40), 20)
	recruit_button.pressed.connect(func() -> void:
		if not _walking:
			recruit_requested.emit())
	row.add_child(recruit_button)
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
	# 先决定这一程路上会发生什么：遇敌（按目的地一带的敌人组合生成）、奇遇，或者一路平安
	var stage: StageData = null
	var event: EventData = null
	if can_encounter:
		if _rng.randf() < map.encounter_chance:
			stage = Encounters.build(map.location(destination), GameState.level, _rng)
			if stage == null and map.encounter_stage_id != "":
				stage = GameDB.stages[map.encounter_stage_id]
		elif _rng.randf() < EVENT_CHANCE:
			event = _pick_event(destination)
	var stops := stage != null or event != null
	await _walk(points, from_progress, ENCOUNTER_AT if stops else 1.0)
	if stage != null:
		_flash_toast("%s！" % stage.title)
		await get_tree().create_timer(0.9).timeout
		battle_requested.emit(stage, destination, ENCOUNTER_AT, {})
		return
	if event != null:
		if await _run_event(event, destination):
			return
		await _walk(points, ENCOUNTER_AT, 1.0)
	_walking = false
	_arrive(map.location(destination))


func _walk(points: PackedVector2Array, from: float, to: float) -> void:
	var bob := _avatar.create_tween().set_loops()
	bob.tween_property(_avatar, "rotation", 0.08, 0.15)
	bob.tween_property(_avatar, "rotation", -0.08, 0.15)
	var walk := create_tween()
	var duration := _length(points) * (to - from) / WALK_SPEED
	walk.tween_method(func(p: float) -> void: _place_avatar(_sample(points, p)), from, to, maxf(duration, 0.1))
	await walk.finished
	bob.kill()
	_avatar.rotation = 0.0


## 随机挑一个能在去 destination 的路上发生的奇遇；只发生一次的，发生过就不再出现。
func _pick_event(destination: StringName) -> EventData:
	var pool: Array[EventData] = []
	for e in GameDB.events:
		if e.once and GameState.has_flag("event_" + String(e.id)):
			continue
		if not e.locations.is_empty() and not destination in e.locations:
			continue
		pool.append(e)
	return pool[_rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else null


## 弹出奇遇让玩家选。选了要打仗的就发出 battle_requested 并返回 true（地图会被换掉）。
func _run_event(event: EventData, destination: StringName) -> bool:
	if event.once:
		GameState.set_flag("event_" + String(event.id))
	var choice := await _event_panel.ask(event)
	if choice.battle != null or choice.battle_from_region:
		var stage := choice.battle
		if stage == null:
			stage = Encounters.build(map.location(destination), GameState.level, _rng)
		_event_panel.close()
		battle_requested.emit(stage, destination, ENCOUNTER_AT, _choice_bonus(choice))
		return true
	var gained := Rewards.apply_choice(choice)
	GameState.save_game()
	_refresh_status()
	await _event_panel.show_result(choice.result_text, gained)
	return false


static func _choice_bonus(choice: EventChoice) -> Dictionary:
	return {"tokens": choice.tokens, "silver": choice.silver - choice.cost_silver, "experience": choice.experience,
		"flag": choice.flag, "text": choice.result_text}


func _arrive(loc: LocationData) -> void:
	GameState.location_id = loc.id
	var first_time := loc.arrive_flag != "" and not GameState.has_flag(loc.arrive_flag)
	GameState.set_flag(loc.arrive_flag)
	var visit_flag := "visited_" + String(loc.id)
	var first_visit := not GameState.has_flag(visit_flag)
	GameState.set_flag(visit_flag)
	if first_visit:
		GameState.tokens += FIRST_VISIT_TOKENS
		_flash_toast("初到%s，聚义令 +%d" % [loc.display_name, FIRST_VISIT_TOKENS])
	GameState.save_game()
	_refresh_status()
	_refresh_locks()
	_show_panel(loc)
	if first_time and loc.arrive_text != "":
		_panel_desc.text = loc.arrive_text
		_layout()


func _show_panel(loc: LocationData) -> void:
	_panel.visible = true
	_panel_title.text = "%s　%s" % [loc.display_name, "★".repeat(loc.danger)]
	_panel_desc.text = "%s\n这一带的敌人：%d～%d 级（你现在 %d 级）" % [loc.description, loc.level_min, loc.level_max, GameState.level]
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
	if GameDB.bounties.any(func(b: BountyData) -> bool: return b.location == loc.id):
		var open := GameDB.open_bounties(loc.id)
		var board := UiKit.button("悬赏告示（%d）" % open.size(), Vector2(200, 52), 22)
		board.pressed.connect(_open_board.bind(loc))
		_panel_buttons.add_child(board)
	if _panel_buttons.get_child_count() == 0:
		_panel_buttons.add_child(UiKit.label("点地图上的地名前往别处。", 17, UiKit.TEXT_DIM))
	_layout()


func _open_board(loc: LocationData) -> void:
	var board := BountyBoard.new()
	board.bounties = GameDB.open_bounties(loc.id)
	add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.closed.connect(board.queue_free)
	board.accepted.connect(func(b: BountyData) -> void:
		battle_requested.emit(b.stage, &"", 0.0, {"tokens": b.tokens(), "flag": "bounty_" + String(b.id),
			"text": "揭下了「%s」的悬赏。" % b.target}))


func _refresh_status() -> void:
	_status.text = "%s　Lv%d　经验 %d/%d　银两 %d　聚义令 %d" % [GameState.player_name, GameState.level, GameState.experience, GameState.exp_to_next(GameState.level), GameState.silver, GameState.tokens]


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
