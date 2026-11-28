class_name LocationView
extends Control
## 可以自由行走的俯视场景：点地面走过去（自动寻路），点人物走到旁边对话，点宝箱打开，走到出口回江湖大地图。
## 地形来自 SceneData 的文字地图，用瓦片图集拼成 TileMapLayer；镜头跟着主角走。

signal exit_requested
## 支线事件里选了要打一仗；bonus 见 main.gd 的 _start_battle()
signal battle_requested(stage: StageData, bonus: Dictionary)
## 走进门里，换到另一个场景
signal scene_requested(scene_id: String)
## 打开江湖大地图看看（只能看，地点之间要从路口走过去）
signal map_requested
## 在场景里打开编队、好汉、招募（看完回到场景原地）
signal team_requested
signal heroes_requested
signal recruit_requested
signal jianghu_requested
## 左下「行囊」：看身上带的东西
signal bag_requested

## 像素瓦片放大倍数：16 像素的瓦片在画面上是 48 像素一格
const PIXEL_SCALE := 3
const WALK_SPEED := 230.0
const CAMERA_FOLLOW := 8.0

var scene_data: SceneData
## 进场景时先提示一句，比如支线战斗打赢后的结果
var notice := ""

var _tile := 48.0
var _world: Node2D
var _actors: Node2D
var _player: MapActor
var _npc_at: Dictionary[Vector2i, NpcData] = {}
var _chest_at: Dictionary[Vector2i, ChestData] = {}
var _chest_actors: Dictionary[Vector2i, MapActor] = {}
var _astar := AStarGrid2D.new()
var _path: Array[Vector2] = []
var _on_arrive: Callable
var _busy := false
var _marker: Node2D
var _dialogue: DialogueBox
var _event_panel: EventPanel
var _toast: Label
var _roamers: Array[SceneRoamer] = []
## 刚从战斗回来的几秒里小怪不追人，免得一回来又被碰上
var _grace := 0.0
const RETURN_GRACE := 2.5
## 有小怪离主角这么多格以内就不能歇脚
const CAMP_SAFE_CELLS := 5.0

## 正在歇脚时的天色、火光层、倒计时面板、站着时的小人图
var _resting := false
var _rest_sky: ColorRect
var _rest_lit: Node2D
var _rest_panel: PanelContainer
var _rest_label: Label
var _rest_standing: Texture2D


func _ready() -> void:
	_tile = scene_data.tile_pixels * PIXEL_SCALE
	var bg := ColorRect.new()
	bg.color = Color("1b1d22")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_world = Node2D.new()
	add_child(_world)
	_build_tiles()
	_build_pathfinding()
	_marker = _make_marker()
	_world.add_child(_marker)
	_actors = Node2D.new()
	_actors.y_sort_enabled = true
	_world.add_child(_actors)
	_spawn_objects()

	_build_ui()
	# 关掉游戏前在这里坐下歇脚的：站回原地接着歇（时间到了就直接歇好）
	if GameState.camp.get("scene", "") == scene_data.id:
		var c: Array = GameState.camp["cell"]
		_player.position = _feet(Vector2i(c[0], c[1]))
		_enter_rest.call_deferred()
	# 刚加进场景树时尺寸还是 0，等铺满屏幕后再把镜头对准主角
	resized.connect(_center_camera.bind(true))
	_center_camera(true)
	if notice != "":
		_flash(notice)


func _process(delta: float) -> void:
	_step_rest()
	_step_player(delta)
	_step_roamers(delta)
	_center_camera(false)
	if _minimap != null:
		_minimap.queue_redraw()


# --- 搭场景 ---

func _build_tiles() -> void:
	var px := scene_data.tile_pixels
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(px, px)
	var source := TileSetAtlasSource.new()
	source.texture = scene_data.tileset_texture
	source.texture_region_size = Vector2i(px, px)
	@warning_ignore("integer_division")
	var columns := scene_data.tileset_texture.get_width() / px
	@warning_ignore("integer_division")
	var tile_rows := scene_data.tileset_texture.get_height() / px
	for y in tile_rows:
		for x in columns:
			source.create_tile(Vector2i(x, y))
	tileset.add_source(source, 0)

	var layer := TileMapLayer.new()
	layer.tile_set = tileset
	layer.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var rows := scene_data.rows()
	for y in rows.size():
		for x in rows[y].length():
			var info: Dictionary = SceneData.TERRAIN.get(rows[y][x], SceneData.TERRAIN["#"])
			var block := scene_data.tile_block
			var tile: int = info["tile"]
			layer.set_cell(Vector2i(x, y), 0, Vector2i(tile * block + x % block, y % block))
	_world.add_child(layer)


func _build_pathfinding() -> void:
	_astar.region = Rect2i(Vector2i.ZERO, scene_data.size())
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	var size_cells := scene_data.size()
	for y in size_cells.y:
		for x in size_cells.x:
			var cell := Vector2i(x, y)
			_astar.set_point_solid(cell, not scene_data.is_walkable(cell))


