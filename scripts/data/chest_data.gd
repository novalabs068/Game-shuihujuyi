class_name ChestData
extends Resource
## 俯视场景里的一个宝箱。打开后设置标记 "chest_<场景 id>_<id>"，存档后不会再出现奖励。

@export var id: StringName
@export var cell: Vector2i
@export var reward_text: String
@export var tokens := 0
@export var silver := 0
## 宝箱里的一件装备（可以没有）
@export var equipment: EquipData
## 宝箱里的药（Vitality.MEDICINES 的键，可以没有）和份数
@export var medicine: StringName
@export var medicine_count := 1
