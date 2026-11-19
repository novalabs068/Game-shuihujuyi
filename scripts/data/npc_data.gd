class_name NpcData
extends Resource
## 俯视场景里的一个人物。点他会走过去对话。

@export var id: StringName
@export var display_name: String
## 有对应好汉或敌人数据时，对话框显示其版画半身像，场景里也用他的头像
@export var unit: UnitData
## 场景里走动用的像素小人；不填就用 unit 的 map_sprite，再没有就画圆形头像
@export var sprite: Texture2D
@export var cell: Vector2i
## 对话台词，每行「说话人：台词」；说话人写「我」代表主角
@export var lines: PackedStringArray