func _spawn_objects() -> void:
	var rows := scene_data.rows()
	for y in rows.size():
		for x in rows[y].length():
			var overlay: Texture2D = scene_data.overlays.get(rows[y][x])
			if overlay != null:
				_actors.add_child(_pixel_sprite(overlay, _cell_bottom(Vector2i(x, y))))
	for prop in scene_data.props:
		_actors.add_child(_pixel_sprite(prop.texture, _cell_bottom(prop.cell) + prop.offset))
	for npc in scene_data.npcs:
		# 已经随行的好汉不再站在场景里
		if npc.unit != null and npc.unit.id in GameState.team_ids:
			continue
		if npc.hide_flag != "" and GameState.has_flag(npc.hide_flag):
			continue
		var actor := MapActor.new()
		actor.sprite = npc.sprite if npc.sprite != null else (npc.unit.map_sprite if npc.unit != null else null)
		actor.sprite_scale = MapActor.PIXEL_SCALE if npc.still else MapActor.CHARACTER_SCALE
		var face: Texture2D = npc.unit.face if npc.unit != null else null
		actor.setup(face, npc.display_name.right(1), Color("6b4f8a"), npc.display_name)
		actor.position = _feet(npc.cell)
		actor.facing_left = not npc.still
		_actors.add_child(actor)
		_npc_at[npc.cell] = npc
		_astar.set_point_solid(npc.cell, true)
	for chest in scene_data.chests:
		var actor := MapActor.new()
		var opened := GameState.has_flag(_chest_flag(chest))
		actor.sprite = scene_data.chest_open if opened else scene_data.chest_closed
		actor.setup(null, "空" if opened else "箱", Color("6e5a3a") if opened else Color("b8862e"), "")
		actor.position = _feet(chest.cell)
		_actors.add_child(actor)
		_chest_at[chest.cell] = chest
		_chest_actors[chest.cell] = actor
		_astar.set_point_solid(chest.cell, true)
	var me := GameState.protagonist()
	_player = MapActor.new()
	_player.sprite = me.map_sprite if me != null else null
	_player.sprite_scale = MapActor.CHARACTER_SCALE
	_player.setup(me.face if me != null else null, "我", UiKit.ACCENT, "")
	# 打完仗回来：站回原来的位置
	var memory := GameState.scene_state(scene_data.id)
	var back: Variant = memory["cell"]
	_player.position = _feet(back if back != null else scene_data.spawn_cell)
	if back != null:
		_grace = RETURN_GRACE
	memory["cell"] = null
	GameState.pending_roamer = []
	_actors.add_child(_player)
	_spawn_roamers(memory["cleared"])


## 左上：地区小印 + 黑漆匾（场景名）；右上：圆形小地图（点了看江湖大地图）；右边一列挂木签；
## 左下：歇脚铜钮 + 随行好汉的头像和气血。
func _build_ui() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", -4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	head.position = Vector2(16, 14)
	var parts := PackedStringArray([scene_data.title])
	for sep in [" · ", String.chr(0x30FB), "·"]:
		if scene_data.title.contains(sep):
			parts = scene_data.title.split(sep)
			break
	if parts.size() >= 2:
		var region_seal := UiKit.seal_label(parts[0].strip_edges(), 20, true)
		region_seal.rotation = deg_to_rad(-3)
		region_seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(region_seal)
	var plaque := UiKit.title_plaque(parts[parts.size() - 1].strip_edges(), 32)
	head.add_child(plaque)

	var guide_targets := {}
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 16)
	add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu.offset_left = -80
	menu.offset_right = -28
	menu.offset_top = 222
	for entry: Array in [["招募", recruit_requested, 1], ["好汉", heroes_requested, 4], ["编队", team_requested, 2], ["江湖榜", jianghu_requested, 5]]:
		var b := UiKit.slip_button(entry[0], 50, 24)
		var sig: Signal = entry[1]
		b.pressed.connect(func() -> void:
			if not _busy:
				_remember()
				sig.emit())
		menu.add_child(b)
		guide_targets[entry[2]] = b

	_build_minimap()

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	add_child(foot)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 16
	foot.offset_top = -92
	foot.offset_bottom = -16
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# 行囊：铜钱牌，挂在「歇脚」上面
	var bag := UiKit.copper_button("行囊", 76, 22)
	add_child(bag)
	bag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bag.offset_left = 16
	bag.offset_top = -184
	bag.offset_bottom = -108
	bag.offset_right = 92
	bag.pressed.connect(func() -> void:
		if not _busy:
			_remember()
			bag_requested.emit())
	var camp := UiKit.copper_button("歇脚", 76, 22)
	camp.tooltip_text = "就地打坐 %d 分钟，全队回复 %d%% 气血；一小时只能歇一次" % [Vitality.CAMP_SECONDS / 60, roundi(Vitality.CAMP_REGEN * 100)]
	camp.pressed.connect(_camp)
	foot.add_child(camp)
	var team := GameState.team()
	if not team.is_empty():
		var strip := PanelContainer.new()
		strip.add_theme_stylebox_override("panel", UiKit.lacquer_box())
		strip.size_flags_vertical = Control.SIZE_SHRINK_END
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		strip.add_child(row)
		for u in team:
			row.add_child(_team_face(u))
		foot.add_child(strip)
	_build_guide(guide_targets)
	_build_track()

	_toast = UiKit.brush_label("", 30, Color("f4e2b4"))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color("1a0f08"))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 140
	_toast.offset_left = -400
	_toast.offset_right = 400

	_dialogue = DialogueBox.new()
	add_child(_dialogue)
	_dialogue.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dialogue.offset_left = 40
	_dialogue.offset_right = -40
	_dialogue.offset_top = -200
	_dialogue.offset_bottom = -16

	_event_panel = EventPanel.new()
	add_child(_event_panel)
	_event_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 新手引导：顶栏下面一条提示，对应的按钮一闪一闪。
