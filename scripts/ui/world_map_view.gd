class_name WorldMapView
extends Control
## 江湖大地图：只能看。点地名看那里的情况，在所在的地点可以开列传、住店、逛集市、揭悬赏；
## 去别的地点要回到场景里，从路口走上野外路过去（不能点了就走）。

## 揭了悬赏要打仗；bonus：打赢后额外的奖励和标记，见 main.gd 的 _start_battle()
signal battle_requested(stage: StageData, bonus: Dictionary)
## 回到所在的场景
signal back_requested
signal team_requested
signal recruit_requested
signal heroes_requested
signal story_requested(story: StoryData)
signal jianghu_requested
signal profile_requested
## 在设置里确认了重新开始
signal restart_requested

## 拖动地图时，手指移动超过这么多像素才算拖（不算点击）
const DRAG_SLOP := 10.0
const ROAD_DASH := 12.0
const ROAD_GAP := 9.0
## 第一次到一个地点给的聚义令（GameState.enter_scene 发）
const FIRST_VISIT_TOKENS := 3
const PAPER := Color("efe7d4")
const INK := Color("1e1c1a")
const CINNABAR := Color("be3226")

var map: WorldMapData
## 打开地图时先提示一句
var notice := ""
## 从江湖榜点地点：一打开地图就看那里
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
var _status: Label
## 镜头对准的地点位置（铺满屏幕、尺寸确定后在 _layout 里对准）
var _focus := Vector2.ZERO
## 地图拖到哪了：底图左上角在屏幕上的位置
var _pan := Vector2.ZERO
var _drag_from := Vector2.INF
var _dragging := false


func _ready() -> void:
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
	_build_panel()
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
	var shown := map.location(focus_location) if focus_location != &"" else null
	if shown == null:
		shown = map.location(GameState.location_id)
	_focus = shown.map_position
	_show_panel(shown)
	_layout()
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
	profile.pressed.connect(func() -> void: profile_requested.emit())
	row.add_child(profile)
	_status = UiKit.label("", 20, UiKit.GOLD)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_status)
	_refresh_status()
	var jianghu_button := UiKit.button("江湖榜", Vector2(100, 40), 20)
	jianghu_button.add_theme_color_override("font_color", UiKit.GOLD)
	jianghu_button.pressed.connect(func() -> void: jianghu_requested.emit())
	row.add_child(jianghu_button)
	var recruit_button := UiKit.button("招募", Vector2(100, 40), 20)
	recruit_button.pressed.connect(func() -> void: recruit_requested.emit())
	row.add_child(recruit_button)
	var heroes_button := UiKit.button("好汉", Vector2(100, 40), 20)
	heroes_button.pressed.connect(func() -> void: heroes_requested.emit())
	row.add_child(heroes_button)
	var team_button := UiKit.button("编队", Vector2(100, 40), 20)
	team_button.pressed.connect(func() -> void: team_requested.emit())
	row.add_child(team_button)
	var settings_button := UiKit.button("设置", Vector2(90, 40), 18)
	settings_button.pressed.connect(_open_settings)
	row.add_child(settings_button)
	var back := UiKit.button("返回", Vector2(90, 40), 20)
	back.add_theme_color_override("font_color", UiKit.GOLD)
	back.pressed.connect(func() -> void: back_requested.emit())
	row.add_child(back)


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
	_center_on(_focus + Vector2(0, 80), true)
	_panel.reset_size()
	_panel.position = Vector2((size.x - _panel.size.x) / 2, size.y - _panel.size.y - 14)
	_toast.size = Vector2(size.x, 60)
	_toast.position = Vector2(0, size.y * 0.42)


# --- 拖动和镜头 ---

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
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not GameState.has_flag(loc.unlock_flag):
		_flash_toast("剧情还没走到这里")
		return
	_show_panel(loc)


## 点一个地点：说明和敌人等级；是所在的地点就能开列传、住店、逛集市、揭悬赏，
## 别的地点只看，写出从这里怎么走过去（经过哪些地方）。
func _show_panel(loc: LocationData) -> void:
	_panel.visible = true
	var here := loc.id == GameState.location_id
	_panel_title.text = "%s　%s%s" % [loc.display_name, "★".repeat(loc.danger), "　（你在这里）" if here else ""]
	var desc := "%s\n这一带的敌人：%d～%d 级（你现在 %d 级）" % [loc.description, loc.level_min, loc.level_max, GameState.level]
	if not here:
		var route := _route_names(GameState.location_id, loc.id)
		desc += "\n怎么去：回到场景，从路口走上野外路%s" % ("：" + " → ".join(route) if route.size() > 1 else "")
	_panel_desc.text = desc
	for child in _panel_buttons.get_children():
		_panel_buttons.remove_child(child)
		child.queue_free()
	if not here:
		for story in GameDB.stories:
			if story.location == loc.id and GameState.story_available(story):
				_panel_buttons.add_child(UiKit.label("%s列传·%s（到了那里才能开始）" % [GameDB.hero(story.hero).display_name, story.title], 17, UiKit.GOLD))
		var back := UiKit.button("返回场景", Vector2(150, 52), 22)
		back.pressed.connect(func() -> void: back_requested.emit())
		_panel_buttons.add_child(back)
		_layout()
		return
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
			button.pressed.connect(func() -> void: story_requested.emit(story))
			_panel_buttons.add_child(button)
	if loc.has_inn and loc.id == GameState.location_id:
		var price := GameState.rest_price()
		var inn := UiKit.button("住店（%d 两）" % price if not GameState.vitality.is_empty() else "住店", Vector2(170, 52), 22)
		inn.disabled = GameState.vitality.is_empty() or GameState.silver < price
		inn.tooltip_text = "住一晚，全队气血回满；伤得越重越贵" if not GameState.vitality.is_empty() else "全队气血都是满的"
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
	var back := UiKit.button("返回场景", Vector2(150, 52), 22)
	back.pressed.connect(func() -> void: back_requested.emit())
	_panel_buttons.add_child(back)
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
		battle_requested.emit(b.stage, b.battle_bonus()))


func _refresh_status() -> void:
	_status.text = "Lv%d　经验 %d/%d　银两 %d　聚义令 %d" % [GameState.level, GameState.experience, GameState.exp_to_next(GameState.level), GameState.silver, GameState.tokens]


func _refresh_locks() -> void:
	for loc in map.locations:
		var open := GameState.has_flag(loc.unlock_flag)
		_clouds[loc.id].visible = not open
		_tags[loc.id].modulate = Color.WHITE if open else Color(1, 1, 1, 0.35)


func _open_settings() -> void:
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


## 从 from 到 to 经过的地点名字（按路网最少几段路）。
func _route_names(from: StringName, to: StringName) -> PackedStringArray:
	var came := {from: &""}
	var queue: Array[StringName] = [from]
	while not queue.is_empty():
		var at: StringName = queue.pop_front()
		if at == to:
			break
		for road in map.roads:
			var next: StringName = road.b if road.a == at else (road.a if road.b == at else &"")
			if next != &"" and not came.has(next):
				came[next] = at
				queue.append(next)
	var names := PackedStringArray()
	if not came.has(to):
		return names
	var at := to
	while at != &"":
		names.insert(0, map.location(at).display_name)
		at = came[at]
	return names
