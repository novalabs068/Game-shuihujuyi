class_name StageData
extends Resource
## 一个关卡：敌人、等级、三星条件。

@export var id: String
@export var title: String
@export var enemies: Array[UnitData] = []
## 敌人各站哪一格（和 enemies 一一对应，Vector2i(排, 路)）；空着或不够的按职业自动摆（见 Grid.auto_place）
@export var enemy_cells: Array[Vector2i] = []
@export var enemy_level := 1
@export var recommended_level := 1
## 在这么多回合内获胜可拿第三颗星
@export var star_round_limit := 8
## 敌人整体强度：生命、攻击都乘这个数（危险度高的地区更凶，见 Encounters）
@export var enemy_power := 1.0
## 头目额外的强度倍数（按队伍养成程度加，见 GameState.boss_power），只对 is_boss 的敌人生效
@export var boss_power := 1.0
