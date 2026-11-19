class_name NpcData
extends Resource
## 俯视场景里的一个人物。点他会走过去对话。

@export var id: StringName
@export var display_name: String
## 有对应好汉或敌人数据时，对话框显示其版画半身像，场景里也用他的头像
@export var unit: UnitData
@export var cell: Vector2i
## 对话台词，每行「说话人：台词」；说话人写「我」代表主角
@export var lines: PackedStringArray
