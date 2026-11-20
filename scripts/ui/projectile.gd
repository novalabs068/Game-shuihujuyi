class_name Projectile
extends Node2D
## 远程普攻飞出去的东西：箭（arrow）或暗器、飞石、炮弹（throw）。从 from 飞到 to，到了就删掉。

const ARROW_COLOR := Color("e8dcc0")
const STONE_COLOR := Color("3a3430")
const FLIGHT_SECONDS := 0.16

var style: StringName = &"arrow"


## 在 parent 里从 from 飞到 to，飞到时返回。
static func fly(parent: Node, from: Vector2, to: Vector2, p_style: StringName) -> void:
	var p := Projectile.new()
	p.style = p_style
	p.position = from
	p.rotation = (to - from).angle()
	p.z_index = 16
	p.scale = Vector2(1.6, 1.6)
	parent.add_child(p)
	var t := p.create_tween()
	t.tween_property(p, "position", to, FLIGHT_SECONDS)
	await t.finished
	p.queue_free()


func _draw() -> void:
	if style == &"arrow":
		# 箭杆、箭头、尾羽，后面拖一道淡光
		draw_line(Vector2(-70, 0), Vector2(-20, 0), Color(ARROW_COLOR, 0.25), 6.0)
		draw_line(Vector2(-34, 0), Vector2(10, 0), ARROW_COLOR, 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(18, 0), Vector2(6, -6), Vector2(6, 6)]), Color("c8c8d0"))
		draw_line(Vector2(-34, 0), Vector2(-42, -6), Color("be3226"), 3.0)
		draw_line(Vector2(-34, 0), Vector2(-42, 6), Color("be3226"), 3.0)
	else:
		draw_line(Vector2(-40, 0), Vector2(0, 0), Color(1, 0.9, 0.7, 0.3), 8.0)
		draw_circle(Vector2.ZERO, 8.0, STONE_COLOR)
		draw_circle(Vector2(-2, -2), 3.0, Color(1, 1, 1, 0.35))
