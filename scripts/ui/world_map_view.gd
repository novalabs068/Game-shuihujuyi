class_name WorldMapView
extends Control
## 江湖大地图：点地名，主角沿道路走过去；没开放的地点盖着云雾；路上可能遇敌。
## 打仗、编队都交给 main.gd 切换画面，回来时用 resume_* 接着走完剩下的路。

## bonus：打赢后额外的奖励和标记，见 main.gd 的 _start_battle()
signal battle_requested(stage: StageData, destination: StringName, progress: float, bonus: Dictionary)
signal team_requested
signal scene_requested(scene_id: String)
signal recruit_requested
signal heroes_requested
signal story_requested(story: StoryData)
signal jianghu_requested
signal profile_requested
## 在设置里确认了重新开始
signal restart_requested

## 拖动地图时，手指移动超过这么多像素才算拖（不算点击）
const DRAG_SLOP := 10.0
## 赶路时镜头跟随主角的快慢
const CAMERA_FOLLOW := 6.0
const ROAD_DASH := 12.0
const ROAD_GAP := 9.0
const WALK_SPEED := 260.0
const ENCOUNTER_AT := 0.5
## 一程路上没遇敌时，碰上奇遇的概率
const EVENT_CHANCE := 0.3
## 第一次到一个地点给的聚义令
const FIRST_VISIT_TOKENS := 3
## 地图上走路时头像每一步跳起的高度
const AVATAR_HOP := 7.0
const PAPER := Color("efe7d4")
const INK := Color("1e1c1a")
const CINNABAR := Color("be3226")

var map: WorldMapData
## 从战斗回来时由 main.gd 设置：接着从 resume_progress 处走到 resume_destination
var resume_destination: StringName = &""
var resume_progress := 0.0
## 打开地图时先提示一句，比如升级
var notice := ""
## 从江湖榜点「前往」：一进地图就走向这个地点
var focus_location: StringName = &""

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
## 新手引导要框亮的顶栏按钮：步骤 → 按钮
var _guide_targets: Dictionary[int, Button] = {}
var _walking := false
var _rng := RandomNumberGenerator.new()
## 地图拖到哪了：底图左上角在屏幕上的位置
var _pan := Vector2.ZERO
var _drag_from := Vector2.INF
var _dragging := false


func _ready() -> void:
	_rng.randomize()
	var bg := ColorRect.new()
	bg.color = PAPER
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_layer = Control.new()
	_layer.size = map.size
	add_child(_layer)
	var tex := TextureRect.new()
	tex.texture = map.texture
	tex.size = map.size
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# 按住底图拖动地图
	tex.mouse_filter = Control.MOUSE_FILTER_STOP
	tex.gui_input.connect(_on_drag_input)
	_layer.add_child(tex)
	var roads := Control.new()
	roads.size = map.size
	roads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roads.draw.connect(_draw_roads.bind(roads))
	_layer.add_child(roads)

	for loc in map.locations:
		_build_location(loc)
	_avatar = _build_avatar()
	_layer.add_child(_avatar)
	_build_top_bar()
	_build_guide()
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
	_refresh_locks()
	_place_avatar(map.location(GameState.location_id).map_position)
	_layout()
	if resume_destination != &"":
		_travel(resume_destination, resume_progress, false)
	elif focus_location != &"" and focus_location != GameState.location_id:
		_travel(focus_location, 0.0, true)
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
	var me := GameState.protagonist()
	var face := UiKit.picture(me.face if me != null else null, 64)
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
	# 左上角是主角：头像 + 名字，点了进主角页
	var me := GameState.protagonist()
	var profile := UiKit.button(me.display_name if me != null else map.title, Vector2(150, 44), 22)
	if me != null and me.face != null:
		profile.icon = me.face
		profile.expand_icon = true
		profile.add_theme_constant_override("icon_max_width", 36)
	profile.add_theme_color_override("font_color", PAPER)
	profile.pressed.connect(func() -> void:
		if not _walking:
			profile_requested.emit())
	row.add_child(profile)
	_status = UiKit.label("", 20, UiKit.GOLD)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_status)
	_refresh_status()
	var jianghu_button := UiKit.button("江湖榜", Vector2(100, 40), 20)
	jianghu_button.add_theme_color_override("font_color", UiKit.GOLD)
	jianghu_button.pressed.connect(func() -> void:
		if not _walking:
			jianghu_requested.emit())
	row.add_child(jianghu_button)
	_guide_targets[5] = jianghu_button
	var recruit_button := UiKit.button("招募", Vector2(100, 40), 20)
	recruit_button.pressed.connect(func() -> void:
		if not _walking:
			recruit_requested.emit())
	row.add_child(recruit_button)
	_guide_targets[1] = recruit_button
	var heroes_button := UiKit.button("好汉", Vector2(100, 40), 20)
	heroes_button.pressed.connect(func() -> void:
		if not _walking:
			heroes_requested.emit())
	row.add_child(heroes_button)
	_guide_targets[4] = heroes_button
	var team_button := UiKit.button("编队", Vector2(100, 40), 20)
	team_button.pressed.connect(func() -> void:
		if not _walking:
			team_requested.emit())
	row.add_child(team_button)
	_guide_targets[2] = team_button
	var settings_button := UiKit.button("设置", Vector2(90, 40), 18)
	settings_button.pressed.connect(_open_settings)
	row.add_child(settings_button)


