class_name BattleBoard
extends Control
## 战场地面上的两块格子（每方 2 排 × 3 路）：淡淡的水墨菱形，按状态上色——
## 金色是这一招会打到的格子，朱红描边是绝招的范围，闪动的红格是头目大招要砸的地方，青色是补位能去的空格。
## 点格子发出 cell_tapped。格子的位置由 BattleView 给（cell_center），这里只管画和点。

signal cell_tapped(side: BattleUnit.Side, cell: Vector2i)

## 格子的宽、高，往右上斜多少（透视）
const CELL_W := 168.0
const CELL_H := 88.0
const SKEW := 18.0
const MARK_COLORS := {
	"gold": Color(0.92, 0.72, 0.25, 0.38),
	"move": Color(0.35, 0.75, 0.85, 0.34),
	"danger": Color(0.86, 0.16, 0.1, 0.42),
	"skill": Color(0.86, 0.2, 0.14, 0.0),
}
const MARK_LINES := {
	"gold": Color("f0c060"),
	"move": Color("7fd6e8"),
	"danger": Color("ff5a3c"),
	"skill": Color("ff6a4a"),
}

## 给一格算中心点：func(side, cell) -> Vector2（BattleView 设）
var cell_center: Callable
## [side, cell] → 标记名（gold / move / danger / skill）；同一格可以有多个，用数组
var marks: Dictionary = {}
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 3.0, TAU)
	if marks.values().any(func(m: Array) -> bool: return "danger" in m or "move" in m):
		queue_redraw()


func set_marks(m: Dictionary) -> void:
	marks = m
	queue_redraw()


func key(side: BattleUnit.Side, c: Vector2i) -> Array:
	return [side, c]


func _poly(center: Vector2) -> PackedVector2Array:
	var hw := CELL_W / 2
	var hh := CELL_H / 2
	return PackedVector2Array([
		center + Vector2(-hw + SKEW, -hh), center + Vector2(hw + SKEW, -hh),
		center + Vector2(hw - SKEW, hh), center + Vector2(-hw - SKEW, hh)])


func _draw() -> void:
	if not cell_center.is_valid():
		return
	for side in [BattleUnit.Side.PLAYER, BattleUnit.Side.ENEMY]:
		for c in Grid.all_cells():
			var center: Vector2 = cell_center.call(side, c)
			var poly := _poly(center)
			draw_colored_polygon(poly, Color(0.93, 0.86, 0.72, 0.06))
			var outline := poly.duplicate()
			outline.append(poly[0])
			draw_polyline(outline, Color(0.93, 0.86, 0.72, 0.2), 1.5, true)
			for mark: String in marks.get(key(side, c), []):
				var fill: Color = MARK_COLORS[mark]
				var line: Color = MARK_LINES[mark]
				if mark in ["danger", "move"]:
					var k := 0.65 + 0.35 * sin(_pulse)
					fill.a *= k
					line.a = 0.6 + 0.4 * k
				if fill.a > 0.0:
					draw_colored_polygon(poly, fill)
				draw_polyline(outline, line, 3.0 if mark != "skill" else 2.5, true)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or not cell_center.is_valid():
		return
	for side in [BattleUnit.Side.PLAYER, BattleUnit.Side.ENEMY]:
		for c in Grid.all_cells():
			if Geometry2D.is_point_in_polygon(click.position, _poly(cell_center.call(side, c))):
				cell_tapped.emit(side, c)
				accept_event()
				return
