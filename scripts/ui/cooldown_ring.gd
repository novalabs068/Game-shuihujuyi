class_name CooldownRing
extends Control
## 绝招钮上的冷却圈：没恢复的部分盖一片暗色扇形，恢复了的部分沿边亮一道金弧，
## 每回合一格（格与格之间有刻度）。recovered 为 1 时什么都不画。

const SHADE := Color(0.05, 0.03, 0.02, 0.62)
const ARC := Color("e8c060")
const TICK := Color(0.93, 0.86, 0.74, 0.8)

## 已经恢复的比例（0～1）
var recovered := 1.0:
	set(value):
		recovered = clampf(value, 0.0, 1.0)
		queue_redraw()
## 一共几格（几回合）
var segments := 1:
	set(value):
		segments = maxi(value, 1)
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if recovered >= 1.0:
		return
	var c := size / 2
	var r := minf(size.x, size.y) / 2
	var top := -PI / 2
	var done := top + recovered * TAU
	# 还没恢复的那一块：从已恢复的边一直到 12 点，顺时针盖暗
	var pts := PackedVector2Array([c])
	var steps := 48
	for i in steps + 1:
		pts.append(c + Vector2.from_angle(lerpf(done, top + TAU, float(i) / steps)) * (r - 2))
	draw_colored_polygon(pts, SHADE)
	# 已恢复的部分：沿边一道金弧
	if recovered > 0.0:
		draw_arc(c, r - 5, top, done, 48, ARC, 6.0, true)
	# 每回合一格的刻度
	for i in segments:
		var a := top + TAU * i / segments
		draw_line(c + Vector2.from_angle(a) * (r - 12), c + Vector2.from_angle(a) * (r - 1), TICK, 2.0, true)
