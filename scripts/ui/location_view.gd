class_name LocationView
extends Control
## 可以自由行走的俯视场景：点地面走过去（自动寻路），点人物走到旁边对话，点宝箱打开，走到出口回江湖大地图。
## 地形来自 SceneData 的文字地图，用瓦片图集拼成 TileMapLayer；镜头跟着主角走。

signal exit_requested

## 像素瓦片放大倍数：16 像素的瓦片在画面上是 48 像素一格
const PIXEL_SCALE := 3
const WALK_SPEED := 230.0
const CAMERA_FOLLOW := 8.0

var scene_data: SceneData

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
var _toast: Label


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
	# 刚加进场景树时尺寸还是 0，等铺满屏幕后再把镜头对准主角
	resized.connect(_center_camera.bind(true))
	_center_camera(true)


func _process(delta: float) -> void:
	_step_player(delta)
	_center_camera(false)


# --- 搭场景 ---

func _build_tiles() -> void:
	var px := scene_data.tile_pixels
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(px, px)
	var source := TileSetAtlasSource.new()
	source.texture = scene_data.tileset_texture
	source.texture_region_size = Vector2i(px, px)
	@warning_ignore("integer_division")
	var count := scene_data.tileset_texture.get_width() / px
	for i in count:
		source.create_tile(Vector2i(i, 0))
	tileset.add_source(source, 0)

	var layer := TileMapLayer.new()
	layer.tile_set = tileset
	layer.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var rows := scene_data.rows()
	for y in rows.size():
		for x in rows[y].length():
			var info: Dictionary = SceneData.TERRAIN.get(rows[y][x], SceneData.TERRAIN["#"])
			layer.set_cell(Vector2i(x, y), 0, Vector2i(info["tile"], 0))
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
	for npc in scene_data.npcs:
		var actor := MapActor.new()
		var face: Texture2D = npc.unit.face if npc.unit != null else null
		actor.setup(face, npc.display_name.right(1), Color("6b4f8a"), npc.display_name)
		actor.position = _feet(npc.cell)
		actor.facing_left = true
		_actors.add_child(actor)
		_npc_at[npc.cell] = npc
		_astar.set_point_solid(npc.cell, true)
	for chest in scene_data.chests:
		var actor := MapActor.new()
		var opened := GameState.has_flag(_chest_flag(chest))
		actor.setup(null, "空" if opened else "箱", Color("6e5a3a") if opened else Color("b8862e"), "")
		actor.position = _feet(chest.cell)
		_actors.add_child(actor)
		_chest_at[chest.cell] = chest
		_chest_actors[chest.cell] = actor
		_astar.set_point_solid(chest.cell, true)
	var team := GameState.team()
	_player = MapActor.new()
	_player.setup(team[0].face if not team.is_empty() else null, "我", UiKit.ACCENT, "")
	_player.position = _feet(scene_data.spawn_cell)
	_actors.add_child(_player)


func _build_ui() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiKit.box(Color(0.12, 0.11, 0.1, 0.85), Color(0, 0, 0, 0), 0, 0))
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 56
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	var title := UiKit.label(scene_data.title, 26, UiKit.GOLD)
	row.add_child(title)
	var hint := UiKit.label("点地面走动，点人物对话，走到山门离开", 17, UiKit.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	var leave := UiKit.button("离开", Vector2(100, 40), 20)
	leave.pressed.connect(func() -> void:
		if not _busy:
			exit_requested.emit())
	row.add_child(leave)

	_toast = UiKit.label("", 28, UiKit.GOLD)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 90
	_toast.offset_left = -400
	_toast.offset_right = 400

	_dialogue = DialogueBox.new()
	add_child(_dialogue)
	_dialogue.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dialogue.offset_left = 40
	_dialogue.offset_right = -40
	_dialogue.offset_top = -200
	_dialogue.offset_bottom = -16


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
	if _path.is_empty():
		return
	var next := _path[0]
	var to := next - _player.position
	if absf(to.x) > 1.0:
		_player.facing_left = to.x < 0
	var step := WALK_SPEED * delta
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
	elif scene_data.terrain_at(_cell_at(_player.position)) == "E":
		exit_requested.emit()


# --- 互动 ---

func _talk(npc: NpcData) -> void:
	_busy = true
	var team := GameState.team()
	var speakers := {npc.display_name: npc.unit, "我": team[0] if not team.is_empty() else null}
	await _dialogue.run(npc.lines, speakers)
	_busy = false


func _open_chest(chest: ChestData) -> void:
	var flag := _chest_flag(chest)
	if GameState.has_flag(flag):
		_flash("箱子是空的")
		return
	GameState.set_flag(flag)
	GameState.save_game()
	_chest_actors[chest.cell].set_glyph("空", Color("6e5a3a"))
	_flash("获得：%s" % chest.reward_text)


func _chest_flag(chest: ChestData) -> String:
	return "chest_%s_%s" % [scene_data.id, chest.id]


func _flash(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var t := _toast.create_tween()
	t.tween_interval(1.2)
	t.tween_property(_toast, "modulate:a", 0.0, 0.4)


# --- 工具 ---

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
