class_name UiKit
## 原型阶段的占位美术：颜色、边框、字号都集中在这里，以后换正式美术主要改这一处。

const BG := Color("1b1d22")
const PANEL := Color("2a2d35")
const PANEL_LIGHT := Color("3a3e48")
const TEXT := Color("f2efe6")
const TEXT_DIM := Color("a8a49a")
const GOLD := Color("d9a93f")      # 天罡
const SILVER := Color("b9c0c8")    # 地煞
const ENEMY := Color("8a4a4a")
const BOSS := Color("e0583f")
const ACCENT := Color("4f8ff7")
const HP := Color("4caf50")
const RAGE := Color("f08a24")
const DAMAGE := Color("ff6b5b")
const HEAL := Color("7be07f")

const ROLE_NAMES: Array[String] = ["猛将", "武将", "射手", "谋士", "奇人"]
const RARITY_NAMES: Array[String] = ["", "地煞", "天罡", "主角"]
## 职业底色：猛将蓝、武将红、射手绿、谋士紫、奇人青
const ROLE_COLORS: Array[Color] = [Color("34465f"), Color("5a3434"), Color("3d5634"), Color("4a3d5e"), Color("2f5252")]


static var _font: Font


## 简体中文字体。主题外的地方（比如 Node2D 下的 Label 拿不到主题）也用它。
static func cjk_font() -> Font:
	if _font == null:
		# 默认的系统字体回退会缺简体字，所以点名简体中文字体。不用苹方：Godot 取到的是合集里的繁体（港）字面。
		# M4 再换成打包进游戏的字体。
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Hiragino Sans GB", "Noto Sans CJK SC", "Microsoft YaHei", "sans-serif"])
		_font = font
	return _font


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = cjk_font()
	t.default_font_size = 22
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, SILVER, 2))
	t.set_stylebox("hover", "Button", box(PANEL_LIGHT.lightened(0.1), TEXT, 2))
	t.set_stylebox("pressed", "Button", box(ACCENT.darkened(0.3), ACCENT, 3))
	t.set_stylebox("disabled", "Button", box(PANEL, PANEL_LIGHT, 2))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.3))
	t.set_color("font_color", "Label", TEXT)
	return t


static func box(bg: Color, border: Color, border_width := 2, radius := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(10)
	return s


static func label(text: String, font_size := 22, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, min_size: Vector2, font_size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	return b


static func rarity_color(data: UnitData) -> Color:
	if data.is_boss:
		return BOSS
	match data.rarity:
		UnitData.Rarity.PROTAGONIST:
			return ACCENT
		UnitData.Rarity.TIANGANG:
			return GOLD
		UnitData.Rarity.DISHA:
			return SILVER
	return ENEMY


static func role_color(data: UnitData) -> Color:
	return ROLE_COLORS[data.role]


## 人物图（半身像或头像）。没有图时用同样大小的空位占住，布局不变。
static func picture(texture: Texture2D, side: int, flip := false) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.flip_h = flip
	return rect


## 人物的半身像（prefer_face 时用头像）。没有版画图的敌人退回用像素小人，按最近邻放大保持像素清晰。
static func unit_picture(data: UnitData, side: int, flip := false, prefer_face := false) -> TextureRect:
	var texture: Texture2D = data.face if prefer_face else data.bust
	var pixel := texture == null and data.map_sprite != null
	if pixel:
		texture = data.map_sprite
	var rect := picture(texture, side, flip)
	if pixel:
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect


## 让 node 下所有控件都不吃点击，交给最外层处理。
static func ignore_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		ignore_mouse(child)
