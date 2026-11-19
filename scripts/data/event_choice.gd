class_name EventChoice
extends Resource
## 奇遇或支线里的一个选项，以及选了之后的结果。

@export var label: String
## 选这一项要花的银两；不够时选项不能点
@export var cost_silver := 0
@export_multiline var result_text: String
@export var tokens := 0
@export var silver := 0
@export var experience := 0
## 选了之后打一仗：填 battle 用固定的战斗；battle_from_region 为 true 时按当地的遭遇组合生成（有精英）
@export var battle: StageData
@export var battle_from_region := false
## 打一仗时，只有打赢才给上面的 tokens/silver/experience
## 选了之后设置的剧情标记，比如支线完成
@export var flag: String
