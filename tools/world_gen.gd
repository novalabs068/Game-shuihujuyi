extends SceneTree
## 生成可以走遍的江湖：把 11 个地点的场景扩大（原来的场景当城镇核心，四周长出野外），
## 再给大地图上的每条路生成一张野外路图，地点和路图之间用边上的路口相连。
##
##     godot --headless --path . --script res://tools/world_gen.gd
##
## 原来的地点场景存在 tools/scene_cores/（每次都从它们重新生成，可以反复跑），生成结果写进 data/scenes/。
## 地形用噪声铺：树林、水塘、空地各成片；路口之间的土路按噪声弯弯曲曲；最后把走不到的空地填成树，
## 保证从出生点能走到每个路口、每个小怪、每个宝箱。同一个场景每次生成都一样（随机种子按场景 id 定）。

const CORES := "res://tools/scene_cores/"
const OUT := "res://data/scenes/"
## 地点场景至少这么大（原来的城镇放在正中，四周至少留这么多野外）
const LOCATION_SIZE := Vector2i(112, 80)
const MIN_WILD := Vector2i(22, 18)
## 野外路图的高度；宽度按大地图上这条路的长短算
const ROAD_HEIGHT := 46
const ROAD_WIDTH_RANGE := Vector2i(84, 150)
## 外圈一层树当围墙，路口在围墙上开口
const BORDER := 2
const GAP := 3
## 每多少格空地放一只小怪
const CELLS_PER_ROAMER := 260
const ROAM_SPACING := 7

var map: WorldMapData
## 每条路的规划：road → {"id", "size", "west_y", "east_y"}
var road_plan := {}
## 每个地点朝每条路的路口：[地点 id, 路 id] → 进地点时站的格子
var location_entry := {}
## 扩大后的地点场景：场景 id → 原来的城镇往里挪了多少格
var offsets := {}


func _initialize() -> void:
	map = load("res://data/maps/ch1.tres")
	for road in map.roads:
		_plan_road(road)
	for loc in map.locations:
		_expand_location(loc)
	for road in map.roads:
		_build_road(road)
	_patch_side_scenes()
	quit()


# --- 规划 ---

func _road_id(road: RoadData) -> String:
	return "road_%s_%s" % [road.a, road.b]


func _plan_road(road: RoadData) -> void:
	var rng := _rng(_road_id(road))
	var w := clampi(int(road.length() / 3.2), ROAD_WIDTH_RANGE.x, ROAD_WIDTH_RANGE.y)
	road_plan[road] = {
		"id": _road_id(road),
		"size": Vector2i(w, ROAD_HEIGHT),
		"west_y": ROAD_HEIGHT / 2 + rng.randi_range(-8, 8),
		"east_y": ROAD_HEIGHT / 2 + rng.randi_range(-8, 8),
	}


## 进路图时站的格子：从 a 那头进站在西口里面，从 b 那头进站在东口里面。
func _road_arrival(road: RoadData, from_location: StringName) -> Vector2i:
	var plan: Dictionary = road_plan[road]
	var size: Vector2i = plan["size"]
	if from_location == road.a:
		return Vector2i(BORDER + 1, plan["west_y"])
	return Vector2i(size.x - BORDER - 2, plan["east_y"])


