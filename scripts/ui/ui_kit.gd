class_name UiKit
## 古风界面的公共样式：颜色、字体、按钮、面板都集中在这里（宋风：宣纸、墨、朱砂、乌木、石青、泥金）。
## 零件图在 art/ui/kit_*.png（tools/ui_kit_art.py 生成），设计稿见 claude.ai/artifact/JmJVE9foKaJ2wEZXuFbjeG。

const BG := Color("1c140e")
const PANEL := Color("2a1d14")
const PANEL_LIGHT := Color("3a2818")
const TEXT := Color("f2e8d2")
const TEXT_DIM := Color("b8a888")
const GOLD := Color("d9a93f")      # 天罡
const SILVER := Color("b9c0c8")    # 地煞
const ENEMY := Color("8a4a4a")
const BOSS := Color("e0583f")
## 石青（浅）：主角名字、选中等强调色，压在深色底上用
const ACCENT := Color("8fb8d8")
const HP := Color("4caf50")
const RAGE := Color("f08a24")
const DAMAGE := Color("ff6b5b")
const HEAL := Color("7be07f")

const ROLE_NAMES: Array[String] = ["战士", "刺客", "射手", "道士", "治疗"]
const RARITY_NAMES: Array[String] = ["", "地煞", "天罡", "主角"]
## 内部和设计文档里的品级名；界面上不显示，品级只用勾玉数（MagatamaRow）和名字颜色表示
const TIER_NAMES: Array[String] = ["甲", "乙", "丙", "丁"]
## 品级的名字颜色：甲金、乙紫、丙蓝、丁灰（参考《三国志·战略版》名字按品质上色）
const TIER_COLORS: Array[Color] = [Color("e0b040"), Color("a070e0"), Color("5a9ae8"), Color("9aa0a8")]
## 装备品质的颜色：凡品灰白、良品蓝、精品金、名器朱红。QUALITY_INK 用在纸色底的面板上
const QUALITY_COLORS: Array[Color] = [Color("c8c4b8"), Color("6aa8f0"), Color("e0b040"), Color("e8604a")]
const QUALITY_INK: Array[Color] = [Color("6a6458"), Color("2f63a8"), Color("a8741a"), Color("b0301e")]
## 职业小标签上的单字
const ROLE_TAGS: Array[String] = ["战", "刺", "射", "道", "医"]
## 卡面统一用墨色底、深色框，颜色只留给印章、名字、勾玉这些小标记
const CARD_BG := Color("221d18")
const CARD_FRAME := Color("4a3f33")
## 职业底色（旧卡面用，新卡面统一墨色底）：猛将蓝、武将红、射手绿、谋士紫、奇人青
const ROLE_COLORS: Array[Color] = [Color("34465f"), Color("4e3560"), Color("3d5634"), Color("2a5452"), Color("6a5220")]


## 宣纸、墨、朱砂、乌木、石青、泥金：纸色面板上的字用 INK，按钮和印章用 CINNABAR，边线用 GILT
const PAPER := Color("ece0c3")
const INK := Color("1f1712")
const INK_DIM := Color("5b4a38")
const CINNABAR := Color("a8291d")
const EBONY := Color("5a3a22")
const INDIGO := Color("23384a")
const GILT := Color("c9a25a")
## 木牌、黑漆上的金字
const WOOD_TEXT := Color("f1d99c")


static var _font: Font
static var _brush_font: Font


## 正文字体（思源宋体）。主题外的地方（比如 Node2D 下的 Label 拿不到主题）也用它。
const FONT_PATH := "res://art/fonts/NotoSerifSC.ttf"
## 标题、按钮用的毛笔字（马善政）；不收数字，数字落到宋体
const BRUSH_FONT_PATH := "res://art/fonts/MaShanZheng.ttf"


static func cjk_font() -> Font:
	if _font == null:
		# 打包进游戏的思源宋体（Noto Serif SC，字重 600）：只收了游戏里用到的字和 3755 个常用字（见 art/fonts/chars.txt），
		# 各家手机显示一样。单独一个全角符号（比如「！」）也不会再被系统换成没有这个字的西文字体、画成「FF01」方框。
		# 玩家起名用到的生僻字不在里面，交给系统字体兜底（点名简体字体，不用苹方：Godot 取到的是繁体字面）。
		var font: FontFile = load(FONT_PATH)
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Noto Serif CJK SC", "Songti SC", "Noto Sans CJK SC", "Hiragino Sans GB", "Microsoft YaHei", "serif"])
		font.fallbacks = [system]
		_font = font
	return _font


