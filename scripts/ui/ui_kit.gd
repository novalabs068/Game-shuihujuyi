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
## 内部和设计文档里的品级名；界面上不显示，品级只用勾玉数（MagatamaRow）和名字颜色表示
const TIER_NAMES: Array[String] = ["甲", "乙", "丙", "丁"]
## 品级的名字颜色：甲金、乙紫、丙蓝、丁灰（参考《三国志·战略版》名字按品质上色）
const TIER_COLORS: Array[Color] = [Color("e0b040"), Color("a070e0"), Color("5a9ae8"), Color("9aa0a8")]
## 装备品质的颜色：凡品灰白、良品蓝、精品金、名器朱红。QUALITY_INK 用在纸色底的面板上
const QUALITY_COLORS: Array[Color] = [Color("c8c4b8"), Color("6aa8f0"), Color("e0b040"), Color("e8604a")]
const QUALITY_INK: Array[Color] = [Color("6a6458"), Color("2f63a8"), Color("a8741a"), Color("b0301e")]
## 职业小标签上的单字
const ROLE_TAGS: Array[String] = ["猛", "武", "射", "谋", "奇"]
## 卡面统一用墨色底、深色框，颜色只留给印章、名字、勾玉这些小标记
const CARD_BG := Color("221d18")
const CARD_FRAME := Color("4a3f33")
## 职业底色（旧卡面用，新卡面统一墨色底）：猛将蓝、武将红、射手绿、谋士紫、奇人青
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


## 按钮按下时笃一声（木鱼）。
## 按名字在运行时找 Sfx：UiKit 也被不带自动加载的测试用到，不能直接写 Sfx。
static func click_sound(b: BaseButton) -> void:
	b.pressed.connect(func() -> void:
		var sfx := b.get_node_or_null("/root/Sfx")
		if sfx != null:
			sfx.play(&"ui_click", -6.0, 0.05))


static func button(text: String, min_size: Vector2, font_size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	click_sound(b)
	return b


static func rarity_color(data: UnitData) -> Color:
	if data.is_boss:
		return BOSS
	match data.rarity:
		UnitData.Rarity.PROTAGONIST:
			return ACCENT
		UnitData.Rarity.TIANGANG, UnitData.Rarity.DISHA:
			return TIER_COLORS[data.tier]
	return ENEMY


## 品级对应几颗勾玉：甲 5、乙 4、丙 3、丁 2（也就是能升几次星）。
static func tier_magatama(tier: int) -> int:
	return 5 - tier


## 职业小标签：深色小方块里一个字（猛、武、射、谋、奇）。
static func role_tag(data: UnitData, font_size := 15) -> PanelContainer:
	var tag := PanelContainer.new()
	var style := box(Color(0, 0, 0, 0.55), Color("6a5c4a"), 1, 3)
	style.set_content_margin_all(2)
	style.content_margin_left = 5
	style.content_margin_right = 5
	tag.add_theme_stylebox_override("panel", style)
	tag.add_child(label(ROLE_TAGS[data.role], font_size, Color("d8ccb4")))
	tag.tooltip_text = ROLE_NAMES[data.role]
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tag


## 卡面：墨色底、深色框（被选中等状态时传 border 覆盖）。
static func card_box(border := CARD_FRAME, width := 2) -> StyleBoxFlat:
	return box(CARD_BG, border, width, 6)


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


## 游戏版本号（tools/build_apk.sh 每打一次包加一，写在 project.godot）。
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "开发版"))


## 1～99 写成汉字（「第十二回合」）。
static func cn_number(n: int) -> String:
	const DIGITS := "零一二三四五六七八九"
	if n <= 0 or n >= 100:
		return str(n)
	if n < 10:
		return DIGITS[n]
	var tens := n / 10
	var ones := n % 10
	return ("" if tens == 1 else DIGITS[tens]) + "十" + ("" if ones == 0 else DIGITS[ones])


## 圆形按钮：直径 d，底色 fill，边框米色；字居中。
static func round_button(text: String, d: float, fill: Color, text_color: Color, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(d, d)
	b.size = Vector2(d, d)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, text_color)
	b.add_theme_color_override("font_disabled_color", Color(text_color, 0.45))
	var normal := StyleBoxFlat.new()
	normal.bg_color = fill
	normal.set_corner_radius_all(int(d / 2))
	normal.set_border_width_all(3)
	normal.border_color = Color("ecdcbc")
	normal.shadow_color = Color(0, 0, 0, 0.45)
	normal.shadow_size = 8
	normal.shadow_offset = Vector2(0, 4)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = fill.lightened(0.15)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(fill.darkened(0.3), 0.55)
	disabled.border_color = Color("ecdcbc", 0.35)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	click_sound(b)
	return b


## 带黑描边的字，直接压在战场画面上用。
static func outlined(text: String, font_size: int, color: Color) -> Label:
	var l := label(text, font_size, color)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.04))
	return l