const GUIDE_TEXTS := {
	1: "新手引导 1/5：点右上角「招募」，用开局送的聚义令来两次五连，招几位好汉。",
	2: "新手引导 2/5：点「编队」，挑 3 位好汉出战（主角当统领，不上阵）。",
	3: "新手引导 3/5：去打一仗。点地面走动，碰到游荡的小怪就开打；走到地图边上的路口，就能上路去别的地方。",
	4: "新手引导 4/5：打赢了！点「好汉」看看：重复抽到的好汉会变成将魂，攒够了点亮勾玉；还能换装备、看天赋和组合技。",
	5: "新手引导 5/5：点「江湖榜」，里面列着眼下能做的事：悬赏、列传、宝箱、没去过的地方。看完之后，江湖就随你闯了！",
}


func _build_guide(targets: Dictionary) -> void:
	var step := GameState.tutorial_step()
	if step == 0:
		return
	# 宣纸字条，前面盖一方「引」字印
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiKit.note_box())
	add_child(bar)
	bar.position = Vector2(16, 86)
	bar.custom_minimum_size.x = 560
	bar.size.x = 560
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var mark := UiKit.seal_label("引", 18)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(mark)
	var text := UiKit.label(GUIDE_TEXTS[step], 16, UiKit.INK)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var skip := UiKit.button("跳过", Vector2(70, 36), 18)
	skip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	skip.pressed.connect(func() -> void:
		GameState.mark_tutorial("tut_done")
		bar.queue_free())
	row.add_child(skip)
	var target: Button = targets.get(step)
	if target != null:
		var pulse := target.create_tween().set_loops()
		pulse.tween_property(target, "modulate", Color(1.8, 1.5, 0.6), 0.5)
		pulse.tween_property(target, "modulate", Color.WHITE, 0.5)


## 指引（地图左上）：平时只挂一方红印（「上梁山」或正在追踪的那件事），印下写名望进度；
## 点一下展开成一张签条（写着下一步做什么），再点收起。展开还是收起记在设置里，下次进来照旧。
## 新手引导还没走完时不挂（引导字条占着同一个位置）。
const TRACK_PREF := "guide_open"
## 签条宽
const TRACK_WIDTH := 360.0
var _track_box: Control