## 毛笔字：标题、按钮、名字。没收的字（数字、生僻字）落到宋体。
static func brush_font() -> Font:
	if _brush_font == null:
		var font: FontFile = load(BRUSH_FONT_PATH)
		font.fallbacks = [cjk_font()]
		_brush_font = font
	return _brush_font


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = cjk_font()
	t.default_font_size = 22
	# 普通按钮：黑漆金边、毛笔金字（主按钮、木签、印章另有专门的样子，见下面的 plaque_button 等）
	var lac := lacquer_box()
	t.set_stylebox("normal", "Button", lac)
	t.set_stylebox("hover", "Button", _tinted(lac, Color(1.15, 1.1, 1.05)))
	t.set_stylebox("pressed", "Button", _tinted(lac, Color(0.75, 0.7, 0.66)))
	t.set_stylebox("disabled", "Button", _tinted(lac, Color(0.6, 0.58, 0.55, 0.7)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", brush_font())
	t.set_color("font_color", "Button", WOOD_TEXT)
	t.set_color("font_hover_color", "Button", WOOD_TEXT.lightened(0.15))
	t.set_color("font_pressed_color", "Button", WOOD_TEXT.darkened(0.15))
	t.set_color("font_focus_color", "Button", WOOD_TEXT)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.6))
	t.set_color("font_color", "Label", TEXT)
	# 滚动条：细细一根泥金
	var track := StyleBoxFlat.new()
	track.bg_color = Color(GILT, 0.12)
	track.set_corner_radius_all(3)
	track.content_margin_left = 3
	track.content_margin_right = 3
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(GILT, 0.75)
	grab.set_corner_radius_all(3)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("grabber", bar, grab)
		t.set_stylebox("grabber_highlight", bar, grab)
		t.set_stylebox("grabber_pressed", bar, grab)
	# 输入框：宣纸底、墨字
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(PAPER, 0.92)
	edit.border_color = INK
	edit.border_width_bottom = 2
	edit.set_content_margin_all(8)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", CINNABAR)
	# 弹出的提示
	t.set_stylebox("panel", "TooltipPanel", note_box())
	t.set_color("font_color", "TooltipLabel", INK)
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


