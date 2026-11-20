class_name LocationView
extends Control
## 可以自由行走的俯视场景：点地面走过去（自动寻路），点人物走到旁边对话，点宝箱打开，走到出口回江湖大地图。
## 地形来自 SceneData 的文字地图，用瓦片图集拼成 TileMapLayer；镜头跟着主角走。

signal exit_requested
## 支线事件里选了要打一仗；bonus 见 main.gd 的 _start_battle()
signal battle_requested(stage: StageData, bonus: Dictionary)
## 走进门里，换到另一个场景
signal scene_requested(scene_id: String)

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
	if notice != "":
		_flash(notice)


func _process(delta: float) -> void:
	_step_player(delta)
	_step_roamers(delta)
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
	var team := GameState.team()
	_player = MapActor.new()
	_player.sprite = team[0].map_sprite if not team.is_empty() else null
	_player.sprite_scale = MapActor.CHARACTER_SCALE
	_player.setup(team[0].face if not team.is_empty() else null, "我", UiKit.ACCENT, "")
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
	var hint := UiKit.label("点地面走动，点人物对话；碰到游荡的小怪就开打", 17, UiKit.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	var leave := UiKit.button("离开", Vector2(100, 40), 20)
	leave.pressed.connect(func() -> void:
		if not _busy:
			_leave())
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

	_event_panel = EventPanel.new()
	add_child(_event_panel)
	_event_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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
	else:
		var here := _cell_at(_player.position)
		if scene_data.doors.has(here):
			_go_to_scene(scene_data.doors[here], null)
		elif scene_data.terrain_at(here) == "E":
			if scene_data.exit_scene != "":
				_go_to_scene(scene_data.exit_scene, scene_data.exit_cell)
			else:
				_leave()


## 手机返回键：正在对话、开箱这类事情时不响应，否则离开场景。
func go_back() -> void:
	if not _busy:
		_leave()


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


# --- 场景小怪 ---

func _spawn_roamers(cleared: Array) -> void:
	if scene_data.region == &"" or scene_data.roam_spots.is_empty():
		return
	var loc: LocationData = GameDB.maps[GameState.DEFAULT_MAP].location(scene_data.region)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in scene_data.roam_spots.size():
		if i in cleared:
			continue
		var groups := scene_data.roam_groups if not scene_data.roam_groups.is_empty() else loc.encounter_groups
		var bonus := scene_data.roam_bonus[i] if i < scene_data.roam_bonus.size() else 0
		var stage := Encounters.build_from(groups, loc.level_min, loc.level_max, GameState.level, rng, bonus)
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
		actor.position = _feet(scene_data.roam_spots[i])
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
		if _grace <= 0.0 and (dist < SceneRoamer.AGGRO_CELLS or (r.chasing and dist < SceneRoamer.GIVE_UP_CELLS)):
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


## 碰上小怪：记下主角站的位置，开打；打赢后 main 会把它记成已打败。
func _fight(r: SceneRoamer) -> void:
	_busy = true
	_path.clear()
	_player.moving = false
	var memory := GameState.scene_state(scene_data.id)
	memory["cell"] = _cell_at(_player.position)
	GameState.pending_roamer = [scene_data.id, r.index]
	_flash("%s 冲了上来！" % r.stage.enemies[0].display_name)
	await get_tree().create_timer(0.5).timeout
	battle_requested.emit(r.stage, {})


# --- 互动 ---

func _talk(npc: NpcData) -> void:
	_busy = true
	var team := GameState.team()
	var speakers := {npc.display_name: npc.unit, "我": team[0] if not team.is_empty() else null}
	await _dialogue.run(npc.lines, speakers)
	if npc.event != null and not GameState.has_flag("event_" + String(npc.event.id)):
		GameState.set_flag("event_" + String(npc.event.id))
		var choice := await _event_panel.ask(npc.event)
		if choice.battle != null:
			_event_panel.close()
			battle_requested.emit(choice.battle, WorldMapView._choice_bonus(choice))
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
	var gained := Rewards.grant(chest.tokens, chest.silver, 0, chest.equipment)
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