## 新手引导：顶栏下面一条提示，对应的按钮一闪一闪。
const GUIDE_TEXTS := {
	1: "新手引导 1/5：点右上角「招募」，用开局送的 10 枚聚义令来一次十连，招几位好汉。",
	2: "新手引导 2/5：点「编队」，挑 2 位好汉跟你一起闯荡。",
	3: "新手引导 3/5：去打一仗。点地点的「进入」走进场景（东京、景阳冈、快活林、十字坡），碰到游荡的小怪就开打；在大地图上赶路也会遇到敌人。",
	4: "新手引导 4/5：打赢了！点「好汉」看看：重复抽到的好汉会变成将魂，攒够了点亮勾玉；还能换装备、看天赋和组合技。",
	5: "新手引导 5/5：点「江湖榜」，里面列着眼下能做的事：悬赏、列传、宝箱、没去过的地方。看完之后，江湖就随你闯了！",
}


func _build_guide() -> void:
	var step := GameState.tutorial_step()
	if step == 0:
		return
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiKit.box(Color(INK, 0.92), UiKit.GOLD, 2, 8))
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = 62
	bar.offset_left = 16
	bar.offset_right = -16
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	var text := UiKit.label(GUIDE_TEXTS[step], 20, UiKit.GOLD)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var skip := UiKit.button("跳过引导", Vector2(110, 40), 16)
	skip.pressed.connect(func() -> void:
		GameState.mark_tutorial("tut_done")
		bar.queue_free())
	row.add_child(skip)
	var target: Button = _guide_targets.get(step)
	if target != null:
		var pulse := target.create_tween().set_loops()
		pulse.tween_property(target, "modulate", Color(1.8, 1.5, 0.6), 0.5)
		pulse.tween_property(target, "modulate", Color.WHITE, 0.5)


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
	_center_on(_avatar.position + Vector2(36, 96), true)
	_panel.reset_size()
	_panel.position = Vector2((size.x - _panel.size.x) / 2, size.y - _panel.size.y - 14)
	_toast.size = Vector2(size.x, 60)
	_toast.position = Vector2(0, size.y * 0.42)


# --- 拖动和镜头 ---

func _process(delta: float) -> void:
	if _walking and not _dragging:
		var target := _clamp_pan(size / 2 - (_avatar.position + Vector2(36, 96)))
		_set_pan(_pan.lerp(target, clampf(CAMERA_FOLLOW * delta, 0.0, 1.0)))


## 把地图上的 point 放到屏幕中间（地图比屏幕小的方向就居中）。
func _center_on(point: Vector2, snap: bool) -> void:
	var target := _clamp_pan(size / 2 - point)
	_set_pan(target if snap else _pan.lerp(target, 0.2))


func _clamp_pan(p: Vector2) -> Vector2:
	for axis in 2:
		if map.size[axis] <= size[axis]:
			p[axis] = (size[axis] - map.size[axis]) / 2
		else:
			p[axis] = clampf(p[axis], size[axis] - map.size[axis], 0.0)
	return p


func _set_pan(p: Vector2) -> void:
	_pan = p
	_layer.position = p.round()


func _on_drag_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_drag_from = click.global_position
			_dragging = false
		else:
			_drag_from = Vector2.INF
			_dragging = false
		return
	var motion := event as InputEventMouseMotion
	if motion == null or _drag_from == Vector2.INF:
		return
	if not _dragging and motion.global_position.distance_to(_drag_from) > DRAG_SLOP:
		_dragging = true
	if _dragging:
		_set_pan(_clamp_pan(_pan + motion.relative))


