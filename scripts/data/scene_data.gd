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
	"H": {"tile": 11, "walk": false}, # 建筑占地（上面摆 PropData 的建筑图）
	"D": {"tile": 8, "walk": true},   # 门：走到这里进 doors 里写的另一个场景
	"h": {"tile": 0, "walk": false},  # 小物件占地（摊子、木桶等）：地面还是草地，只是不能走
}

@export var id: String
@export var title: String
## 瓦片图集：每种地形一个图块，一行排开，顺序同 TERRAIN 的 tile 序号
@export var tileset_texture: Texture2D
## 每格的像素边长
@export var tile_pixels := 16
## 每个图块是 tile_block × tile_block 格的循环图案（地面就不会每格都一样）；1 表示每块就是一格
@export var tile_block := 1
@export_multiline var layout: String
@export var spawn_cell: Vector2i
@export var npcs: Array[NpcData] = []
@export var chests: Array[ChestData] = []
## 所属地区（大地图上的地点 id）：小怪按这里的遇敌表和等级生成，告示栏揭这里的悬赏
@export var region: StringName
## 小怪的出生点，每个一只；空的就没有小怪
@export var roam_spots: Array[Vector2i] = []
## 这个场景自己的小怪组合；空的就用所属地区的遇敌表
@export var roam_groups: Array[StageData] = []
## 每个出生点额外加几级（和 roam_spots 一一对应，缺的算 0）：场景越深处越强
@export var roam_bonus: Array[int] = []
## 门格子（地形 D）→ 进哪个场景（出现在那个场景的 spawn_cell）
@export var doors: Dictionary[Vector2i, String] = {}
## 走到出口（地形 E）去哪个场景、出现在哪一格；为空就回江湖大地图
@export var exit_scene: String
## 这个场景的配乐（audio/music/ 下的曲名）
@export var music: StringName = &"jieshi"
## 在这个场景里打仗用哪张背景（art/story/<名字>）；空的就用所属地区的
@export var battle_bg: StringName
@export var exit_cell: Vector2i

@export_group("像素图")
## 画在某种地形格子上的物件图，比如 "T" → 树、"W" → 水井；图的底边中点对齐格子底边中点
@export var overlays: Dictionary[String, Texture2D] = {}
@export var props: Array[PropData] = []
@export var chest_closed: Texture2D
@export var chest_open: Texture2D


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