func _build_track() -> void:
	if GameState.tutorial_step() != 0:
		return
	if _track_box != null:
		_track_box.queue_free()
	var info := GuideTrack.current()
	var open: bool = Prefs.get_value("ui", TRACK_PREF, false)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.position = Vector2(16, 86)
	add_child(box)
	_track_box = box
	# 红印 + 进度：点了展开或收起
	var stamp := VBoxContainer.new()
	stamp.add_theme_constant_override("separation", 2)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stamp.mouse_filter = Control.MOUSE_FILTER_STOP
	stamp.tooltip_text = "指引：点一下展开或收起"
	var seal := UiKit.seal_label(String(info["seal"]), 20, true)
	seal.rotation = deg_to_rad(-2)
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stamp.add_child(seal)
	if info["progress_text"] != "":
		var prog := UiKit.label(info["progress_text"], 13, Color("f4e2b4"))
		prog.add_theme_constant_override("outline_size", 4)
		prog.add_theme_color_override("font_outline_color", Color("1a0f08"))
		prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stamp.add_child(prog)
	UiKit.ignore_mouse(seal)
	for child in stamp.get_children():
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.button_index == MOUSE_BUTTON_LEFT and not click.pressed and not _busy:
			Prefs.set_value("ui", TRACK_PREF, not open)
			_build_track())
	box.add_child(stamp)
	if not open:
		return
	# 展开的签条：从哪阶到哪阶、名望进度条、下一步；点「江湖榜」看全部
	var note := PanelContainer.new()
	note.add_theme_stylebox_override("panel", UiKit.note_box())
	note.custom_minimum_size.x = TRACK_WIDTH
	note.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(note)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	note.add_child(v)
	var title := UiKit.brush_label(String(info["title"]), 22, UiKit.INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	if float(info["progress"]) >= 0.0 and info["progress_text"] != "":
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(TRACK_WIDTH - 40, 8)
		bar.value = float(info["progress"]) * 100.0
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color("d9c7a4")
		bg.set_corner_radius_all(4)
		var fill := StyleBoxFlat.new()
		fill.bg_color = UiKit.CINNABAR
		fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
		v.add_child(bar)
	var next := UiKit.label(String(info["next"]), 15, UiKit.INK)
	next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next.custom_minimum_size.x = TRACK_WIDTH - 40
	v.add_child(next)
	var more := UiKit.button("江湖榜", Vector2(96, 34), 16)
	more.size_flags_horizontal = Control.SIZE_SHRINK_END
	more.pressed.connect(func() -> void:
		if not _busy:
			_remember()
			jianghu_requested.emit())
	v.add_child(more)


## 小地图：一格画成 MINI_CELL 见方的色块，以主角为中心；朱点是自己，墨点是小怪，石青点是人物。
const MINI_SIZE := 150.0
const MINI_CELL := 5.0
const MINI_COLORS := {
	"~": Color("6f8c96"), "#": Color("5e4b38"), "H": Color("5e4b38"), "T": Color("4f5e3a"),
	"=": Color("7a6248"), "W": Color("6f8c96"), "P": Color("5e4b38"), "h": Color("8a7458"),
	"E": Color("b0281c"), "D": Color("c9a25a"),
}
var _minimap: Control
var _mini_rows: PackedStringArray


func _build_minimap() -> void:
	_mini_rows = scene_data.rows()
	var holder := Button.new()
	holder.flat = true
	holder.focus_mode = Control.FOCUS_NONE
	holder.tooltip_text = "打开江湖大地图"
	holder.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	holder.custom_minimum_size = Vector2(MINI_SIZE, MINI_SIZE + 22)
	add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	holder.offset_left = -MINI_SIZE - 30
	holder.offset_right = -30
	holder.offset_top = 18
	holder.pressed.connect(func() -> void:
		if not _busy:
			go_back())
	UiKit.click_sound(holder)
	var ring := Panel.new()
	var style := UiKit.box(Color("d9c9a3"), UiKit.GILT, 4, int(MINI_SIZE / 2))
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 10
	ring.add_theme_stylebox_override("panel", style)
	ring.size = Vector2(MINI_SIZE, MINI_SIZE)
	ring.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	holder.add_child(ring)
	_minimap = Control.new()
	_minimap.size = ring.size
	_minimap.draw.connect(_draw_minimap)
	ring.add_child(_minimap)
	var rim := Control.new()
	rim.size = ring.size
	rim.draw.connect(func() -> void:
		rim.draw_arc(rim.size / 2, MINI_SIZE / 2 - 2, 0, TAU, 48, Color("5a3a22"), 4.0, true)
		rim.draw_arc(rim.size / 2, MINI_SIZE / 2 - 6, 0, TAU, 48, Color(UiKit.GILT, 0.8), 1.5, true))
	holder.add_child(rim)
	var north := UiKit.brush_label("北", 16, Color("f4e2b4"))
	north.add_theme_constant_override("outline_size", 4)
	north.add_theme_color_override("font_outline_color", Color("1a0f08"))
	north.position = Vector2(MINI_SIZE / 2 - 8, -8)
	holder.add_child(north)
	var caption := UiKit.title_plaque("舆　图", 18)
	caption.position = Vector2(MINI_SIZE / 2 - 42, MINI_SIZE - 14)
	caption.custom_minimum_size.x = 84
	holder.add_child(caption)
	UiKit.ignore_mouse(holder)


func _draw_minimap() -> void:
	if _player == null:
		return
	var c := _minimap.size / 2
	var here := _player.position / _tile
	var reach := int(MINI_SIZE / MINI_CELL / 2) + 2
	var pc := Vector2i(floori(here.x), floori(here.y))
	var offset := (here - Vector2(pc)) * MINI_CELL
	for dy in range(-reach, reach + 1):
		var y := pc.y + dy
		if y < 0 or y >= _mini_rows.size():
			continue
		var line := _mini_rows[y]
		for dx in range(-reach, reach + 1):
			var x := pc.x + dx
			if x < 0 or x >= line.length():
				continue
			var color: Color = MINI_COLORS.get(line[x], Color("d9c9a3"))
			_minimap.draw_rect(Rect2(c + Vector2(dx, dy) * MINI_CELL - offset, Vector2(MINI_CELL, MINI_CELL)), color)
	for cell in _npc_at:
		_minimap.draw_circle(c + (Vector2(cell) + Vector2(0.5, 0.5) - here) * MINI_CELL, 3.0, UiKit.INDIGO)
	for r in _roamers:
		if r.actor.visible:
			_minimap.draw_circle(c + (r.actor.position - _player.position) / _tile * MINI_CELL, 3.2, Color("1f1712"))
	_minimap.draw_circle(c, 5.0, Color("fff3d6"))
	_minimap.draw_circle(c, 3.6, UiKit.CINNABAR)


## 随行好汉的小头像，下面一道气血；重伤的盖一方「伤」。
func _team_face(u: UnitData) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(46, 46)
	var frame := Panel.new()
	frame.size = Vector2(46, 46)
	holder.add_child(frame)
	frame.add_theme_stylebox_override("panel", UiKit.box(UiKit.PAPER, UiKit.GILT, 2, 23))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var face := UiKit.unit_picture(u, 42, false, true)
	face.position = Vector2(2, 2)
	face.size = Vector2(42, 42)
	frame.add_child(face)
	v.add_child(holder)
	var hp := ProgressBar.new()
	hp.custom_minimum_size = Vector2(46, 5)
	var ratio := GameState.vitality_of(u.id)
	UiKit.style_bar(hp, Color("6f9a4e") if not Vitality.is_wounded(ratio) else UiKit.CINNABAR, false)
	hp.max_value = 1.0
	hp.step = 0.01
	hp.value = ratio
	v.add_child(hp)
	if Vitality.is_wounded(ratio):
		frame.modulate = Color(0.75, 0.7, 0.7)
		var mark := UiKit.seal_label("伤", 12)
		mark.position = Vector2(30, -6)
		mark.rotation = deg_to_rad(8)
		holder.add_child(mark)
	UiKit.ignore_mouse(v)
	return v


func _make_marker() -> Node2D:
	var marker := Node2D.new()
	marker.visible = false
	marker.draw.connect(func() -> void:
		marker.draw_arc(Vector2.ZERO, _tile * 0.32, 0, TAU, 24, Color(1, 1, 1, 0.8), 3.0))
	return marker


# --- 点击 ---

func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or _busy:
		return
	var cell := _cell_at(click.position - _world.position)
	if _npc_at.has(cell):
		_approach(cell, _talk.bind(_npc_at[cell]))
	elif _chest_at.has(cell):
		_approach(cell, _open_chest.bind(_chest_at[cell]))
	elif scene_data.is_walkable(cell):
		_walk_to(cell, Callable())


## 走到 target 旁边一格再执行 action；已经挨着就直接执行。
func _approach(target: Vector2i, action: Callable) -> void:
	var here := _cell_at(_player.position)
	if _adjacent(here, target):
		_face(target)
		action.call()
		return
	var best := Vector2i(-1, -1)
	var best_len := 1 << 30
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var spot := target + Vector2i(dx, dy)
			if spot == target or not _astar.is_in_boundsv(spot) or _astar.is_point_solid(spot):
				continue
			var path := _astar.get_id_path(here, spot)
			if not path.is_empty() and path.size() < best_len:
				best = spot
				best_len = path.size()
	if best.x >= 0:
		_walk_to(best, func() -> void:
			_face(target)
			action.call())


func _walk_to(cell: Vector2i, on_arrive: Callable) -> void:
	var path := _astar.get_id_path(_cell_at(_player.position), cell)
	if path.is_empty():
		return
	_path.clear()
	for i in range(1, path.size()):
		_path.append(_feet(path[i]))
	_on_arrive = on_arrive
	_marker.position = _feet(cell) - Vector2(0, _tile * 0.1)
	_marker.visible = true
	_marker.queue_redraw()
	if _path.is_empty():
		_arrived()


func _step_player(delta: float) -> void:
	_player.moving = not _path.is_empty()
	if _path.is_empty():
		return
	var next := _path[0]
	var to := next - _player.position
	if absf(to.x) > 1.0:
		_player.facing_left = to.x < 0
	var step := _walk_speed() * delta
	if to.length() <= step:
		_player.position = next
		_path.remove_at(0)
		if _path.is_empty():
			_arrived()
	else:
		_player.position += to.normalized() * step
	_player.queue_redraw()


func _arrived() -> void:
	_marker.visible = false
	if _on_arrive.is_valid():
		var action := _on_arrive
		_on_arrive = Callable()
		action.call()
	else:
		var here := _cell_at(_player.position)
		if scene_data.doors.has(here):
			_go_to_scene(scene_data.doors[here], scene_data.door_arrivals.get(here, null))
		elif scene_data.terrain_at(here) == "E":
			if scene_data.exit_scene != "":
				_go_to_scene(scene_data.exit_scene, scene_data.exit_cell)
			else:
				_leave()


## 手机返回键：正在对话、开箱这类事情时不响应，否则打开大地图。
func go_back() -> void:
	if not _busy:
		_remember()
		map_requested.emit()


## 离开场景回大地图；小怪下次进来重新出现。
func _leave() -> void:
	GameState.scene_memory.erase(scene_data.id)
	exit_requested.emit()


## 走进另一个场景；cell 为空就站在那个场景的出生点。
func _go_to_scene(scene_id: String, cell: Variant) -> void:
	GameState.scene_memory.erase(scene_data.id)
	if cell != null:
		GameState.scene_state(scene_id)["cell"] = cell
	scene_requested.emit(scene_id)


## 骑着马走得快，小怪也不容易注意到（坐骑的「赶路」「遇敌」加成）。
func _walk_speed() -> float:
	var mount := GameState.mount()
	return WALK_SPEED * (1.0 + (mount.travel_speed if mount != null else 0.0))


func _aggro_cells() -> float:
	var mount := GameState.mount()
	return SceneRoamer.AGGRO_CELLS * (1.0 - (mount.encounter_cut if mount != null else 0.0))


# --- 场景小怪 ---

## 摆出场景里的小怪。上次离开时记下了的（打仗、看菜单回来），照原来的人马和位置摆。
func _spawn_roamers(cleared: Array) -> void:
	if scene_data.region == &"" or scene_data.roam_spots.is_empty():
		return
	var saved: Dictionary = GameState.scene_state(scene_data.id).get("roamers", {})
	for i in scene_data.roam_spots.size():
		if i in cleared:
			continue
		_spawn_roamer(i, saved.get(i, {}))


func _spawn_roamer(i: int, saved: Dictionary) -> void:
	var loc: LocationData = GameDB.maps[GameState.DEFAULT_MAP].location(scene_data.region)
	var stage: StageData = saved.get("stage")
	if stage == null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var groups := scene_data.roam_groups if not scene_data.roam_groups.is_empty() else loc.encounter_groups
		var bonus := scene_data.roam_bonus[i] if i < scene_data.roam_bonus.size() else 0
		stage = Encounters.build_from(groups, loc.level_min, loc.level_max, GameState.level, rng, bonus, loc.danger)
	var lead: UnitData = stage.enemies[0]
	var actor := MapActor.new()
	for e in stage.enemies:
		if e.map_sprite != null:
			actor.sprite = e.map_sprite
			break
	actor.sprite_scale = MapActor.CHARACTER_SCALE
	var elite := lead.elite_trait != &""
	actor.setup(lead.face, lead.display_name.left(1), UiKit.ENEMY, "%s %d级" % [lead.display_name, stage.enemy_level])
	actor.caption_color = UiKit.BOSS if elite else Color("ffb0a0")
	var cell: Vector2i = saved.get("cell", scene_data.roam_spots[i])
	actor.position = _feet(cell)
	_actors.add_child(actor)
	_roamers.append(SceneRoamer.new(i, stage, actor, scene_data.roam_spots[i]))


func _step_roamers(delta: float) -> void:
	if _busy:
		for r in _roamers:
			r.actor.moving = false
		return
	_grace = maxf(_grace - delta, 0.0)
	for r in _roamers:
		var dist := r.actor.position.distance_to(_player.position) / _tile
		if _grace <= 0.0 and dist < SceneRoamer.CONTACT_CELLS:
			_fight(r)
			return
		if _grace <= 0.0 and (dist < _aggro_cells() or (r.chasing and dist < SceneRoamer.GIVE_UP_CELLS)):
			if not r.chasing:
				r.chasing = true
				r.actor.alert(true)
			r.repath -= delta
			if r.repath <= 0.0:
				r.repath = SceneRoamer.REPATH_SECONDS
				r.path = _path_between(_cell_at(r.actor.position), _cell_at(_player.position))
				# 最后一步直接扑向主角站的位置
				r.path.append(_player.position)
		else:
			if r.chasing:
				r.chasing = false
				r.actor.alert(false)
				r.path.clear()
			if r.path.is_empty():
				r.wait -= delta
				if r.wait <= 0.0:
					r.wait = randf_range(1.0, 3.0)
					r.path = _path_between(_cell_at(r.actor.position), _wander_target(r.home))
		r.walk(delta)


## 出生点附近随便挑一个能走到的格子。
func _wander_target(home: Vector2i) -> Vector2i:
	for attempt in 8:
		var cell := home + Vector2i(randi_range(-SceneRoamer.WANDER_RADIUS, SceneRoamer.WANDER_RADIUS), randi_range(-SceneRoamer.WANDER_RADIUS, SceneRoamer.WANDER_RADIUS))
		if _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell):
			return cell
	return home


