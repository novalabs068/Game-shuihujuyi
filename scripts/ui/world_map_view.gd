class_name WorldMapView
extends Control
## 江湖大地图：点地名看那里的情况，在所在的地点可以开列传、住店、逛集市、揭悬赏；
## 去别的地点要回到场景里，从路口走上野外路过去；去过的地方也可以用一张甲马直接到（见 Jiama）。

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
## 用甲马去一个去过的地方（main 扣一张、切到那里的场景）
signal jiama_requested(location_id: StringName)
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
var _exp_bar: ProgressBar
var _silver_row: HBoxContainer
var _token_row: HBoxContainer
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
	# 地名小竖幅：宣纸、石青包头、下面一根木轴，墨色毛笔字一字一行；危险几颗朱点
	var tag := PanelContainer.new()
	var flag := StyleBoxFlat.new()
	flag.bg_color = Color("efe3c6")
	flag.border_color = UiKit.INDIGO
	flag.border_width_top = 7
	flag.border_width_bottom = 5
	flag.border_color = UiKit.INDIGO
	flag.set_content_margin_all(4)
	flag.content_margin_top = 9
	flag.content_margin_bottom = 8
	flag.shadow_color = Color(0, 0, 0, 0.4)
	flag.shadow_size = 4
	flag.shadow_offset = Vector2(0, 3)
	tag.add_theme_stylebox_override("panel", flag)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	tag.add_child(column)
	var name_label := UiKit.brush_label(UiKit.vertical_text(loc.display_name), 24, UiKit.INK)
	name_label.add_theme_constant_override("line_spacing", -6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	var dots := Control.new()
	dots.custom_minimum_size = Vector2(26, loc.danger * 10)
	dots.draw.connect(func() -> void:
		for i in loc.danger:
			dots.draw_circle(Vector2(dots.size.x / 2, 5 + i * 10), 3.2, UiKit.CINNABAR))
	column.add_child(dots)
	_layer.add_child(tag)
	tag.position = loc.label_position - Vector2(20, 0)
	UiKit.ignore_mouse(tag)
	tag.gui_input.connect(_on_location_input.bind(loc))
	_tags[loc.id] = tag

	# 道路上的落脚点
	var dot := Panel.new()
	var pin := UiKit.box(CINNABAR, INK, 3, 13)
	pin.shadow_color = Color(PAPER, 0.85)
	pin.shadow_size = 3
	dot.add_theme_stylebox_override("panel", pin)
	dot.size = Vector2(24, 24)
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
	var ring := UiKit.box(PAPER, CINNABAR, 4, 36)
	ring.shadow_color = Color(1.0, 0.8, 0.45, 0.8)
	ring.shadow_size = 10
	frame.add_theme_stylebox_override("panel", ring)
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


## 左上：主角头像 + 黑漆名牌（点了进主角页）；中间题签；右上：家当、设置、「归」；右边一列挂木签（主菜单）。
func _build_top_bar() -> void:
	var me := GameState.protagonist()
	var profile := Button.new()
	profile.flat = true
	profile.focus_mode = Control.FOCUS_NONE
	profile.custom_minimum_size = Vector2(280, 88)
	profile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	profile.pressed.connect(func() -> void: profile_requested.emit())
	UiKit.click_sound(profile)
	add_child(profile)
	profile.position = Vector2(16, 12)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiKit.lacquer_box())
	plate.position = Vector2(66, 16)
	plate.custom_minimum_size = Vector2(196, 58)
	profile.add_child(plate)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	plate.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	info.add_child(name_row)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 14
	name_row.add_child(spacer)
	name_row.add_child(UiKit.brush_label(me.display_name if me != null else "", 28, Color("f1d99c")))
	_status = UiKit.label("", 14, Color("cdb68a"))
	_status.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(_status)
	_exp_bar = ProgressBar.new()
	_exp_bar.custom_minimum_size = Vector2(150, 6)
	UiKit.style_bar(_exp_bar, Color("e9c979"), false)
	var bar_row := HBoxContainer.new()
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.x = 14
	bar_row.add_child(spacer2)
	bar_row.add_child(_exp_bar)
	info.add_child(bar_row)
	var face_ring := Panel.new()
	var ring := UiKit.box(PAPER, UiKit.GILT, 3, 42)
	ring.shadow_color = Color(0, 0, 0, 0.5)
	ring.shadow_size = 6
	face_ring.add_theme_stylebox_override("panel", ring)
	face_ring.size = Vector2(84, 84)
	face_ring.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	profile.add_child(face_ring)
	var face := UiKit.picture(me.face if me != null else null, 78)
	face.position = Vector2(3, 3)
	face.size = Vector2(78, 78)
	face_ring.add_child(face)
	UiKit.ignore_mouse(profile)

	var title := UiKit.title_plaque("大宋江湖舆图", 26)
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 16
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.alignment = BoxContainer.ALIGNMENT_END
	add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -480
	right.offset_right = -16
	right.offset_top = 14
	var purse := PanelContainer.new()
	purse.add_theme_stylebox_override("panel", UiKit.lacquer_box())
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var purse_row := HBoxContainer.new()
	purse_row.add_theme_constant_override("separation", 18)
	purse.add_child(purse_row)
	_silver_row = UiKit.amount_row(UiKit.coin_icon(), "")
	purse_row.add_child(_silver_row)
	_token_row = UiKit.amount_row(UiKit.token_icon(), "")
	purse_row.add_child(_token_row)
	right.add_child(purse)
	var settings_button := UiKit.copper_button("设置", 46, 22, true)
	settings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings_button.pressed.connect(_open_settings)
	right.add_child(settings_button)
	var back := UiKit.back_button()
	back.tooltip_text = "回到场景"
	back.pressed.connect(func() -> void: back_requested.emit())
	right.add_child(back)
	_refresh_status()

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 20)
	add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu.offset_left = -78
	menu.offset_right = -24
	menu.offset_top = 112
	for item in [["招募", recruit_requested], ["好汉", heroes_requested], ["编队", team_requested], ["江湖榜", jianghu_requested]]:
		var slip := UiKit.slip_button(item[0])
		var sig: Signal = item[1]
		slip.pressed.connect(func() -> void: sig.emit())
		menu.add_child(slip)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_panel_title = UiKit.brush_label("", 30, INK)
	v.add_child(_panel_title)
	_panel_desc = UiKit.label("", 17, INK)
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
	_panel_title.text = "%s%s" % [loc.display_name, "　· 你在这里" if here else ""]
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
				_panel_buttons.add_child(UiKit.label("%s列传·%s（到了那里才能开始）" % [GameDB.hero(story.hero).display_name, story.title], 17, UiKit.CINNABAR))
		if GameState.has_flag("visited_" + String(loc.id)):
			var go := UiKit.button("使用甲马（%d）" % GameState.jiama, Vector2(200, 52), 22)
			go.disabled = GameState.jiama <= 0
			go.tooltip_text = "用一张甲马，直接到%s" % loc.display_name if GameState.jiama > 0 else "没有甲马：集市能买，招到戴宗后他每天写"
			go.pressed.connect(func() -> void: jiama_requested.emit(loc.id))
			_panel_buttons.add_child(go)
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
	_status.text = "%s级" % UiKit.cn_number(GameState.level)
	_exp_bar.max_value = GameState.exp_to_next(GameState.level)
	_exp_bar.value = GameState.experience
	_exp_bar.tooltip_text = "经验 %d / %d" % [GameState.experience, GameState.exp_to_next(GameState.level)]
	(_silver_row.get_child(1) as Label).text = str(GameState.silver)
	(_token_row.get_child(1) as Label).text = str(GameState.tokens)


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