func _rng(key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng


func _noise(key: String, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = hash(key)
	n.frequency = frequency
	n.fractal_octaves = 3
	return n


# --- 网格工具 ---

func _grid(size: Vector2i, fill: String) -> Array:
	var g := []
	for y in size.y:
		var row := []
		row.resize(size.x)
		row.fill(fill)
		g.append(row)
	return g


func _layout(g: Array) -> String:
	var lines := PackedStringArray()
	for row: Array in g:
		lines.append("".join(row))
	return "\n".join(lines)


func _walkable(ch: String) -> bool:
	return SceneData.TERRAIN.get(ch, {"walk": false})["walk"]


## filter() 出来的是无类型数组，转回 Array[Vector2i]。
func _cells(arr: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in arr:
		out.append(c)
	return out


func _in(g: Array, c: Vector2i) -> bool:
	return c.y >= 0 and c.y < g.size() and c.x >= 0 and c.x < g[0].size()


## 外圈 BORDER 格围上树。
func _wall(g: Array) -> void:
	var h := g.size()
	var w: int = g[0].size()
	for y in h:
		for x in w:
			if x < BORDER or y < BORDER or x >= w - BORDER or y >= h - BORDER:
				g[y][x] = "T"


## 在围墙上开一个 GAP 宽的口：side 是 "w"/"e"/"n"/"s"，at 是沿边的坐标（口的中间）。
## 返回 [口上最外面那排的门格子们, 口里面站的那一格]。
func _open_gap(g: Array, side: String, at: int) -> Array:
	var h := g.size()
	var w: int = g[0].size()
	var doors: Array[Vector2i] = []
	var inside := Vector2i.ZERO
	for k in range(-1, GAP - 1):
		for depth in BORDER + 1:
			var c := Vector2i.ZERO
			match side:
				"w": c = Vector2i(depth, at + k)
				"e": c = Vector2i(w - 1 - depth, at + k)
				"n": c = Vector2i(at + k, depth)
				"s": c = Vector2i(at + k, h - 1 - depth)
			g[c.y][c.x] = "D" if depth == 0 else ","
			if depth == 0:
				doors.append(c)
	match side:
		"w": inside = Vector2i(BORDER + 1, at)
		"e": inside = Vector2i(w - BORDER - 2, at)
		"n": inside = Vector2i(at, BORDER + 1)
		"s": inside = Vector2i(at, h - BORDER - 2)
	return [doors, inside]


## 用 A* 找一条弯弯曲曲的路：噪声大的地方走起来「贵」，路就会绕。blocked 里的格子和外圈围墙不能走；
## keep 里面（原来的城镇）只借道不重铺地面。
func _carve_path(g: Array, from: Vector2i, to: Vector2i, blocked: Dictionary, noise: FastNoiseLite, path_cells: Dictionary, keep := Rect2i()) -> void:
	var w: int = g[0].size()
	var h := g.size()
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, g[0].size(), g.size())
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in g.size():
		for x in g[0].size():
			var c := Vector2i(x, y)
			var wall: bool = (x < BORDER or y < BORDER or x >= w - BORDER or y >= h - BORDER) and g[y][x] == "T"
			if blocked.has(c) or wall:
				astar.set_point_solid(c, true)
			else:
				astar.set_point_weight_scale(c, 1.0 + 4.0 * (noise.get_noise_2d(x, y) * 0.5 + 0.5))
	astar.set_point_solid(from, false)
	astar.set_point_solid(to, false)
	var cells := astar.get_id_path(from, to)
	for c: Vector2i in cells:
		for d: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
			var p: Vector2i = c + d
			var wall := p.x < BORDER or p.y < BORDER or p.x >= w - BORDER or p.y >= h - BORDER
			if _in(g, p) and not blocked.has(p) and not wall and not keep.has_point(p) and g[p.y][p.x] != "D":
				g[p.y][p.x] = ","
				path_cells[p] = true


## 用噪声在 free 里的格子上铺成片的树和水：按比例取噪声最高的那些格子。
func _scatter(g: Array, free: Array[Vector2i], ch: String, coverage: float, noise: FastNoiseLite) -> void:
	if free.is_empty() or coverage <= 0.0:
		return
	var scored := []
	for c in free:
		scored.append([noise.get_noise_2d(c.x, c.y), c])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var n := int(scored.size() * coverage)
	for i in n:
		var c: Vector2i = scored[i][1]
		g[c.y][c.x] = ch


## 从 start 走得到的格子；走不到的空地填成树（免得小怪、宝箱刷在死角里）。
func _reachable(g: Array, start: Vector2i, fill_unreached := true) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var p: Vector2i = c + d
			if _in(g, p) and not seen.has(p) and _walkable(g[p.y][p.x]):
				seen[p] = true
				queue.append(p)
	if fill_unreached:
		for y in g.size():
			for x in g[0].size():
				var c := Vector2i(x, y)
				if not seen.has(c) and g[y][x] in [".", ","]:
					g[y][x] = "T"
	return seen


## 在 candidates 里挑一批彼此隔开 spacing 格的点，最多 count 个。
func _spread(candidates: Array[Vector2i], count: int, spacing: float, rng: RandomNumberGenerator, avoid: Array[Vector2i] = []) -> Array[Vector2i]:
	var pool := candidates.duplicate()
	var out: Array[Vector2i] = []
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Vector2i = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	for c: Vector2i in pool:
		if out.size() >= count:
			break
		var ok := true
		for o in out + avoid:
			if Vector2(c - o).length() < spacing:
				ok = false
				break
		if ok:
			out.append(c)
	return out


# --- 地点 ---

func _expand_location(loc: LocationData) -> void:
	var sd: SceneData = load(CORES + loc.scene_id + ".tres")
	var core := sd.rows()
	var core_size := Vector2i(core[0].length(), core.size())
	var size := Vector2i(maxi(LOCATION_SIZE.x, core_size.x + MIN_WILD.x * 2), maxi(LOCATION_SIZE.y, core_size.y + MIN_WILD.y * 2))
	var o := (size - core_size) / 2
	var rng := _rng(loc.id)
	var g := _grid(size, ".")
	_wall(g)
	# 原来的城镇摆在正中；它通往大地图的出口改成土路，接到野外
	var openings: Array[Vector2i] = []
	# 原来的出口通向别的小场景（比如东京街市通城外郊野）的，留着当门；通大地图的改成土路接到野外
	var side_doors: Dictionary[Vector2i, String] = {}
	var side_arrivals: Dictionary[Vector2i, Vector2i] = {}
	for y in core_size.y:
		for x in core_size.x:
			var ch := core[y][x]
			var c := Vector2i(x, y) + o
			if ch == "E":
				if sd.exit_scene != "":
					ch = "D"
					side_doors[c] = sd.exit_scene
					side_arrivals[c] = sd.exit_cell
				else:
					ch = ","
					openings.append(c)
			g[c.y][c.x] = ch
	# 原来地图最外一圈：是树就散开成空地，城镇和野外连成一片；是城墙就留着，在每个旧出口外面开一道城门
	for y in core_size.y:
		for x in core_size.x:
			if (x == 0 or y == 0 or x == core_size.x - 1 or y == core_size.y - 1) and g[y + o.y][x + o.x] == "T":
				g[y + o.y][x + o.x] = "."
	for i in openings.size():
		var e := openings[i] - o
		var edge := e
		var best := INF
		for cand: Vector2i in [Vector2i(e.x, 0), Vector2i(e.x, core_size.y - 1), Vector2i(0, e.y), Vector2i(core_size.x - 1, e.y)]:
			var dist := Vector2(cand - e).length()
			if dist < best:
				best = dist
				edge = cand
		var step := (edge - e).sign()
		var c := e
		while c != edge:
			c += step
			if not _walkable(g[c.y + o.y][c.x + o.x]):
				g[c.y + o.y][c.x + o.x] = ","
		openings[i] = edge + o
	var blocked := {}
	for y in core_size.y:
		for x in core_size.x:
			if not _walkable(g[y + o.y][x + o.x]):
				blocked[Vector2i(x, y) + o] = true
	var core_rect := Rect2i(o, core_size)
	# 每条路一个路口，开在朝那个邻居的那一边
	var gaps := []
	for road in map.roads:
		if road.a != loc.id and road.b != loc.id:
			continue
		var other := map.location(road.b if road.a == loc.id else road.a)
		var dir := (other.map_position - loc.map_position).normalized()
		var side := ""
		var at := 0
		if absf(dir.x) >= absf(dir.y) * 0.8:
			side = "e" if dir.x > 0 else "w"
			at = clampi(int(size.y / 2 + dir.y * (size.y / 2 - 10)), BORDER + 4, size.y - BORDER - 5)
		else:
			side = "s" if dir.y > 0 else "n"
			at = clampi(int(size.x / 2 + dir.x * (size.x / 2 - 12)), BORDER + 4, size.x - BORDER - 5)
		# 同一边上的路口至少隔 12 格
		for other_gap: Array in gaps:
			if other_gap[0] == side and absi(other_gap[1] - at) < 12:
				at = clampi(at + (12 if at >= other_gap[1] else -12), BORDER + 4, (size.y if side in ["w", "e"] else size.x) - BORDER - 5)
		gaps.append([side, at, road])
	var path_noise := _noise(String(loc.id) + "_path", 0.06)
	var path_cells := {}
	var door_map: Dictionary[Vector2i, String] = {}
	var arrivals: Dictionary[Vector2i, Vector2i] = {}
	var gap_insides: Array[Vector2i] = []
	for gap: Array in gaps:
		var opened := _open_gap(g, gap[0], gap[1])
		var road: RoadData = gap[2]
		var inside: Vector2i = opened[1]
		gap_insides.append(inside)
		location_entry[[loc.id, road]] = inside
		for d: Vector2i in opened[0]:
			door_map[d] = road_plan[road]["id"]
			arrivals[d] = _road_arrival(road, loc.id)
		# 城镇没有通野外的出口（四面城墙）：在朝这个路口的那面墙上开一道城门
		if openings.is_empty():
			openings.append(_punch_gate(g, o, core_size, inside, blocked))
		# 从最近的城镇出口修一条土路过去
		var start: Vector2i = openings[0]
		for p in openings:
			if Vector2(p - inside).length() < Vector2(start - inside).length():
				start = p
		_carve_path(g, start, inside, blocked, path_noise, path_cells, core_rect)
	# 野外：路两边留一格空地，其余按噪声铺树林和水塘（看原来的城镇多树多水，野外就跟着多）
	var free: Array[Vector2i] = []
	for y in range(BORDER, size.y - BORDER):
		for x in range(BORDER, size.x - BORDER):
			var c := Vector2i(x, y)
			if core_rect.grow(1).has_point(c) or g[y][x] != ".":
				continue
			var near_path := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if path_cells.has(c + d):
					near_path = true
			if not near_path:
				free.append(c)
	var trees := 0
	var water := 0
	for line in core:
		trees += line.count("T")
		water += line.count("~")
	var area := float(core_size.x * core_size.y)
	_scatter(g, free, "T", clampf(trees / area * 1.4 + 0.12, 0.18, 0.38), _noise(String(loc.id) + "_trees", 0.07))
	var water_free := _cells(free.filter(func(c: Vector2i) -> bool: return g[c.y][c.x] == "."))
	_scatter(g, water_free, "~", 0.14 if water / area > 0.03 else 0.04, _noise(String(loc.id) + "_water", 0.05))
	var spawn: Vector2i = sd.spawn_cell + o
	var reach := _reachable(g, spawn)
	# 小怪：原来的照搬，野外按面积多放，离城越远越强
	var spots: Array[Vector2i] = []
	var bonus: Array[int] = []
	for i in sd.roam_spots.size():
		spots.append(sd.roam_spots[i] + o)
		bonus.append(sd.roam_bonus[i] if i < sd.roam_bonus.size() else 0)
	var wild: Array[Vector2i] = []
	for c: Vector2i in reach:
		if not core_rect.grow(4).has_point(c) and g[c.y][c.x] in [".", ","] and not gap_insides.any(func(gi: Vector2i) -> bool: return Vector2(gi - c).length() < 6):
			wild.append(c)
	var center := Vector2(core_rect.get_center())
	var far := Vector2(size).length() / 2
	for c in _spread(wild, wild.size() / CELLS_PER_ROAMER, ROAM_SPACING, rng, spots):
		spots.append(c)
		bonus.append(roundi(lerpf(2.0, 13.0, clampf(Vector2(c).distance_to(center) / far, 0.0, 1.0))))
	# 宝箱：放在离城最远的那些空地上
	var chests: Array[ChestData] = []
	for chest in sd.chests:
		var moved: ChestData = chest.duplicate()
		moved.cell = chest.cell + o
		chests.append(moved)
	var deep := _cells(wild.filter(func(c: Vector2i) -> bool: return g[c.y][c.x] == "." and Vector2(c).distance_to(center) > far * 0.55))
	var k := 0
	for c in _spread(deep, 4, 14.0, rng, spots):
		chests.append(_wild_chest("%s_wild_%d" % [loc.id, k], c, loc.danger, k == 0))
		k += 1
	# 原来的人、物件、门都挪到新位置
	for npc in sd.npcs:
		npc.cell += o
	for prop in sd.props:
		prop.cell += o
	for d: Vector2i in side_doors:
		door_map[d] = side_doors[d]
		arrivals[d] = side_arrivals[d]
	for d: Vector2i in sd.doors:
		door_map[d + o] = sd.doors[d]
	for d: Vector2i in sd.door_arrivals:
		arrivals[d + o] = sd.door_arrivals[d]
	offsets[loc.scene_id] = o
	sd.layout = _layout(g)
	sd.spawn_cell = spawn
	sd.exit_cell = Vector2i.ZERO
	sd.exit_scene = ""
	sd.doors = door_map
	sd.door_arrivals = arrivals
	sd.roam_spots = spots
	sd.roam_bonus = bonus
	sd.chests = chests
	print("%s %s → %s, 路口 %d, 小怪 %d, 宝箱 %d, %s" % [loc.scene_id, core_size, size, gaps.size(), spots.size(), chests.size(), ResourceSaver.save(sd, OUT + loc.scene_id + ".tres")])


## 在城镇外墙上朝 toward 的那一面开一道城门：从墙上挑离 toward 最近、里面一格能走的那个墙格，
## 打通墙（城门两格宽），返回城门外面那一格（土路从这里接出去）。
func _punch_gate(g: Array, o: Vector2i, core_size: Vector2i, toward: Vector2i, blocked: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var inward := Vector2i.ZERO
	for y in core_size.y:
		for x in core_size.x:
			if x != 0 and y != 0 and x != core_size.x - 1 and y != core_size.y - 1:
				continue
			var c := Vector2i(x, y) + o
			var into := Vector2i(1 if x == 0 else (-1 if x == core_size.x - 1 else 0), 1 if y == 0 else (-1 if y == core_size.y - 1 else 0))
			if into.x != 0 and into.y != 0:
				continue
			if not _walkable(g[c.y + into.y][c.x + into.x]):
				continue
			var d := Vector2(c - toward).length()
			if d < best_d:
				best_d = d
				best = c
				inward = into
	var along := Vector2i(absi(inward.y), absi(inward.x))
	for c: Vector2i in [best, best + along]:
		g[c.y][c.x] = "_"
		blocked.erase(c)
	return best - inward


func _wild_chest(id: String, cell: Vector2i, danger: int, with_token: bool) -> ChestData:
	var chest := ChestData.new()
	chest.id = StringName(id)
	chest.cell = cell
	chest.silver = 25 * danger + (hash(id) % 20)
	chest.tokens = 1 if with_token else 0
	chest.medicine = [&"zhi_xue_cao", &"jin_chuang_yao", &"jin_chuang_yao", &"xu_ming_gao"][clampi(danger - 1, 0, 3)]
	chest.medicine_count = 2 if danger <= 2 else 1
	return chest


# --- 野外路 ---

func _build_road(road: RoadData) -> void:
	var plan: Dictionary = road_plan[road]
	var id: String = plan["id"]
	var size: Vector2i = plan["size"]
	var a := map.location(road.a)
	var b := map.location(road.b)
	# 地图图块、树、宝箱的样子借 a 那头的场景（雪地、黄土跟着走）
	var looks: SceneData = load(CORES + a.scene_id + ".tres")
	var rng := _rng(id)
	var g := _grid(size, ".")
	_wall(g)
	var west := _open_gap(g, "w", plan["west_y"])
	var east := _open_gap(g, "e", plan["east_y"])
	var path_cells := {}
	_carve_path(g, west[1], east[1], {}, _noise(id + "_path", 0.05), path_cells)
	var free: Array[Vector2i] = []
	for y in range(BORDER, size.y - BORDER):
		for x in range(BORDER, size.x - BORDER):
			var c := Vector2i(x, y)
			if g[y][x] != ".":
				continue
			var near_path := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if path_cells.has(c + d):
					near_path = true
			if not near_path:
				free.append(c)
	var watery := a.id == &"liangshan" or b.id == &"liangshan"
	_scatter(g, free, "T", 0.3, _noise(id + "_trees", 0.08))
	var water_free := _cells(free.filter(func(c: Vector2i) -> bool: return g[c.y][c.x] == "."))
	_scatter(g, water_free, "~", 0.16 if watery else 0.05, _noise(id + "_water", 0.05))
	# 过路人站在路中段旁边：先把他脚下和身前一格清成空地
	var along: Array = path_cells.keys()
	along.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.x < q.x)
	var mid: Vector2i = along[along.size() / 2]
	var traveller_cell := mid + Vector2i(0, -2)
	for d in [Vector2i(0, -2), Vector2i(0, -1)]:
		g[mid.y + d.y][mid.x + d.x] = "."
	var spawn: Vector2i = west[1]
	var reach := _reachable(g, spawn)
	# 两头哪边敌人弱，就按哪边的等级生成，越往强的那头加的级越多；敌人组合两头的都有
	var easy := a if a.level_min <= b.level_min else b
	var hard := b if easy == a else a
	var hard_east := hard == b
	var spread := float(hard.level_min - easy.level_min)
	var open_cells: Array[Vector2i] = []
	for c: Vector2i in reach:
		if g[c.y][c.x] in [".", ","] and c.x > BORDER + 6 and c.x < size.x - BORDER - 7:
			open_cells.append(c)
	var spots: Array[Vector2i] = []
	var bonus: Array[int] = []
	for c in _spread(open_cells, maxi(4, open_cells.size() / CELLS_PER_ROAMER), ROAM_SPACING + 2, rng):
		spots.append(c)
		var t := float(c.x) / size.x
		bonus.append(roundi(spread * 0.7 * (t if hard_east else 1.0 - t)))
	var groups: Array[StageData] = []
	groups.append_array(a.encounter_groups)
	groups.append_array(b.encounter_groups)
	var chests: Array[ChestData] = []
	var quiet := _cells(open_cells.filter(func(c: Vector2i) -> bool: return g[c.y][c.x] == "." and not path_cells.has(c)))
	var k := 0
	for c in _spread(quiet, 2, 20.0, rng, spots):
		chests.append(_wild_chest("%s_%d" % [id, k], c, maxi(a.danger, b.danger), false))
		k += 1
	var sd := SceneData.new()
	sd.id = id
	sd.title = "%s—%s道上" % [a.display_name, b.display_name]
	sd.tileset_texture = looks.tileset_texture
	sd.tile_pixels = looks.tile_pixels
	sd.tile_block = looks.tile_block
	sd.overlays = looks.overlays.duplicate()
	sd.chest_closed = looks.chest_closed
	sd.chest_open = looks.chest_open
	sd.layout = _layout(g)
	sd.spawn_cell = spawn
	sd.region = easy.id
	sd.roam_spots = spots
	sd.roam_bonus = bonus
	sd.roam_groups = groups
	sd.chests = chests
	sd.music = &"jiaoye"
	sd.battle_bg = easy.id
	var door_map: Dictionary[Vector2i, String] = {}
	var arrivals: Dictionary[Vector2i, Vector2i] = {}
	for d: Vector2i in west[0]:
		door_map[d] = a.scene_id
		arrivals[d] = location_entry[[a.id, road]]
	for d: Vector2i in east[0]:
		door_map[d] = b.scene_id
		arrivals[d] = location_entry[[b.id, road]]
	sd.doors = door_map
	sd.door_arrivals = arrivals
	sd.npcs = _travellers(road, traveller_cell, looks)
	print("%s %s, 小怪 %d, 宝箱 %d, 路人 %d, %s" % [id, size, spots.size(), chests.size(), sd.npcs.size(), ResourceSaver.save(sd, OUT + id + ".tres")])


## 路上的过路人：原来赶路时随机碰上的奇遇，现在站在路边等你去搭话。每条路挑一件（按路定，不重样）。
func _travellers(road: RoadData, cell: Vector2i, looks: SceneData) -> Array[NpcData]:
	var out: Array[NpcData] = []
	var events: Array[EventData] = []
	for f in DirAccess.get_files_at("res://data/events"):
		if f.ends_with(".tres"):
			var e: EventData = load("res://data/events/" + f)
			if e.locations.is_empty() or road.a in e.locations or road.b in e.locations:
				events.append(e)
	if events.is_empty():
		return out
	events.sort_custom(func(x: EventData, y: EventData) -> bool: return String(x.id) < String(y.id))
	var event: EventData = events[absi(hash(_road_id(road))) % events.size()]
	var npc := NpcData.new()
	npc.id = &"traveller"
	npc.display_name = "过路人"
	npc.cell = cell
	npc.event = event
	if event.once:
		npc.hide_flag = "event_" + String(event.id)
	npc.lines = PackedStringArray(["过路人：这位好汉，留步！"])
	for n in looks.npcs:
		if n.sprite != null and n.event == null and n.action == &"":
			npc.sprite = n.sprite
			break
	out.append(npc)
	return out


## 没扩大的小场景（东京郊外、相国寺……）：通进扩大了的场景的格子跟着挪；
## 原来通回江湖大地图的出口，改成通回从哪个地点进来的那个地点（站在那扇门旁边）。
func _patch_side_scenes() -> void:
	var generated := {}
	for loc in map.locations:
		generated[loc.scene_id] = true
	for road in map.roads:
		generated[road_plan[road]["id"]] = true
	for f in DirAccess.get_files_at(OUT):
		if not f.ends_with(".tres") or generated.has(f.get_basename()):
			continue
		var sd: SceneData = load(OUT + f)
		var changed := false
		if offsets.has(sd.exit_scene):
			sd.exit_cell += offsets[sd.exit_scene]
			changed = true
		var arrivals: Dictionary[Vector2i, Vector2i] = {}
		for d: Vector2i in sd.door_arrivals:
			var target: String = sd.doors.get(d, "")
			arrivals[d] = sd.door_arrivals[d] + (offsets[target] if offsets.has(target) else Vector2i.ZERO)
			changed = changed or offsets.has(target)
		sd.door_arrivals = arrivals
		if sd.exit_scene == "" and sd.layout.contains("E"):
			# 找哪个地点场景有门通到这里：出口就通回那里，站在那扇门旁边
			for loc in map.locations:
				var home: SceneData = load(OUT + loc.scene_id + ".tres")
				for d: Vector2i in home.doors:
					if home.doors[d] == sd.id:
						sd.exit_scene = loc.scene_id
						sd.exit_cell = _beside(home, d)
						changed = true
		if changed:
			print("%s 出口 → %s %s, %s" % [sd.id, sd.exit_scene, sd.exit_cell, ResourceSaver.save(sd)])


## 门旁边一格能站的地方（优先门下面，就是从门里走出来的方向）。
func _beside(sd: SceneData, door: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if sd.is_walkable(door + d) and sd.terrain_at(door + d) != "D":
			return door + d
	return sd.spawn_cell