## 道路：墨色虚线，下面垫一道淡淡的宽线。
func _draw_roads(canvas: Control) -> void:
	for road in map.roads:
		canvas.draw_polyline(road.points, Color(INK, 0.12), 9.0, true)
		var pts := road.points
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var length := a.distance_to(b)
			var dir := (b - a) / maxf(length, 0.001)
			var t := 0.0
			while t < length:
				var e := minf(t + ROAD_DASH, length)
				canvas.draw_line(a + dir * t, a + dir * e, Color(INK, 0.6), 3.0, true)
				t = e + ROAD_GAP


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
	# 还没有好汉随行时路上不遇敌
	if can_encounter and not GameState.team().is_empty():
		var mount := GameState.mount()
		var cut := mount.encounter_cut if mount != null else 0.0
		if _rng.randf() < map.encounter_chance * (1.0 - cut):
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
	# 走完一段路，气血回一点
	GameState.road_regen()
	_arrive(map.location(destination))


func _walk(points: PackedVector2Array, from: float, to: float) -> void:
	var bob := _avatar.create_tween().set_loops()
	bob.tween_property(_avatar, "rotation", 0.08, 0.15)
	bob.tween_property(_avatar, "rotation", -0.08, 0.15)
	var walk := create_tween()
	# 主角骑着马赶路更快
	var mount := GameState.mount()
	var speed := WALK_SPEED * (1.0 + (mount.travel_speed if mount != null else 0.0))
	var duration := _length(points) * (to - from) / speed
	var started := Time.get_ticks_msec()
	# 一边走一边一跳一跳：每 0.3 秒（左右各摆一次）跳一下
	walk.tween_method(func(p: float) -> void:
		var t := (Time.get_ticks_msec() - started) / 1000.0
		_place_avatar(_sample(points, p) - Vector2(0, absf(sin(t * PI / 0.3)) * AVATAR_HOP)), from, to, maxf(duration, 0.1))
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
	for story in GameDB.stories:
		if story.location == loc.id and GameState.story_available(story):
			var hero := GameDB.hero(story.hero)
			var button := UiKit.button("%s列传·%s" % [hero.display_name, story.title], Vector2(220, 52), 22)
			button.add_theme_color_override("font_color", UiKit.GOLD)
			button.tooltip_text = "推荐 %d 级" % story.recommended_level
			button.pressed.connect(func() -> void:
				if not _walking:
					story_requested.emit(story))
			_panel_buttons.add_child(button)
	if loc.has_inn and loc.id == GameState.location_id:
		var price := Vitality.rest_price(GameState.level)
		var inn := UiKit.button("歇脚（%d 两）" % price, Vector2(170, 52), 22)
		inn.disabled = GameState.vitality.is_empty() or GameState.silver < price
		inn.tooltip_text = "住一晚，全队气血回满" if not GameState.vitality.is_empty() else "全队气血都是满的"
		inn.pressed.connect(func() -> void:
			if GameState.rest():
				_flash_toast("住了一晚，全队气血回满")
				_refresh_status()
				_show_panel(loc))
		_panel_buttons.add_child(inn)
	if loc.has_market:
		var market := UiKit.button("集市", Vector2(120, 52), 22)
		market.pressed.connect(_open_market)
		_panel_buttons.add_child(market)
	if _panel_buttons.get_child_count() == 0:
		_panel_buttons.add_child(UiKit.label("点地图上的地名前往别处。", 17, UiKit.TEXT_DIM))
	_layout()


func _open_market() -> void:
	var market := MarketPanel.new()
	add_child(market)
	market.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	market.closed.connect(func() -> void:
		market.queue_free()
		_refresh_status())


func _open_board(loc: LocationData) -> void:
	var board := BountyBoard.new()
	board.bounties = GameDB.open_bounties(loc.id)
	board.region = loc.id
	add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.closed.connect(board.queue_free)
	board.accepted.connect(func(b: BountyData) -> void:
		battle_requested.emit(b.stage, &"", 0.0, b.battle_bonus()))


func _refresh_status() -> void:
	_status.text = "Lv%d　经验 %d/%d　银两 %d　聚义令 %d" % [GameState.level, GameState.experience, GameState.exp_to_next(GameState.level), GameState.silver, GameState.tokens]


func _refresh_locks() -> void:
	for loc in map.locations:
		var open := GameState.has_flag(loc.unlock_flag)
		_clouds[loc.id].visible = not open
		_tags[loc.id].modulate = Color.WHITE if open else Color(1, 1, 1, 0.35)


func _open_settings() -> void:
	if _walking:
		return
	var panel := SettingsPanel.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(panel.queue_free)
	panel.restart_requested.connect(func() -> void: restart_requested.emit())


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
