class_name MapActor
extends Node2D
## 俯视场景里的人物或物件：脚下阴影 + 像素小人（sprite）；没有像素图时画圆形头像，
## 再没有就是写着一个字的色块。position 是脚底的位置，配合父节点的 y_sort 实现前后遮挡。
## 像素小人只有一张图，走路的动作由程序拼：把图切成上身和左右两条腿，按 4 帧步伐循环
## （迈左脚 → 腾起 → 迈右脚 → 腾起）错开腿、抬身子，每次只挪整 1 个像素，像素格子不变形；
## 落脚时扬起一小撮土（art/fx/step_dust.png，用 pixelfx 生成，见 tools/pixelfx/）。
## 站着时上身隔一会儿沉 1 个像素，像在呼吸。朝左时水平翻转。

const RADIUS := 22.0
const LIFT := 26.0
## 像素图放大倍数：物件和瓦片一致用 3 倍；人物像素更细（约 48 像素高），用 2 倍
const PIXEL_SCALE := 3.0
const CHARACTER_SCALE := 2.0
## 每秒迈几步（每步 2 帧：落脚、腾起）
const STEP_RATE := 4.0
## 腿从图的多高处开始（占整张图高度的比例）
const LEG_START := 0.74
## 呼吸：每隔多少秒沉一下，沉多久
const BREATH_PERIOD := 1.8
const BREATH_HOLD := 0.6
## 4 帧步伐：[前腿错开, 后腿错开, 整个人抬起]，单位是图上的像素
const WALK_FRAMES := [[1, -1, 0], [0, 0, 1], [-1, 1, 0], [0, 0, 1]]
const DUST_SHEET := preload("res://art/fx/step_dust.png")
const DUST_FRAME := Vector2i(32, 16)
const DUST_PIVOT := Vector2(22, 13)
const DUST_COLUMNS := 3
const DUST_FRAMES := 12
const DUST_FPS := 24.0

var texture: Texture2D
var glyph := ""
var color := Color("8a6a4a")
var facing_left := false
var sprite: Texture2D
var sprite_scale := PIXEL_SCALE
## 正在走路
var moving := false:
	set(value):
		if value and not moving:
			_step_phase = 0.0
		moving = value
		queue_redraw()

## 头顶名字的颜色（小怪用红色，精英更红）
var caption_color := UiKit.TEXT:
	set(value):
		caption_color = value
		if _caption != null:
			_caption.add_theme_color_override("font_color", value)

var _time := 0.0
var _step_phase := 0.0
var _caption: Label
var _alert: Label
## 扬起的尘土：[扬起的位置（和自己同一个坐标系）, 已存在时间, 是否朝左]
var _dust: Array[Array] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 时间错开一点，免得一群人同时呼吸
	_time = randf() * 10.0


func _process(delta: float) -> void:
	# 只有人物会动，宝箱、物件不动
	if not _is_character():
		return
	_time += delta
	if moving:
		var before := _walk_frame()
		_step_phase += delta * STEP_RATE * 2.0
		var now := _walk_frame()
		# 落脚的那两帧（0 和 2）扬一小撮土，土留在原地，人走远了它还在
		if now != before and now % 2 == 0:
			_dust.append([position, 0.0, facing_left])
	for d in _dust:
		d[1] += delta
	_dust = _dust.filter(func(d: Array) -> bool: return d[1] * DUST_FPS < DUST_FRAMES)
	queue_redraw()


func _walk_frame() -> int:
	return int(_step_phase) % WALK_FRAMES.size()


## 头顶冒个「！」：小怪发现主角时
func alert(on: bool) -> void:
	if _alert == null:
		_alert = Label.new()
		_alert.text = "！"
		_alert.add_theme_font_override("font", UiKit.cjk_font())
		_alert.add_theme_font_size_override("font_size", 30)
		_alert.add_theme_color_override("font_color", UiKit.BOSS)
		_alert.add_theme_constant_override("outline_size", 8)
		_alert.add_theme_color_override("font_outline_color", Color.BLACK)
		_alert.position = Vector2(-12, -sprite_scale * 60 - 34)
		add_child(_alert)
	_alert.visible = on


