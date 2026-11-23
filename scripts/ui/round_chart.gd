class_name RoundChart
extends Control
## 按回合的折线图：横轴回合，纵轴数值；每条线一个人，带图例。数据由外面塞进来。

const PAD := Vector4(56, 16, 16, 34)  # 左、上、右、下留白（放刻度）
const GRID := Color(1, 1, 1, 0.08)
const AXIS := Color(0.85, 0.8, 0.7, 0.75)

## 每项 {"name": 名字, "color": 颜色, "values": [第 1 回合, 第 2 回合, ...]}
var series: Array[Dictionary] = []:
	set(value):
		series = value
		queue_redraw()
var rounds := 1:
	set(value):
		rounds = maxi(value, 1)
		queue_redraw()


func _draw() -> void:
	var font := UiKit.cjk_font()
	var area := Rect2(PAD.x, PAD.y, size.x - PAD.x - PAD.z, size.y - PAD.y - PAD.w)
	var top := 1
	for s in series:
		for v: int in s["values"]:
			top = maxi(top, v)
	top = _nice_ceiling(top)
	# 横线和纵轴刻度：0、1/4、1/2、3/4、顶
	for i in 5:
		var y := area.end.y - area.size.y * i / 4.0
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), GRID, 1.0)
		draw_string(font, Vector2(0, y + 6), "%d" % (top * i / 4), HORIZONTAL_ALIGNMENT_RIGHT, PAD.x - 8, 14, AXIS)
	# 回合刻度：回合多时隔几个标一个
	var step := maxi(1, ceili(rounds / 12.0))
	for r in range(1, rounds + 1, step):
		var x := _x(area, r)
		draw_string(font, Vector2(x - 20, area.end.y + 22), "%d" % r, HORIZONTAL_ALIGNMENT_CENTER, 40, 14, AXIS)
	draw_line(Vector2(area.position.x, area.end.y), area.end, AXIS, 1.0)
	for s in series:
		var values: Array = s["values"]
		var color: Color = s["color"]
		var pts := PackedVector2Array()
		for i in values.size():
			pts.append(Vector2(_x(area, i + 1), area.end.y - area.size.y * float(values[i]) / top))
		if pts.size() >= 2:
			draw_polyline(pts, color, 3.0, true)
		for p in pts:
			draw_circle(p, 4.0, color)


func _x(area: Rect2, r: int) -> float:
	if rounds <= 1:
		return area.position.x + area.size.x / 2
	return area.position.x + area.size.x * (r - 1) / float(rounds - 1)


## 把纵轴顶取成好看的整数：1、2、5 × 10 的几次方。
static func _nice_ceiling(v: int) -> int:
	var mag := pow(10.0, floorf(log(maxf(v, 1)) / log(10.0)))
	for k in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if k * mag >= v:
			return int(k * mag)
	return v
