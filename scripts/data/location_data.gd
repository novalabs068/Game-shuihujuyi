class_name LocationData
extends Resource
## 江湖大地图上的一个地点。坐标都是地图原图（1280×720）上的像素。

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## 主角站的位置（道路上）
@export var map_position: Vector2
## 地名竖签的位置（一般在地标建筑上方）
@export var label_position: Vector2
## 这个剧情标记出现后才开放；空 = 一开始就开放
@export var unlock_flag: String
## 危险程度（1～4 颗星）和这一带敌人的等级区间。赶路到这里时，路上的遭遇战按这里的设置生成
@export_range(1, 4) var danger := 1
@export var level_min := 1
@export var level_max := 8
## 这一带可能遇到的敌人组合（每个是一场战斗的模板，等级由 level_min～level_max 决定）
@export var encounter_groups: Array[StageData] = []
## 第一次到达时设置的剧情标记，以及弹出的剧情文字
@export var arrive_flag: String
@export_multiline var arrive_text: String
## 这里的主线关卡（StageData.id），打赢后设置标记 "clear_<id>"
@export var stage_id: String
## 可以进入的横版场景（第 2 步再做）
@export var scene_id: String
## 有集市：能买凡品装备、卖掉不要的装备
@export var has_market := false
## 有客栈、酒店可以歇脚（花银两，全队气血回满）
@export var has_inn := false
## 去下一个地点的道路折线，从本地点开始、到下一个地点结束；最后一个地点留空
@export var road_to_next: PackedVector2Array