func _path_between(from: Vector2i, to: Vector2i) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not _astar.is_in_boundsv(from) or not _astar.is_in_boundsv(to):
		return out
	var ids := _astar.get_id_path(from, to)
	for i in range(1, ids.size()):
		out.append(_feet(ids[i]))
	return out


## 离开这个画面一会儿（开打、看菜单）之前，记下主角和每只小怪站在哪、是哪伙人，回来时原样摆回去。
func _remember() -> void:
	var memory := GameState.scene_state(scene_data.id)
	memory["cell"] = _cell_at(_player.position)
	var saved := {}
	for r in _roamers:
		saved[r.index] = {"cell": _cell_at(r.actor.position), "stage": r.stage}
	memory["roamers"] = saved


## 碰上小怪：记下主角站的位置，开打；打赢后 main 会把它记成已打败。
func _fight(r: SceneRoamer) -> void:
	_busy = true
	_path.clear()
	_player.moving = false
	_remember()
	GameState.pending_roamer = [scene_data.id, r.index]
	_flash("%s 冲了上来！" % r.stage.enemies[0].display_name)
	await get_tree().create_timer(0.5).timeout
	battle_requested.emit(r.stage, {})


# --- 歇脚 ---

## 随地歇脚：主角盘腿坐下打坐，天黑下来、身边生起篝火，身上一团气息随呼吸明暗。
## 要打坐真实的 5 分钟（Vitality.CAMP_SECONDS）：可以一直看着，也可以关掉游戏，回来时接着坐、到时间自动歇好；
## 中途点「起身」就不算。歇好了全队回一截气血，被打退的小怪也回来了；之后一小时内不能再歇。附近有小怪就歇不了。
func _camp() -> void:
	if _busy:
		return
	var wait := GameState.camp_cooldown_left()
	if wait > 0:
		_flash("刚歇过不久，还要再过 %s 才能歇" % _clock(wait))
		return
	for r in _roamers:
		if r.actor.position.distance_to(_player.position) / _tile < CAMP_SAFE_CELLS:
			_flash("附近有强人出没，没法安心歇脚")
			return
	GameState.start_camp(scene_data.id, _cell_at(_player.position))
	_enter_rest()


