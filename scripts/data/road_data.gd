class_name RoadData
extends Resource
## 江湖大地图上连接两个地点的一条路：从 a 走到 b 经过的折线（地图坐标）。路是双向的。

@export var a: StringName
@export var b: StringName
@export var points: PackedVector2Array


func length() -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total
