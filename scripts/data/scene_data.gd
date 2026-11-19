class_name SceneData
extends Resource
## 一个可以自由行走的俯视场景。地形用文字画：一个字符一格，含义见 TERRAIN。

## 字符 → 瓦片图集里的序号，以及能不能走
const TERRAIN := {
	".": {"tile": 0, "walk": true},   # 草地
	",": {"tile": 1, "walk": true},   # 土路
	"~": {"tile": 2, "walk": false},  # 水
	"#": {"tile": 3, "walk": false},  # 墙、建筑
	"T": {"tile": 4, "walk": false},  # 树
	"=": {"tile": 5, "walk": false},  # 篱笆
	"F": {"tile": 6, "walk": true},   # 菜地
	"E": {"tile": 7, "walk": true},   # 出口，走到这里回到江湖大地图
	"_": {"tile": 8, "walk": true},   # 石板地
	"W": {"tile": 9, "walk": false},  # 水井
	"P": {"tile": 10, "walk": false}, # 粪窖
}

@export var id: String
@export var title: String
## 瓦片图集：一行排开，每块 tile_pixels 见方，顺序同 TERRAIN 的 tile 序号
@export var tileset_texture: Texture2D
@export var tile_pixels := 16
@export_multiline var layout: String
@export var spawn_cell: Vector2i
@export var npcs: Array[NpcData] = []
@export var chests: Array[ChestData] = []


func rows() -> PackedStringArray:
	var out := PackedStringArray()
	for line in layout.split("\n"):
		if line.strip_edges() != "":
			out.append(line.strip_edges())
	return out


func size() -> Vector2i:
	var r := rows()
	return Vector2i(r[0].length() if not r.is_empty() else 0, r.size())


func terrain_at(cell: Vector2i) -> String:
	var r := rows()
	if cell.y < 0 or cell.y >= r.size() or cell.x < 0 or cell.x >= r[cell.y].length():
		return "#"
	return r[cell.y][cell.x]


func is_walkable(cell: Vector2i) -> bool:
	var info: Dictionary = TERRAIN.get(terrain_at(cell), {"walk": false})
	return info["walk"]
