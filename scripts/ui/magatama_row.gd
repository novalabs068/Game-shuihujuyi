class_name MagatamaRow
extends Control
## 一排勾玉：总数表示品级（甲 5、乙 4、丙 3、丁 2，界面上不写甲乙丙丁），
## 实心的是已经升星点亮的，空心的是还没点亮的。

const GOLD := Color("e8b440")
const INK := Color("2a1a08")

var count := 1
var filled := 0
var size_px := 16.0


## 只看品级（刚抽到、还没招到）：全空心。
static func for_tier(tier: int, px := 16.0) -> MagatamaRow:
	return make(UiKit.tier_magatama(tier), 0, px)


## 某位好汉现在的样子：星级 star 点亮了几颗。
static func for_hero(hero: UnitData, star: int, px := 16.0) -> MagatamaRow:
	return make(UiKit.tier_magatama(hero.tier), Stars.lit(star), px)


static func make(total: int, lit: int, px := 16.0) -> MagatamaRow:
	var row := MagatamaRow.new()
	row.count = total
	row.filled = lit
	row.size_px = px
	row.custom_minimum_size = Vector2(row.count * px * 0.95, px * 1.15)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


func _draw() -> void:
	for i in count:
		_draw_one(Vector2(i * size_px * 0.95 + size_px * 0.42, size_px * 0.42), size_px * 0.32, i < filled)


## 一颗勾玉：圆头 + 往左下弯、越来越细的尾巴（一串由大到小的圆），先画深色的底当描边，再画金色，头上一点眼和高光。
func _draw_one(c: Vector2, r: float, solid: bool) -> void:
	var tail: Array[Vector3] = []
	for k in 9:
		var t := k / 8.0
		var a := PI * 0.15 + t * PI * 0.75
		var p := c + Vector2(cos(a), sin(a)) * r * (0.55 + t * 0.55) + Vector2(-t * r * 0.35, t * r * 0.15)
		tail.append(Vector3(p.x, p.y, r * (0.78 - t * 0.68)))
	var edge := maxf(1.0, r * 0.2)
	draw_circle(c, r + edge, INK)
	for q in tail:
		draw_circle(Vector2(q.x, q.y), q.z + edge, INK)
	# 空心：金色描边、里面是暗色；实心：整颗金色，带眼和高光
	var rim := GOLD if solid else Color(GOLD, 0.75)
	var fill := GOLD if solid else Color("2a2218")
	var inset := 0.0 if solid else maxf(1.0, r * 0.22)
	draw_circle(c, r, rim)
	for q in tail:
		draw_circle(Vector2(q.x, q.y), q.z, rim)
	if not solid:
		draw_circle(c, r - inset, fill)
		for q in tail:
			if q.z > inset:
				draw_circle(Vector2(q.x, q.y), q.z - inset, fill)
		return
	draw_circle(c + Vector2(r * 0.15, -r * 0.05), r * 0.28, INK)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.18, Color(1, 1, 1, 0.55))
