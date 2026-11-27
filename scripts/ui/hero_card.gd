class_name HeroCard
extends Control
## 竖长的好汉卡（参考三国志战略版的卡面）：品级颜色的光晕做底（五玉金、四玉紫、三玉蓝、二玉灰），
## 版画立绘铺满整张卡，底部压暗一截写勾玉、名字和绰号；左上角身份印，右上角小标签（「新」「将魂 +10」）。
## 外框是深铜色，里面一道细线用品级颜色，五玉的细线加粗。

## 光晕底：中心亮、四周压暗
const GLOW_LIGHTEN := 0.3
const EDGE_DARK := 0.9
const FRAME_DARK := Color("1e140c")


## card_size 是整张卡的大小；lit 是点亮了几颗勾玉（刚抽到的传 0）；hidden 时立绘只剩黑影、名字写「？？？」。
static func make(hero: UnitData, card_size: Vector2, lit := 0, tag := "", tag_color := UiKit.GOLD, hidden := false) -> HeroCard:
	var card := HeroCard.new()
	card.custom_minimum_size = card_size
	card.size = card_size
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := card_size.x
	var h := card_size.y
	var tier_color: Color = UiKit.TIER_COLORS[hero.tier]
	if hidden:
		tier_color = Color("4a4640")

	# 底：品级色的径向光晕，光心在头部附近
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.38, 1.0])
	grad.colors = PackedColorArray([tier_color.lightened(GLOW_LIGHTEN), tier_color.darkened(0.5), tier_color.darkened(EDGE_DARK)])
	var glow := GradientTexture2D.new()
	glow.gradient = grad
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.36)
	glow.fill_to = Vector2(1.15, 0.95)
	glow.width = 64
	glow.height = 96
	card._fill(_tex_rect(glow))

	# 立绘：铺满卡面，头顶留一点光晕
	var tex: Texture2D = hero.portrait if hero.portrait != null else hero.bust
	var pixel := tex == null and hero.map_sprite != null
	if pixel:
		tex = hero.map_sprite
	if tex != null:
		var fig := TextureRect.new()
		fig.texture = tex
		fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fig.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if pixel else TextureRect.STRETCH_KEEP_ASPECT_COVERED
		fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if pixel:
			fig.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fig.position = Vector2(0, h * 0.05)
		fig.size = Vector2(w, h * 0.95)
		if hidden:
			fig.modulate = Color(0.05, 0.05, 0.05)
		card.add_child(fig)

	# 底部压暗，好放名字
	var shade_grad := Gradient.new()
	shade_grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	shade_grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.03, 0.02, 0.01, 0.82), Color(0.03, 0.02, 0.01, 0.95)])
	var shade_tex := GradientTexture2D.new()
	shade_tex.gradient = shade_grad
	shade_tex.fill_from = Vector2(0, 0)
	shade_tex.fill_to = Vector2(0, 1)
	shade_tex.width = 4
	shade_tex.height = 64
	var shade := _tex_rect(shade_tex)
	card.add_child(shade)
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 0.58
	shade.anchor_bottom = 1.0

	# 底部文字：勾玉、名字、绰号
	var name_px := int(clampf(w * 0.135, 16, 32))
	var foot := VBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 0)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(foot)
	foot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	foot.offset_bottom = -maxf(6, h * 0.035)
	var marks := HBoxContainer.new()
	marks.alignment = BoxContainer.ALIGNMENT_CENTER
	marks.add_theme_constant_override("separation", 4)
	marks.add_child(MagatamaRow.make(UiKit.tier_magatama(hero.tier), lit, maxf(12, w * 0.085)))
	if not hidden and w >= 170:
		marks.add_child(UiKit.role_tag(hero, 13))
	foot.add_child(marks)
	var name_color := Color("fff0c8") if hero.tier == UnitData.Tier.JIA else Color("f0e4cc")
	var name := UiKit.outlined("？？？" if hidden else hero.display_name, name_px, name_color)
	name.add_theme_constant_override("outline_size", maxi(4, name_px / 4))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(name)
	if not hidden and hero.nickname != "" and h >= 180:
		var nick := UiKit.outlined(hero.nickname, int(clampf(w * 0.07, 12, 17)), tier_color.lightened(0.35))
		nick.add_theme_constant_override("outline_size", 4)
		nick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		foot.add_child(nick)

	# 左上身份印，右上小标签
	var inset := maxf(5, w * 0.035)
	var seal := IdentitySeal.make(hero.rarity, clampf(w * 0.15, 20, 34))
	seal.position = Vector2(inset, inset)
	card.add_child(seal)
	if tag != "":
		var t := UiKit.outlined(tag, int(clampf(w * 0.085, 13, 19)), tag_color)
		t.add_theme_constant_override("outline_size", 5)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		t.position = Vector2(inset, inset)
		t.size = Vector2(w - inset * 2, 24)
		card.add_child(t)

	# 框：外圈深铜，里面一道品级色细线
	var outer := StyleBoxFlat.new()
	outer.draw_center = false
	outer.border_color = FRAME_DARK
	outer.set_border_width_all(4)
	outer.set_corner_radius_all(6)
	card._fill(_frame(outer))
	var inner := StyleBoxFlat.new()
	inner.draw_center = false
	inner.border_color = Color(tier_color.lightened(0.15), 0.95)
	inner.set_border_width_all(3 if hero.tier == UnitData.Tier.JIA and not hidden else (2 if hero.tier == UnitData.Tier.YI else 1))
	inner.set_corner_radius_all(4)
	var line := _frame(inner)
	card._fill(line)
	line.offset_left = 4
	line.offset_top = 4
	line.offset_right = -4
	line.offset_bottom = -4
	return card


func _fill(node: Control) -> void:
	add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func _tex_rect(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _frame(style: StyleBoxFlat) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p
