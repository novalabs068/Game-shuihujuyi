class_name Grid
## 战场棋盘：每方 2 排 × 3 路 = 6 格。格子写成 Vector2i(排, 路)：排 0 前排、1 后排；路 0 上、1 中、2 下。纯规则。

const ROWS := 2
const LANES := 3
## 自动摆位时先占哪一路：中路、上路、下路
const LANE_ORDER: Array[int] = [1, 0, 2]
const NONE := Vector2i(-1, -1)


## 全部 6 格（前排在前）。
static func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in ROWS:
		for l in LANE_ORDER:
			out.append(Vector2i(r, l))
	return out


static func valid(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < ROWS and c.y >= 0 and c.y < LANES


## 两格之间走几步（排差 + 路差）。
static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## 给还没站位的人找格子：大体型的先占中路一整路，其余按职业宜站的排、从中路往两边，排满了去另一排。
## units 里 row 为 -1 的才摆；taken 是已经被占的格子（会被改写）。摆不下的人 row 留 -1。
static func auto_place(units: Array[BattleUnit], taken: Dictionary) -> void:
	for u in units:
		if u.row >= 0 or not u.data.big:
			continue
		for l in LANE_ORDER:
			if not taken.has(Vector2i(0, l)) and not taken.has(Vector2i(1, l)):
				_put(u, Vector2i(0, l), taken)
				break
	for u in units:
		if u.row >= 0 or u.data.big:
			continue
		var home := Roles.home_row(u.data.role)
		for r in [home, 1 - home]:
			if u.row >= 0:
				break
			for l in LANE_ORDER:
				if not taken.has(Vector2i(r, l)):
					_put(u, Vector2i(r, l), taken)
					break


static func _put(u: BattleUnit, c: Vector2i, taken: Dictionary) -> void:
	u.row = c.x
	u.lane = c.y
	for cc in u.cells():
		taken[cc] = u


## 排名：「前排上路」
static func cell_name(c: Vector2i) -> String:
	return "%s排%s路" % ["前" if c.x == 0 else "后", ["上", "中", "下"][c.y]]
