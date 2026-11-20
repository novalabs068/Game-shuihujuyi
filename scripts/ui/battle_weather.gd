class_name BattleWeather
## 战场上飘的东西：雪、落叶、芦花、风沙、花瓣。按战场背景（地点）选，没有的就不飘。
## 粒子贴图在代码里现画，不占美术文件。

## 战场背景名 → 天气
const BY_PLACE := {
	"cangzhou": &"snow",
	"yezhulin": &"leaves",
	"erlongshan": &"leaves",
	"liangshan": &"reeds",
	"jingyanggang": &"wind",
	"shizipo": &"wind",
	"huangnigang": &"wind",
	"weizhou": &"wind",
	"dongjing": &"petals",
	"kuaihuolin": &"petals",
}


## 在 parent 里铺满 area 的一层天气；没有天气返回 null。
static func make(place: String, area: Vector2) -> CPUParticles2D:
	var kind: StringName = BY_PLACE.get(place, &"")
	if kind == &"":
		return null
	var p := CPUParticles2D.new()
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	match kind:
		&"snow":
			p.texture = _dot(6, Color(1, 1, 1, 0.9))
			p.amount = 80
			p.lifetime = 9.0
			p.position = Vector2(area.x / 2, -10)
			p.emission_rect_extents = Vector2(area.x * 0.6, 4)
			p.direction = Vector2(0.15, 1)
			p.spread = 15.0
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 60.0
			p.gravity = Vector2(4, 8)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.4
		&"leaves", &"petals":
			var color := Color("c8742c") if kind == &"leaves" else Color("f0b8c0")
			p.texture = _leaf(color)
			p.amount = 16 if kind == &"leaves" else 22
			p.lifetime = 8.0
			p.position = Vector2(area.x / 2, -10)
			p.emission_rect_extents = Vector2(area.x * 0.6, 4)
			p.direction = Vector2(0.6, 1)
			p.spread = 20.0
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 70.0
			p.gravity = Vector2(6, 10)
			p.angular_velocity_min = -120.0
			p.angular_velocity_max = 120.0
			p.angle_min = 0.0
			p.angle_max = 360.0
			p.scale_amount_min = 0.7
			p.scale_amount_max = 1.3
		&"reeds":
			p.texture = _dot(10, Color(1, 1, 0.95, 0.55))
			p.amount = 30
			p.lifetime = 10.0
			p.position = Vector2(-10, area.y * 0.45)
			p.emission_rect_extents = Vector2(4, area.y * 0.45)
			p.direction = Vector2(1, -0.15)
			p.spread = 25.0
			p.initial_velocity_min = 40.0
			p.initial_velocity_max = 80.0
			p.gravity = Vector2(0, -3)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.2
		&"wind":
			p.texture = _streak(Color(0.85, 0.75, 0.6, 0.35))
			p.amount = 26
			p.lifetime = 3.5
			p.position = Vector2(-40, area.y * 0.5)
			p.emission_rect_extents = Vector2(4, area.y * 0.5)
			p.direction = Vector2(1, 0.05)
			p.spread = 4.0
			p.initial_velocity_min = 380.0
			p.initial_velocity_max = 520.0
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.5
	# 一进战斗就已经飘满了，不是从零开始下
	p.preprocess = p.lifetime
	return p


## 一个边缘柔和的圆点。
static func _dot(d: int, color: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d / 2.0
	for y in d:
		for x in d:
			var t := clampf(1.0 - Vector2(x + 0.5 - r, y + 0.5 - r).length() / r, 0.0, 1.0)
			img.set_pixel(x, y, Color(color, color.a * t))
	return ImageTexture.create_from_image(img)


## 一片小叶子（或花瓣）：细长的椭圆。
static func _leaf(color: Color) -> ImageTexture:
	var img := Image.create(12, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in 12:
			var dx := (x + 0.5 - 6.0) / 6.0
			var dy := (y + 0.5 - 3.0) / 3.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, color.darkened(0.25 * absf(dy)))
	return ImageTexture.create_from_image(img)


## 一道横向的风沙线，两头淡。
static func _streak(color: Color) -> ImageTexture:
	var img := Image.create(48, 2, false, Image.FORMAT_RGBA8)
	for x in 48:
		var t := sin(PI * x / 47.0)
		for y in 2:
			img.set_pixel(x, y, Color(color, color.a * t))
	return ImageTexture.create_from_image(img)