## 圆形按钮：直径 d，底色 fill，泥金边；毛笔字居中（战斗里的攻、技、守、合、位）。
static func round_button(text: String, d: float, fill: Color, text_color: Color, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(d, d)
	b.size = Vector2(d, d)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", brush_font())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, text_color)
	b.add_theme_color_override("font_disabled_color", Color(text_color, 0.45))
	var normal := StyleBoxFlat.new()
	normal.bg_color = fill
	normal.set_corner_radius_all(int(d / 2))
	normal.set_border_width_all(3)
	normal.border_color = GILT
	normal.shadow_color = Color(0, 0, 0, 0.45)
	normal.shadow_size = 8
	normal.shadow_offset = Vector2(0, 4)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = fill.lightened(0.15)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(fill.darkened(0.3), 0.55)
	disabled.border_color = Color(GILT, 0.35)
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


# ======== 古风零件 ========

## 九宫格零件：图、四边不拉伸的边距（左、上、右、下，图上像素）、里面内容离边的距离
const KIT := {
	&"lacquer": ["res://art/ui/kit_lacquer.png", [8, 8, 8, 8], [16, 8, 16, 8]],
	&"panel": ["res://art/ui/kit_panel.png", [36, 36, 36, 36], [30, 26, 30, 26]],
	&"note": ["res://art/ui/kit_note.png", [6, 6, 6, 6], [14, 8, 14, 8]],
	&"slip": ["res://art/ui/kit_slip.png", [8, 26, 8, 8], [4, 26, 4, 10]],
	&"slip_red": ["res://art/ui/kit_slip_red.png", [8, 26, 8, 8], [4, 26, 4, 10]],
	&"tab": ["res://art/ui/kit_tab.png", [10, 10, 10, 2], [16, 4, 16, 2]],
	&"tab_on": ["res://art/ui/kit_tab_on.png", [10, 10, 10, 2], [16, 4, 16, 2]],
	&"slot": ["res://art/ui/kit_slot.png", [8, 8, 8, 8], [6, 6, 6, 6]],
}

## 云头木牌按钮下面垂的红穗大小
const TASSEL_SIZE := Vector2(20, 58)


static func kit_box(id: StringName) -> StyleBoxTexture:
	var spec: Array = KIT[id]
	var s := StyleBoxTexture.new()
	s.texture = load(spec[0])
	var m: Array = spec[1]
	var c: Array = spec[2]
	s.texture_margin_left = m[0]
	s.texture_margin_top = m[1]
	s.texture_margin_right = m[2]
	s.texture_margin_bottom = m[3]
	s.content_margin_left = c[0]
	s.content_margin_top = c[1]
	s.content_margin_right = c[2]
	s.content_margin_bottom = c[3]
	return s


## 黑漆金边框：匾额、题签、资源条、普通按钮。
static func lacquer_box() -> StyleBoxTexture:
	return kit_box(&"lacquer")


## 宣纸面板：石青锦缎包边、四角回纹。弹窗和详情页用。
static func panel_box() -> StyleBoxTexture:
	return kit_box(&"panel")


## 宣纸字条：细金线框。提示条、告示。
static func note_box() -> StyleBoxTexture:
	return kit_box(&"note")


## 同一个样子换个明暗（按下变暗、悬停变亮、禁用褪色）。
static func _tinted(style: StyleBox, tint: Color) -> StyleBox:
	var s := style.duplicate() as StyleBox
	if s is StyleBoxTexture:
		(s as StyleBoxTexture).modulate_color = tint
	elif s is StyleBoxFlat:
		(s as StyleBoxFlat).bg_color *= tint
	return s


## 给按钮四种状态套同一个零件（悬停亮一点、按下暗一点）。
static func skin(b: BaseButton, style: StyleBox) -> void:
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", _tinted(style, Color(1.12, 1.08, 1.04)))
	b.add_theme_stylebox_override("pressed", _tinted(style, Color(0.75, 0.7, 0.66)))
	b.add_theme_stylebox_override("disabled", _tinted(style, Color(0.55, 0.52, 0.5, 0.75)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func _text_colors(b: Button, color: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, color)
	b.add_theme_color_override("font_disabled_color", Color(color, 0.45))


## 毛笔字标签。
static func brush_label(text: String, font_size := 30, color := WOOD_TEXT) -> Label:
	var l := label(text, font_size, color)
	l.add_theme_font_override("font", brush_font())
	return l


## 竖排的字：一个字一行（Godot 的 Label 没有竖排，拿换行凑）。
static func vertical_text(text: String) -> String:
	return "\n".join(text.split(""))


## 云头木牌按钮：两头像如意云头，金边木纹，毛笔字；主按钮（primary）是朱漆的，下面垂一缕红穗轻轻摆。
## 一屏最多一个主按钮（确定、出阵、开打、招募）。
static func plaque_button(text: String, min_size := Vector2(190, 60), primary := false, font_size := 28) -> Button:
	var b := button(text, min_size, font_size)
	var texture: Texture2D = load("res://art/ui/result_plaque_red.png" if primary else "res://art/ui/result_plaque.png")
	var style := StyleBoxTexture.new()
	style.texture = texture
	skin(b, style)
	b.add_theme_font_override("font", brush_font())
	_text_colors(b, Color("fff1d0") if primary else WOOD_TEXT)
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_color_override("font_outline_color", Color("5a120b") if primary else Color("1a0f08"))
	if primary:
		var tassel := TextureRect.new()
		tassel.texture = load("res://art/ui/result_tassel.png")
		tassel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tassel.stretch_mode = TextureRect.STRETCH_SCALE
		tassel.size = TASSEL_SIZE
		tassel.pivot_offset = Vector2(TASSEL_SIZE.x / 2, 0)
		tassel.show_behind_parent = true
		tassel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tassel)
		# 穗子挂在木牌右下角，按钮大小定下来后再摆
		var place := func() -> void: tassel.position = Vector2(b.size.x - TASSEL_SIZE.x - 4, b.size.y - 14)
		b.resized.connect(place)
		place.call()
		var sway := tassel.create_tween().set_loops()
		sway.tween_property(tassel, "rotation", 0.09, 1.1).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sway.tween_property(tassel, "rotation", -0.09, 1.1).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	return b


## 挂木签：竖排毛笔字的乌木签（主菜单：招募、好汉、编队、江湖榜）。lit 为真时是朱漆的（选中的页签）。
static func slip_button(text: String, width := 54.0, font_size := 26, lit := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	skin(b, kit_box(&"slip_red" if lit else &"slip"))
	var l := brush_label(vertical_text(text), font_size, Color("fff1d0") if lit else Color("f4e2b4"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("line_spacing", -int(font_size * 0.28))
	# 签的高按竖排字实际占的高算（顶上系绳孔 24 + 字 + 底下留白），字多也不会溢出签外
	b.custom_minimum_size = Vector2(width, 24.0 + l.get_minimum_size().y + 14.0)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color("1a0f08"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_top = 24
	b.set_meta("label", l)
	click_sound(b)
	return b


## 把木签换成朱漆（选中）或乌木。
static func set_slip_lit(b: Button, lit: bool) -> void:
	skin(b, kit_box(&"slip_red" if lit else &"slip"))
	var l: Label = b.get_meta("label")
	l.add_theme_color_override("font_color", Color("fff1d0") if lit else Color("f4e2b4"))


## 圆朱印按钮（返回「归」、号令）。
static func seal_button(text: String, d := 54.0, font_size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(d, d)
	var style := StyleBoxTexture.new()
	style.texture = load("res://art/ui/kit_seal.png")
	skin(b, style)
	b.add_theme_font_override("font", brush_font())
	b.add_theme_font_size_override("font_size", font_size)
	_text_colors(b, Color("f7e7c6"))
	click_sound(b)
	return b


## 右上角的返回键：圆朱印「归」。
static func back_button() -> Button:
	var b := seal_button("归")
	b.tooltip_text = "返回"
	return b


## 铜扣小圆钮（设置等）。gear 为真时画一个齿轮，不写字。
static func copper_button(text: String, d := 46.0, font_size := 22, gear := false) -> Button:
	var b := Button.new()
	b.text = "" if gear else text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(d, d)
	var style := StyleBoxTexture.new()
	style.texture = load("res://art/ui/kit_copper.png")
	skin(b, style)
	b.add_theme_font_override("font", brush_font())
	b.add_theme_font_size_override("font_size", font_size)
	_text_colors(b, Color("e9c979"))
	if gear:
		b.tooltip_text = text
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.draw.connect(func() -> void:
			var c := icon.size / 2
			var r := icon.size.x * 0.12
			var col := Color("e9c979")
			icon.draw_arc(c, r, 0, TAU, 24, col, 2.0, true)
			for i in 8:
				var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
				icon.draw_line(c + dir * (r + 3), c + dir * (r + 8), col, 2.5, true))
	click_sound(b)
	return b


## 小方印标签（「出战」「伤」「阵眼」这类）：朱砂底、浅色字、细内框。vertical 时竖排。
static func seal_label(text: String, font_size := 16, vertical := false, fill := CINNABAR) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = Color("f7e7c6", 0.75)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(3)
	s.content_margin_left = 5
	s.content_margin_right = 5
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 2
	p.add_theme_stylebox_override("panel", s)
	var l := brush_label(vertical_text(text) if vertical else text, font_size, Color("f7e7c6"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if vertical:
		l.add_theme_constant_override("line_spacing", -int(font_size * 0.25))
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 页面标题：金色毛笔大字，旁边一方竖排小印（「好汉」+「群英」）。
static func page_title(text: String, seal := "", font_size := 48) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	var l := brush_label(text, font_size, Color("e9c979"))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color("1a0f08"))
	h.add_child(l)
	if seal != "":
		var s := seal_label(seal, 16, true)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.rotation = deg_to_rad(-4)
		h.add_child(s)
	return h


## 黑漆题签（大地图的「大宋江湖舆图」、聚义厅的匾）。
static func title_plaque(text: String, font_size := 32) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", lacquer_box())
	var l := brush_label(text, font_size, Color("e9c979"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 书签页签（乌木 / 选中朱漆）。
static func tab_button(text: String, font_size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", brush_font())
	b.add_theme_font_size_override("font_size", font_size)
	set_tab_on(b, false)
	click_sound(b)
	return b


static func set_tab_on(b: Button, on: bool) -> void:
	var style := kit_box(&"tab_on" if on else &"tab")
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, style)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_text_colors(b, Color("fff1d0") if on else Color("cdb68a"))
	b.set_pressed_no_signal(on)


## 进度条样子：淡墨槽、墨色（或朱砂）条。纸色底上用。
static func style_bar(bar: ProgressBar, fill := INK, on_paper := true) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(INK, 0.12) if on_paper else Color(1, 1, 1, 0.12)
	bg.border_color = Color(INK, 0.3) if on_paper else Color(GILT, 0.4)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	bar.show_percentage = false


## 菜单页的背景：一张水墨画压暗（默认东京）。加在 parent 最底下。
static func backdrop(parent: Control, path := "res://art/story/dongjing.jpg", dim := 0.78) -> void:
	var tex := TextureRect.new()
	tex.texture = load(path)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tex)
	parent.move_child(tex, 0)
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.086, 0.059, 0.039, dim)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)
	parent.move_child(shade, 1)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 铜钱小图标（银两）。
static func coin_icon(d := 20.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(d, d)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var o := c.size / 2
		c.draw_circle(o, d / 2, Color("a87a2c"))
		c.draw_circle(o, d / 2 - 2, Color("e0b85a"))
		c.draw_arc(o, d / 2 - 1, 0, TAU, 20, Color("7d5a1e"), 1.5, true)
		var h := d * 0.15
		c.draw_rect(Rect2(o - Vector2(h, h), Vector2(h, h) * 2), Color("2a1c12")))
	return c


## 令牌小图标（聚义令）：朱红圆顶小牌、金边，写个「令」。
static func token_icon(h := 24.0) -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color("a8291d")
	s.border_color = Color("e5b95c")
	s.set_border_width_all(1)
	s.corner_radius_top_left = int(h * 0.4)
	s.corner_radius_top_right = int(h * 0.4)
	s.corner_radius_bottom_left = 2
	s.corner_radius_bottom_right = 2
	s.set_content_margin_all(0)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(h * 0.75, h)
	var l := brush_label("令", int(h * 0.5), Color("f7e2b0"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 一行「图标 + 数字」（铜钱 1,280、令牌 12）。
static func amount_row(icon: Control, text: String, font_size := 18, color := Color("f4e2b4")) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	h.add_child(label(text, font_size, color))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


## 设计稿的画面大小。手机屏比 16:9 宽时（拉伸模式 expand），视口会比这个宽。
const DESIGN_SIZE := Vector2(1280, 720)


## 一块设计稿大小（1280×720）、在屏幕正中的画框：按绝对坐标摆的页面把内容放进来，
## 屏幕更宽时整块居中，不会挤在左边、右边空一大片。背景和贴屏幕边的按钮（如「归」）不要放进来。
static func design_frame(parent: Control) -> Control:
	var f := Control.new()
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(f)
	f.set_anchors_preset(Control.PRESET_CENTER)
	f.offset_left = -DESIGN_SIZE.x / 2
	f.offset_right = DESIGN_SIZE.x / 2
	f.offset_top = -DESIGN_SIZE.y / 2
	f.offset_bottom = DESIGN_SIZE.y / 2
	return f


## 铺满屏幕的背景图（KEEP_ASPECT_COVERED）上一点在屏幕上的位置和缩放：
## 返回 [缩放, 左上偏移]，图上坐标 p 在屏幕上是 偏移 + p * 缩放。叠在背景画上的字和物件按这个摆。
static func cover_transform(screen: Vector2, texture_size: Vector2) -> Array:
	var s := maxf(screen.x / texture_size.x, screen.y / texture_size.y)
	return [s, (screen - texture_size * s) / 2]
