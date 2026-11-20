class_name SceneRoamer
extends RefCounted
## 场景里游荡的小怪（明雷）：在出生点附近闲逛，主角走近了就追上来，碰到就开打。
## 只管自己怎么走，寻路和开打交给 LocationView。

## 闲逛时离出生点最远几格
const WANDER_RADIUS := 4
const WANDER_SPEED := 80.0
const CHASE_SPEED := 160.0
## 主角离它几格以内开始追；追出几格以外就放弃
const AGGRO_CELLS := 3.5
const GIVE_UP_CELLS := 6.0
## 离主角不到几格算碰上
const CONTACT_CELLS := 0.6
## 追的时候多久重新算一次路
const REPATH_SECONDS := 0.4

var index: int
var stage: StageData
var actor: MapActor
var home: Vector2i
var path: Array[Vector2] = []
var chasing := false
var wait := 0.0
var repath := 0.0


func _init(p_index: int, p_stage: StageData, p_actor: MapActor, p_home: Vector2i) -> void:
	index = p_index
	stage = p_stage
	actor = p_actor
	home = p_home
	wait = randf_range(0.3, 2.0)


## 沿着 path 走一步。
func walk(delta: float) -> void:
	actor.moving = not path.is_empty()
	if path.is_empty():
		return
	var to := path[0] - actor.position
	if absf(to.x) > 1.0:
		actor.facing_left = to.x < 0
	var step := (CHASE_SPEED if chasing else WANDER_SPEED) * delta
	if to.length() <= step:
		actor.position = path[0]
		path.remove_at(0)
	else:
		actor.position += to.normalized() * step
