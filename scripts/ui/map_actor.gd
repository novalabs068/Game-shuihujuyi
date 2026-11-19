class_name MapActor
extends Node2D
## 俯视场景里的人物或物件：脚下阴影 + 像素小人（sprite）；没有像素图时画圆形头像，
## 再没有就是写着一个字的色块。position 是脚底的位置，配合父节点的 y_sort 实现前后遮挡。
## 像素图不做逐帧动画：走路时由程序上下起伏，朝左时水平翻转。

const RADIUS := 22.0
const LIFT := 26.0
## 像素图放大倍数：物件和瓦片一致用 3 倍；人物像素更细（约 48 像素高），用 2 倍
const PIXEL_SCALE := 3.0
const CHARACTER_SCALE := 2.0
const BOB_HEIGHT := 4.0
const BOB_SPEED := 14.0

var texture: Texture2D
var glyph := ""
var color := Color("8a6a4a")
var facing_left := false
var sprite: Texture2D
var sprite_scale := PIXEL_SCALE
## 正在走路：上下起伏
var moving := false:
	set(value):
		moving = value
		set_process(value)
		queue_redraw()

var _time := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(moving)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


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
	queue_redraw()


func set_glyph(p_glyph: String, p_color: Color) -> void:
	glyph = p_glyph
	color = p_color
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, RADIUS, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if sprite != null:
		var lift := absf(sin(_time * BOB_SPEED)) * BOB_HEIGHT if moving else 0.0
		var flip := -1.0 if facing_left else 1.0
		draw_set_transform(Vector2(0, -lift), 0.0, Vector2(sprite_scale * flip, sprite_scale))
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