## 坐下、入夜、生火、运气，挂上倒计时。进场景时发现还在歇（关掉游戏前坐下的）也走这里。
func _enter_rest() -> void:
	_busy = true
	_path.clear()
	_player.moving = false
	# 天色：一层盖在场景上、在顶栏下面的颜色
	_rest_sky = ColorRect.new()
	_rest_sky.color = Color(0.04, 0.06, 0.16, 0.0)
	_rest_sky.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rest_sky)
	move_child(_rest_sky, _world.get_index() + 1)
	_rest_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 篝火、火光、气息画在天色上面（不被夜色压暗），和场景用同一个镜头位置
	_rest_lit = Node2D.new()
	_rest_lit.transform = _world.transform
	add_child(_rest_lit)
	move_child(_rest_lit, _rest_sky.get_index() + 1)
	var glow := _campfire_glow()
	glow.position = _player.position + Vector2(_tile * 1.5, 4)
	_rest_lit.add_child(glow)
	var fire := FxSprite.spawn(_rest_lit, "burning", glow.position, 2.2, false, 1)
	_rest_lit.modulate.a = 0.0
	# 盘腿坐下：身子一沉，换成打坐的样子
	_rest_standing = _player.sprite
	var sit := GameState.sit_sprite()
	await _sink(sit)
	var dusk := create_tween().set_parallel()
	dusk.tween_property(_rest_sky, "color:a", 0.62, 0.9)
	dusk.tween_property(_rest_lit, "modulate:a", 1.0, 0.6).set_delay(0.3)
	await dusk.finished
	# 运气调息：身上一团气息随呼吸明暗，光点从身边往上飘
	var qi := _qi_aura()
	qi.position = _player.position + Vector2(0, -_tile * 0.7)
	_rest_lit.add_child(qi)
	var motes := _qi_motes()
	motes.position = _player.position + Vector2(0, -_tile * 0.3)
	_rest_lit.add_child(motes)
	var breathe := qi.create_tween().set_loops()
	breathe.tween_property(qi, "modulate:a", 0.9, 0.8).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(qi, "modulate:a", 0.35, 0.8).set_trans(Tween.TRANS_SINE)
	# 倒计时和「起身」
	_rest_panel = PanelContainer.new()
	_rest_panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.08, 0.07, 0.1, 0.82), UiKit.GOLD, 2, 10))
	add_child(_rest_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_rest_panel.add_child(row)
	_rest_label = UiKit.label("", 24, Color("e8f0ff"))
	row.add_child(_rest_label)
	var up := UiKit.button("起身", Vector2(110, 48), 22)
	up.pressed.connect(func() -> void: _end_rest(false))
	row.add_child(up)
	# 放在顶栏下面：主角常常站在画面下半截，放底下会挡住打坐的人
	_rest_panel.z_index = 20
	_rest_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_rest_panel.offset_top = 80
	_rest_panel.offset_bottom = 140
	_rest_panel.offset_left = -260
	_rest_panel.offset_right = 260
	_resting = true


func _step_rest() -> void:
	if _rest_lit != null and is_instance_valid(_rest_lit):
		_rest_lit.transform = _world.transform
	if not _resting:
		return
	var left := GameState.camp_time_left()
	_rest_label.text = "打坐调息　%s　（关掉游戏也照算）" % _clock(left)
	if left <= 0:
		_end_rest(true)


## 歇好（healed）或中途起身：天亮、熄火、站起来。歇好的才回血，被打退的小怪也回来。
func _end_rest(healed: bool) -> void:
	if not _resting:
		return
	_resting = false
	_rest_panel.queue_free()
	var came_back: Array = []
	if healed:
		GameState.finish_camp()
		var memory := GameState.scene_state(scene_data.id)
		came_back = memory["cleared"].duplicate()
		memory["cleared"].clear()
	else:
		GameState.cancel_camp()
	# 天亮：先一抹暖色，再回到白天
	var dawn := create_tween()
	dawn.tween_property(_rest_sky, "color", Color(1.0, 0.72, 0.45, 0.28) if healed else Color(0.04, 0.06, 0.16, 0.3), 0.9)
	dawn.parallel().tween_property(_rest_lit, "modulate:a", 0.0, 0.9)
	dawn.tween_property(_rest_sky, "color:a", 0.0, 0.7)
	await dawn.finished
	_rest_sky.queue_free()
	_rest_lit.queue_free()
	await _sink(_rest_standing)
	for i in came_back:
		_spawn_roamer(i, {})
	_grace = RETURN_GRACE
	_busy = false
	if healed:
		var text := "歇好了，全队气血回复 %d%%。一个时辰（一小时）后才能再歇。" % roundi(Vitality.CAMP_REGEN * 100)
		if not came_back.is_empty():
			text += "被打退的强人又回来了。"
		_flash(text)
	else:
		_flash("起身了，这次没歇成")


## 「4:32」「1 小时 05 分」这样的时长。
static func _clock(seconds: int) -> String:
	if seconds >= 3600:
		return "%d 小时 %02d 分" % [seconds / 3600, (seconds % 3600) / 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


## 篝火照亮的一圈暖光（叠加混合）。
func _campfire_glow() -> Sprite2D:
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size / 2.0
	for y in size:
		for x in size:
			var t := clampf(1.0 - Vector2(x + 0.5 - r, y + 0.5 - r).length() / r, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.62, 0.25, t * t * 0.55))
	var glow := Sprite2D.new()
	glow.texture = ImageTexture.create_from_image(img)
	glow.scale = Vector2(5, 3.2)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	return glow


## 坐下或站起：身子往下一沉，换成 to 这张图，再回弹。to 为空就只沉一下。
func _sink(to: Texture2D) -> void:
	var t := _player.create_tween()
	t.tween_property(_player, "scale", Vector2(1.08, 0.86), 0.14).set_ease(Tween.EASE_IN)
	await t.finished
	if to != null:
		_player.sprite = to
		_player.queue_redraw()
	var back := _player.create_tween()
	back.tween_property(_player, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await back.finished


## 打坐时身上的一团气：青白色、中间亮边上淡（叠加混合），夜里也把人照亮。
func _qi_aura() -> Sprite2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length() / r
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.7, 0.88, 1.0, a * a * 0.5))
	var qi := Sprite2D.new()
	qi.texture = ImageTexture.create_from_image(img)
	qi.scale = Vector2(_tile / 22.0, _tile / 20.0)
	qi.modulate.a = 0.35
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	qi.material = mat
	return qi


