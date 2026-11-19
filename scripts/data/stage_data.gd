class_name StageData
extends Resource
## 一个关卡：敌人、等级、三星条件。

@export var id: String
@export var title: String
@export var enemies: Array[UnitData] = []
@export var enemy_level := 1
@export var recommended_level := 1
## 在这么多回合内获胜可拿第三颗星
@export var star_round_limit := 8