func _is_character() -> bool:
	return sprite != null and sprite_scale == CHARACTER_SCALE


func setup(p_texture: Texture2D, p_glyph: String, p_color: Color, caption: String) -> void:
	texture = p_texture
	glyph = p_glyph
	color = p_color
	if caption != "":
		var tag := Label.new()
		tag.text = caption
		tag.add_theme_font_override("font", UiKit.cjk_font())
		tag.add_theme_font_size_override("font_size", 16)
		tag.add_theme_color_override("font_color", UiKit.TEXT)
		tag.add_theme_constant_override("outline_size", 6)
		tag.add_theme_color_override("font_outline_color", Color.BLACK)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.size = Vector2(120, 22)
		tag.position = Vector2(-60, 2)
		add_child(tag)
		_caption = tag
	queue_redraw()


## 按当前这一帧拼出人物：先画两条腿（各自错开），再画上身（呼吸时沉 1 像素，压住腿的最上一行）。
## 坐标单位是图上的像素，原点在脚底中间。
func _draw_character() -> void:
	var size := Vector2i(sprite.get_size())
	var leg_y := roundi(size.y * LEG_START)
	@warning_ignore("integer_division")
	var mid := size.x / 2
	var front := 0
	var back := 0
	var lift := 0
	var sink := 0
	if moving:
		var f: Array = WALK_FRAMES[_walk_frame()]
		front = f[0]
		back = f[1]
		lift = f[2]
	elif fmod(_time, BREATH_PERIOD) < BREATH_HOLD:
		sink = 1
	var origin := Vector2(-size.x / 2.0, -size.y - lift)
	# 图里人脸朝右：右半边是前腿，左半边是后腿
	_draw_part(Rect2i(0, leg_y, mid, size.y - leg_y), origin + Vector2(back, 0))
	_draw_part(Rect2i(mid, leg_y, size.x - mid, size.y - leg_y), origin + Vector2(front, 0))
	_draw_part(Rect2i(0, 0, size.x, leg_y), origin + Vector2(0, sink))


func _draw_part(region: Rect2i, origin: Vector2) -> void:
	draw_texture_rect_region(sprite, Rect2(origin + Vector2(region.position), Vector2(region.size)), Rect2(region))


## 一撮土：pixelfx 的序列帧，土朝身后扬；朝左走时翻过来。
func _draw_dust(at: Vector2, age: float, left: bool) -> void:
	var frame := int(age * DUST_FPS)
	if frame >= DUST_FRAMES:
		return
	@warning_ignore("integer_division")
	var src := Rect2(Vector2((frame % DUST_COLUMNS) * DUST_FRAME.x, (frame / DUST_COLUMNS) * DUST_FRAME.y), Vector2(DUST_FRAME))
	draw_set_transform(at, 0.0, Vector2(CHARACTER_SCALE * (-1.0 if left else 1.0), CHARACTER_SCALE))
	draw_texture_rect_region(DUST_SHEET, Rect2(-DUST_PIVOT, Vector2(DUST_FRAME)), src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func set_glyph(p_glyph: String, p_color: Color) -> void:
	glyph = p_glyph
	color = p_color
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, RADIUS, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d in _dust:
		_draw_dust(d[0] - position, d[1], d[2])
	if sprite != null:
		var flip := -1.0 if facing_left else 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(sprite_scale * flip, sprite_scale))
		if _is_character():
			_draw_character()
		else:
			var px := Vector2(sprite.get_size())
			draw_texture(sprite, Vector2(-px.x / 2, -px.y))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var center := Vector2(0, -LIFT)
	draw_circle(center, RADIUS + 3, Color("1e1c1a"))
	if texture != null:
		# 朝左时以头像中心为轴水平翻转
		draw_set_transform(center, 0.0, Vector2(-1.0 if facing_left else 1.0, 1.0))
		draw_texture_rect(texture, Rect2(-Vector2(RADIUS, RADIUS), Vector2(RADIUS, RADIUS) * 2), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(center, RADIUS, color)
		var font := UiKit.cjk_font()
		draw_string(font, center + Vector2(-RADIUS, 8), glyph, HORIZONTAL_ALIGNMENT_CENTER, RADIUS * 2, 22, Color.WHITE)