## 打坐时从身边慢慢往上飘的光点。
func _qi_motes() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 18
	p.lifetime = 1.8
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(_tile * 0.5, 4)
	p.direction = Vector2(0, -1)
	p.spread = 12.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 45.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = Color(0.8, 0.95, 1.0)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	return p


# --- 互动 ---

func _talk(npc: NpcData) -> void:
	_busy = true
	var speakers := {npc.display_name: npc.unit, "我": GameState.protagonist()}
	await _dialogue.run(npc.lines, speakers)
	if npc.event != null and not GameState.has_flag("event_" + String(npc.event.id)):
		GameState.set_flag("event_" + String(npc.event.id))
		var choice := await _event_panel.ask(npc.event)
		if choice.battle != null:
			_event_panel.close()
			battle_requested.emit(choice.battle, Rewards.choice_bonus(choice))
			return
		var gained := Rewards.apply_choice(choice)
		GameState.save_game()
		await _event_panel.show_result(choice.result_text, gained)
	match npc.action:
		&"market":
			var market := MarketPanel.new()
			add_child(market)
			market.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			await market.closed
			market.queue_free()
		&"arena":
			var arena := ArenaPanel.new()
			add_child(arena)
			arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var picked_round := [0]
			arena.accepted.connect(func(n: int) -> void:
				picked_round[0] = n
				arena.closed.emit())
			await arena.closed
			arena.queue_free()
			if picked_round[0] > 0:
				GameState.scene_state(scene_data.id)["cell"] = _cell_at(_player.position)
				battle_requested.emit(Arena.stage(picked_round[0]), Arena.battle_bonus(picked_round[0]))
				return
		&"bounties":
			var board := BountyBoard.new()
			board.bounties = GameDB.open_bounties(scene_data.region)
			board.region = scene_data.region
			add_child(board)
			board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var picked: Array = [null]
			board.accepted.connect(func(b: BountyData) -> void:
				picked[0] = b
				board.closed.emit())
			await board.closed
			board.queue_free()
			if picked[0] != null:
				var b: BountyData = picked[0]
				GameState.scene_state(scene_data.id)["cell"] = _cell_at(_player.position)
				battle_requested.emit(b.stage, b.battle_bonus())
				return
	_busy = false


