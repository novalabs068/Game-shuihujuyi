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
## 第一次到达时设置的剧情标记，以及弹出的剧情文字
@export var arrive_flag: String
@export_multiline var arrive_text: String
## 这里的主线关卡（StageData.id），打赢后设置标记 "clear_<id>"
@export var stage_id: String
## 可以进入的横版场景（第 2 步再做）
@export var scene_id: String
## 去下一个地点的道路折线，从本地点开始、到下一个地点结束；最后一个地点留空
@export var road_to_next: PackedVector2Array
