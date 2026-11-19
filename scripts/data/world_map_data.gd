class_name WorldMapData
extends Resource
## 一张江湖大地图：底图、地点（按道路顺序排列）、路上的遭遇。

@export var id: String
@export var title: String
@export var texture: Texture2D
@export var locations: Array[LocationData] = []
@export var start_location: StringName
## 每走一段路遇到敌人的概率，以及遇到时打的关卡
@export_range(0.0, 1.0) var encounter_chance := 0.3
@export var encounter_stage_id: String


func location(location_id: StringName) -> LocationData:
	for loc in locations:
		if loc.id == location_id:
			return loc
	return null


func index_of(location_id: StringName) -> int:
	for i in locations.size():
		if locations[i].id == location_id:
			return i
	return -1


## 从 from 走到 to 经过的道路折线（地点按顺序连成一条路，可以往回走）。
func route(from: StringName, to: StringName) -> PackedVector2Array:
	var a := index_of(from)
	var b := index_of(to)
	var points := PackedVector2Array()
	if a < 0 or b < 0 or a == b:
		return points
	var step := 1 if b > a else -1
	var i := a
	while i != b:
		var segment := locations[mini(i, i + step)].road_to_next.duplicate()
		if step < 0:
			segment.reverse()
		if not points.is_empty():
			segment = segment.slice(1)
		points.append_array(segment)
		i += step
	return points
