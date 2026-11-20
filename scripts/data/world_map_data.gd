class_name WorldMapData
extends Resource
## 一张江湖大地图：底图、地点、道路网、路上的遭遇。
## 有 roads 时按路网走最短的路；没有时按 locations 的顺序连成一条路（旧地图）。

@export var id: String
@export var title: String
@export var texture: Texture2D
## 底图在游戏里的大小（比屏幕大时可以拖动）
@export var size := Vector2(1280, 720)
@export var roads: Array[RoadData] = []
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


## 从 from 走到 to 经过的道路折线。
func route(from: StringName, to: StringName) -> PackedVector2Array:
	if not roads.is_empty():
		return _route_network(from, to)
	return _route_chain(from, to)


## 路网上的最短路（Dijkstra，按路的长度）。走不通返回空。
func _route_network(from: StringName, to: StringName) -> PackedVector2Array:
	var points := PackedVector2Array()
	if from == to:
		return points
	var dist := {from: 0.0}
	var came: Dictionary = {}
	var open: Array[StringName] = [from]
	var done: Array[StringName] = []
	while not open.is_empty():
		open.sort_custom(func(x: StringName, y: StringName) -> bool: return dist[x] < dist[y])
		var here: StringName = open.pop_front()
		if here == to:
			break
		done.append(here)
		for road in roads:
			var next: StringName = road.b if road.a == here else (road.a if road.b == here else &"")
			if next == &"" or next in done:
				continue
			var d: float = dist[here] + road.length()
			if not dist.has(next) or d < dist[next]:
				dist[next] = d
				came[next] = [here, road]
				if not next in open:
					open.append(next)
	if not came.has(to):
		return points
	# 从终点往回倒，再把每段路按行走方向拼起来
	var legs: Array = []
	var at := to
	while at != from:
		legs.push_front(came[at] + [at])
		at = came[at][0]
	for leg in legs:
		var road: RoadData = leg[1]
		var segment := road.points.duplicate()
		if road.a != leg[0]:
			segment.reverse()
		if not points.is_empty():
			segment = segment.slice(1)
		points.append_array(segment)
	return points


## 旧地图：地点按顺序连成一条路，可以往回走。
func _route_chain(from: StringName, to: StringName) -> PackedVector2Array:
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
