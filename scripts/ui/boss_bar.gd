class_name BossBar
extends Control
## 屏幕顶上头目的长血条：血叠成几管（data.boss_bars），一管一个颜色，打掉一管露出下一管，右边写「×几」；
## 下面一条金色细条是韧性，打空就「破绽」；右下三个小菱形是阶段。打碎一管时闪白、碎片四散（shatter）。

## 从上往下一管一个颜色：朱红、橙、金、紫、青
const BAR_COLORS: Array[Color] = [Color("d83a22"), Color("e0742a"), Color("d8a838"), Color("8a5ab0"), Color("3a8a8a")]
const BAR_H := 18.0
const TOUGH_H := 6.0
const INK := Color("120e0b")
const PAPER := Color("efe3c8")

var unit: BattleUnit
## 画面上显示的血量（播到命中那一刻才变）
var shown_hp := 0
var _flash := 0.0
var _name: Label
var _count: Label


func setup(p_unit: BattleUnit) -> void:
	unit = p_unit
	shown_hp = unit.hp
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(620, 64)
	size = custom_minimum_size
	_name = UiKit.outlined(unit.display_name(), 20, PAPER)
	_name.position = Vector2(0, -6)
	add_child(_name)
	_count = UiKit.outlined("", 22, Color("ffcf6a"))
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.size = Vector2(120, 30)
	_count.position = Vector2(size.x - 120, -8)
	add_child(_count)
	refresh()


func show_hp(hp: int) -> void:
	shown_hp = hp
	refresh()


func refresh() -> void:
	var bars := maxi(unit.data.boss_bars, 1)
	var per := float(unit.max_hp) / bars
	var left := ceili(shown_hp / per) if shown_hp > 0 else 0
	_count.text = "×%d" % left
	var phase: String = ["", "一", "二", "三"][clampi(unit.phase, 1, 3)]
	_name.text = "%s　第%s阶段%s" % [unit.display_name(), phase, "　破绽！" if unit.broken_turns > 0 else ""]
	queue_redraw()


## 打碎一管：闪白，碎片往外飞。
func shatter() -> void:
	_flash = 1.0
	var t := create_tween()
	t.tween_property(self, "_flash", 0.0, 0.35)
	t.parallel().tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, 0.35)
	var bar_y := 24.0
	for i in 14:
		var shard := ColorRect.new()
		shard.color = Color(1, 0.95, 0.85, 0.9)
		shard.size = Vector2(randf_range(6, 16), randf_range(3, 7))
		shard.position = Vector2(randf_range(0, size.x), bar_y + randf_range(0, BAR_H))
		shard.rotation = randf_range(-1, 1)
		shard.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shard)
		var st := shard.create_tween().set_parallel()
		st.tween_property(shard, "position", shard.position + Vector2(randf_range(-60, 60), randf_range(20, 70)), 0.5).set_ease(Tween.EASE_OUT)
		st.tween_property(shard, "modulate:a", 0.0, 0.5)
		st.chain().tween_callback(shard.queue_free)


func _draw() -> void:
	if unit == null:
		return
	var bars := maxi(unit.data.boss_bars, 1)
	var per := float(unit.max_hp) / bars
	var y := 24.0
	var w := size.x
	draw_rect(Rect2(-3, y - 3, w + 6, BAR_H + 6), Color(INK, 0.85))
	var left := ceili(shown_hp / per) if shown_hp > 0 else 0
	if left > 0:
		# 下面一管的颜色垫底，当前这一管按比例盖在上面
		var top_i := bars - left
		if left > 1:
			draw_rect(Rect2(0, y, w, BAR_H), BAR_COLORS[(top_i + 1) % BAR_COLORS.size()].darkened(0.15))
		var frac := (shown_hp - (left - 1) * per) / per
		draw_rect(Rect2(0, y, w * frac, BAR_H), BAR_COLORS[top_i % BAR_COLORS.size()])
		draw_rect(Rect2(0, y, w * frac, 4), Color(1, 1, 1, 0.22))
	if _flash > 0.0:
		draw_rect(Rect2(0, y, w, BAR_H), Color(1, 1, 1, _flash * 0.8))
	# 管与管的刻度
	for i in range(1, bars):
		var x := w * i / bars
		draw_line(Vector2(x, y), Vector2(x, y + BAR_H), Color(INK, 0.35), 1.0)
	# 韧性
	var ty := y + BAR_H + 5
	draw_rect(Rect2(0, ty, w, TOUGH_H), Color(INK, 0.8))
	var tough := float(unit.toughness) / BattleUnit.TOUGHNESS_MAX
	var tc := Color("f0c060") if unit.broken_turns == 0 else Color("ff6a4a")
	draw_rect(Rect2(0, ty, w * (tough if unit.broken_turns == 0 else 1.0), TOUGH_H), tc)
	draw_string(UiKit.cjk_font(), Vector2(0, ty + TOUGH_H + 16), "韧性", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(PAPER, 0.8))
	# 阶段小菱形
	for i in 3:
		var c := Vector2(w - 50 + i * 18, ty + TOUGH_H + 10)
		var lit := unit.phase > i
		var pts := PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)])
		draw_colored_polygon(pts, Color("f0c060") if lit else Color(0.35, 0.33, 0.3))