func _open_chest(chest: ChestData) -> void:
	var flag := _chest_flag(chest)
	if GameState.has_flag(flag):
		_flash("箱子是空的")
		return
	GameState.set_flag(flag)
	var gained := Rewards.grant(chest.tokens, chest.silver, 0, chest.equipment, chest.medicine, chest.medicine_count)
	if randf() < Miji.CHEST_DROP_CHANCE:
		var scroll_text := Rewards.grant_pages(Books.CHEST_PAGES)
		if scroll_text != "":
			gained += "　" + scroll_text
	var mingqi := GameState.claim_mingqi()
	if mingqi != "":
		gained = mingqi + "　" + gained
	GameState.save_game()
	_chest_actors[chest.cell].sprite = scene_data.chest_open
	_chest_actors[chest.cell].set_glyph("空", Color("6e5a3a"))
	_flash("打开宝箱：%s" % gained)


func _chest_flag(chest: ChestData) -> String:
	return "chest_%s_%s" % [scene_data.id, chest.id]


func _flash(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var t := _toast.create_tween()
	t.tween_interval(1.2)
	t.tween_property(_toast, "modulate:a", 0.0, 0.4)


# --- 工具 ---

## 像素物件图：底边中点放在 bottom，放大到和瓦片同样的倍数。
func _pixel_sprite(texture: Texture2D, bottom: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	s.offset = Vector2(-texture.get_width() / 2.0, -texture.get_height())
	s.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = bottom
	return s


func _cell_bottom(cell: Vector2i) -> Vector2:
	return Vector2(cell) * _tile + Vector2(_tile * 0.5, _tile * 0.95)


func _feet(cell: Vector2i) -> Vector2:
	return Vector2(cell) * _tile + Vector2(_tile * 0.5, _tile * 0.8)


func _cell_at(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / _tile), floori((world_pos.y - 1.0) / _tile))


func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return maxi(absi(a.x - b.x), absi(a.y - b.y)) == 1


func _face(cell: Vector2i) -> void:
	var dx := _feet(cell).x - _player.position.x
	if absf(dx) > 1.0:
		_player.facing_left = dx < 0
		_player.queue_redraw()


## 让主角留在画面中间；地图比屏幕小的方向就居中，不露出地图外面。
func _center_camera(snap: bool) -> void:
	var map_px := Vector2(scene_data.size()) * _tile
	var target := size / 2 - _player.position
	for axis in 2:
		if map_px[axis] <= size[axis]:
			target[axis] = (size[axis] - map_px[axis]) / 2
		else:
			target[axis] = clampf(target[axis], size[axis] - map_px[axis], 0.0)
	if snap:
		_world.position = target.round()
	else:
		_world.position = _world.position.lerp(target, clampf(CAMERA_FOLLOW * get_process_delta_time(), 0.0, 1.0)).round()
