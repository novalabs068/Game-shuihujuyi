class_name RecruitView
extends Control
## 聚义厅招募：用聚义令单抽或五连（参考三国志战略版：五张竖卡排一排，不再两排挤着）。
## 演出：画面压暗，聚义令旋转砸下（光的颜色预示这一抽最好的品级）→ 卡背一张张落下 → 逐张翻开，
## 四玉、五玉翻开前颤动、升起光柱；五玉和第一次抽到的四玉翻开后全屏登场。翻牌时点屏幕跳过。

signal back_requested

## 五连一排竖卡，和按钮一起放进 720 高的屏幕
const CARD_SIZE := Vector2(220, 330)
const REVEAL_DELAY := 0.12
const CARD_BACK := Color("3a1d14")
const SEAL_RED := Color("b0261e")
const PAPER := Color("ecdcbc")
## 聚义令落地后的大小（图高 520，落地后约 430）
const TOKEN_SCALE := 0.82

var _rng := RandomNumberGenerator.new()
var _tokens_label: Label
var _pity_label: Label
var _single: Button
var _multi: Button
var _back: Button
var _cards: GridContainer
var _revealing := false
## 翻牌时点了屏幕：剩下的卡不再一张张等（五玉的登场照放）
var _skip := false
var _in_showcase := false
## 令牌、闪光、登场都画在这一层，盖在最上面
var _fx: Control


func _ready() -> void:
	_rng.randomize()
	var bg := ColorRect.new()
	bg.color = Color("221a14")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 聚义厅大堂（水墨），压暗一些好看清卡片
	var hall_path := StoryScript.background_path("juyiting")
	if hall_path != "":
		var hall := TextureRect.new()
		hall.texture = load(hall_path)
		hall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		hall.modulate = Color(0.55, 0.5, 0.46)
		hall.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hall)
		hall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	v.add_child(top)
	top.add_child(UiKit.label("聚义厅 · 招募好汉", 34, UiKit.GOLD))
	_tokens_label = UiKit.label("", 24)
	_tokens_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tokens_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_tokens_label)
	_back = UiKit.button("返回", Vector2(120, 48), 22)
	_back.pressed.connect(func() -> void:
		if not _revealing:
			back_requested.emit())
	top.add_child(_back)

	# 概率：每档画勾玉，后面跟百分比
	var rates := HBoxContainer.new()
	rates.add_theme_constant_override("separation", 6)
	rates.add_child(UiKit.label("概率", 16, UiKit.TEXT_DIM))
	for i in Gacha.RATES.size():
		rates.add_child(MagatamaRow.for_tier(i, 15))
		rates.add_child(UiKit.label("%d%%　" % Gacha.RATES[i], 16, UiKit.TEXT_DIM))
	v.add_child(rates)
	v.add_child(UiKit.label("五连至少一个四玉或以上；%d 抽内必出五玉。重复的好汉变成将魂 +%d（升星用）。" % [Gacha.PITY_JIA, Gacha.DUPLICATE_SOULS], 16, UiKit.TEXT_DIM))
	_pity_label = UiKit.label("", 16, UiKit.TEXT_DIM)
	v.add_child(_pity_label)

	# 五张竖卡排成一排，按钮固定在底部
	var stage := CenterContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(stage)
	_cards = GridContainer.new()
	_cards.columns = Gacha.MULTI
	_cards.add_theme_constant_override("h_separation", 22)
	stage.add_child(_cards)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	v.add_child(buttons)
	_single = UiKit.button("单抽（1 枚）", Vector2(240, 60), 26)
	_single.pressed.connect(_recruit.bind(1))
	buttons.add_child(_single)
	_multi = UiKit.button("五连（%d 枚）" % Gacha.MULTI, Vector2(240, 60), 26)
	_multi.pressed.connect(_recruit.bind(Gacha.MULTI))
	buttons.add_child(_multi)

	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.z_index = 20
	add_child(_fx)
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh()


## 翻牌时点屏幕：剩下的直接翻开。
func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and _revealing and not _in_showcase:
		_skip = true


func _refresh() -> void:
	_tokens_label.text = "聚义令 %d" % GameState.tokens
	var left := Gacha.PITY_JIA - GameState.pulls_since_jia
	var first := "（第一次五连必出五玉）" if not GameState.has_flag("first_ten_pull") else ""
	_pity_label.text = "距保底五玉还有 %d 抽　已招募 %d / %d 位好汉 %s" % [left, GameState.owned.size(), GameDB.heroes.size(), first]
	_single.disabled = _revealing or GameState.tokens < 1
	_multi.disabled = _revealing or GameState.tokens < Gacha.MULTI
	_back.disabled = _revealing


func _recruit(count: int) -> void:
	var results := GameState.recruit(count, _rng)
	if results.is_empty():
		return
	_revealing = true
	_skip = false
	_refresh()
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	_cards.columns = mini(count, Gacha.MULTI)
	var best := UnitData.Tier.DING
	for r in results:
		best = mini(best, (r["hero"] as UnitData).tier)
	await _token_strike(best)
	# 卡背一张张落下
	var slots: Array[Control] = []
	for r in results:
		var slot := _make_slot(r["hero"], r["is_new"])
		_cards.add_child(slot)
		slots.append(slot)
		slot.pivot_offset = CARD_SIZE / 2
		slot.scale = Vector2(0.3, 0.3)
		slot.modulate.a = 0.0
		var t := create_tween().set_parallel()
		t.tween_property(slot, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(slot, "modulate:a", 1.0, 0.12)
		Sfx.play(&"card_drop", -4.0, 0.1)
		if not _skip:
			await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.25).timeout
	# 逐张翻开
	for i in results.size():
		var hero: UnitData = results[i]["hero"]
		var is_new: bool = results[i]["is_new"]
		var rare := hero.tier <= UnitData.Tier.YI
		if rare and not _skip:
			await _build_up(slots[i], hero.tier)
		await _flip(slots[i], hero.tier, rare)
		if hero.tier == UnitData.Tier.JIA:
			await _showcase_gold(hero, is_new)
		elif hero.tier == UnitData.Tier.YI and is_new and not _skip:
			await _showcase(hero, is_new)
		elif not _skip:
			await get_tree().create_timer(REVEAL_DELAY).timeout
	_revealing = false
	_refresh()


## 一张卡：背面（深赭底、金边、中间一个「义」字圆印）盖在正面上，翻开时换过来。
func _make_slot(hero: UnitData, is_new: bool) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = CARD_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var front := _make_card(hero, is_new)
	front.visible = false
	front.name = "Front"
	slot.add_child(front)
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := PanelContainer.new()
	back.name = "Back"
	back.add_theme_stylebox_override("panel", UiKit.box(CARD_BACK, UiKit.GOLD, 3, 8))
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	back.add_child(center)
	var seal := PanelContainer.new()
	var seal_style := StyleBoxFlat.new()
	seal_style.bg_color = SEAL_RED
	seal_style.set_corner_radius_all(40)
	seal_style.set_border_width_all(3)
	seal_style.border_color = PAPER
	seal.add_theme_stylebox_override("panel", seal_style)
	seal.custom_minimum_size = Vector2(80, 80)
	var ch := UiKit.label("义", 46, PAPER)
	ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(ch)
	center.add_child(seal)
	return slot


## 聚义令：画面压暗，一块乌木铜边的竖令牌晃着从上方落下，「咚」地砸在地上，冲出一圈光；光的颜色预示这一抽最好的品级。
func _token_strike(best: int) -> void:
	var color: Color = UiKit.TIER_COLORS[best]
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var token := _make_token()
	# 背后的光：品级的颜色
	var glow := Panel.new()
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(color, 0.0)
	glow_style.set_corner_radius_all(120)
	glow_style.shadow_color = Color(color, 0.75)
	glow_style.shadow_size = 70
	glow.add_theme_stylebox_override("panel", glow_style)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.size = Vector2(120, 380)
	glow.position = (token.size - glow.size) / 2 - Vector2(0, 30)
	glow.modulate.a = 0.0
	token.add_child(glow)
	token.move_child(glow, 0)
	_fx.add_child(token)
	var land := Vector2((size.x - token.size.x) / 2, (size.y - token.size.y) / 2 - 10)
	token.position = land - Vector2(0, size.y * 0.9)
	token.pivot_offset = Vector2(token.size.x / 2, token.size.y * 0.62)
	token.rotation = -0.35
	token.scale = Vector2(0.6, 0.6)
	var fast := 0.5 if _skip else 1.0
	Sfx.play(&"token_whoosh")
	var t := create_tween().set_parallel()
	t.tween_property(dim, "color:a", 0.75, 0.25 * fast)
	t.tween_property(token, "position:y", land.y - 60, 0.5 * fast).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(token, "rotation", 0.08, 0.5 * fast).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(token, "scale", Vector2(0.9, 0.9), 0.5 * fast).set_ease(Tween.EASE_OUT)
	t.tween_property(glow, "modulate:a", 1.0, 0.5 * fast)
	await t.finished
	# 悬一下，再砸下
	var hang := create_tween()
	hang.tween_property(token, "rotation", 0.0, 0.14 * fast).set_trans(Tween.TRANS_SINE)
	await hang.finished
	var slam := create_tween().set_parallel()
	slam.tween_property(token, "position:y", land.y, 0.08).set_ease(Tween.EASE_IN)
	slam.tween_property(token, "scale", Vector2(TOKEN_SCALE, TOKEN_SCALE), 0.08)
	await slam.finished
	var squash := create_tween()
	squash.tween_property(token, "scale", Vector2(TOKEN_SCALE * 1.05, TOKEN_SCALE * 0.95), 0.05)
	squash.tween_property(token, "scale", Vector2(TOKEN_SCALE, TOKEN_SCALE), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var foot := token.position + token.pivot_offset + (Vector2(token.size.x / 2, token.size.y * 0.86) - token.pivot_offset) * TOKEN_SCALE
	_shockwave(foot, color)
	_flash(color)
	_shake(14.0)
	Sfx.play(&"token_slam")
	await get_tree().create_timer(0.45 * fast).timeout
	var out := create_tween().set_parallel()
	out.tween_property(token, "modulate:a", 0.0, 0.3)
	out.tween_property(token, "position:y", land.y - 20, 0.3)
	out.tween_property(dim, "color:a", 0.0, 0.5)
	await get_tree().create_timer(0.25 * fast).timeout
	out.finished.connect(func() -> void:
		token.queue_free()
		dim.queue_free())


## 聚义令：乌木铜边的令牌图，牌面正中竖写金色「聚义」（字是游戏里放上去的，图上是空白牌面）。
func _make_token() -> Control:
	var tex: Texture2D = load("res://art/ui/juyi_token.png")
	var token := Control.new()
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token.size = tex.get_size()
	var pic := TextureRect.new()
	pic.texture = tex
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size = tex.get_size()
	token.add_child(pic)
	# 牌面空白区：x 30～138、y 67～326（见 art/ui/juyi_token.png）
	var face := VBoxContainer.new()
	face.alignment = BoxContainer.ALIGNMENT_CENTER
	face.add_theme_constant_override("separation", 6)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.position = Vector2(30, 67)
	face.size = Vector2(108, 259)
	token.add_child(face)
	for ch: String in ["聚", "义"]:
		var l := UiKit.outlined(ch, 76, Color("e8c060"))
		l.add_theme_color_override("font_outline_color", Color("2a1408"))
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 3)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		face.add_child(l)
	return token


## 一圈光从 at 往外扩开。
func _shockwave(at: Vector2, color: Color) -> void:
	var ring := Panel.new()
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(10)
	style.border_color = color
	style.set_corner_radius_all(100)
	ring.add_theme_stylebox_override("panel", style)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = Vector2(200, 200)
	ring.position = at - ring.size / 2
	ring.pivot_offset = ring.size / 2
	ring.scale = Vector2(0.4, 0.4)
	_fx.add_child(ring)
	var t := create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector2(7, 7), 0.55).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 0.55)
	t.finished.connect(ring.queue_free)


## 整屏一闪。
func _flash(color: Color) -> void:
	var f := ColorRect.new()
	f.color = Color(color.lightened(0.4), 0.85)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(f)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := create_tween()
	t.tween_property(f, "color:a", 0.0, 0.4)
	t.finished.connect(f.queue_free)


func _shake(strength: float) -> void:
	var t := create_tween()
	for i in 6:
		var k := strength * (1.0 - i / 6.0)
		t.tween_property(self, "position", Vector2(randf_range(-k, k), randf_range(-k, k)), 0.03)
	t.tween_property(self, "position", Vector2.ZERO, 0.03)


## 四玉、五玉翻开前：卡片颤动，背后升起一道光柱，往上飘光点。
func _build_up(slot: Control, tier: int) -> void:
	var color: Color = UiKit.TIER_COLORS[tier]
	var pillar := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(color, 0.0), Color(color, 0.75)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	pillar.texture = tex
	pillar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pillar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pillar.size = Vector2(CARD_SIZE.x + 30, 520)
	pillar.position = Vector2(-15, CARD_SIZE.y - 520)
	pillar.show_behind_parent = true
	slot.add_child(pillar)
	slot.move_child(pillar, 0)
	pillar.modulate.a = 0.0
	create_tween().tween_property(pillar, "modulate:a", 1.0, 0.25)
	var sparks := CPUParticles2D.new()
	sparks.position = CARD_SIZE / 2
	sparks.amount = 40 if tier == UnitData.Tier.JIA else 20
	sparks.lifetime = 1.0
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sparks.emission_rect_extents = CARD_SIZE / 2
	sparks.direction = Vector2(0, -1)
	sparks.spread = 20.0
	sparks.gravity = Vector2(0, -60)
	sparks.initial_velocity_min = 60.0
	sparks.initial_velocity_max = 160.0
	sparks.scale_amount_min = 3.0
	sparks.scale_amount_max = 6.0
	sparks.color = color.lightened(0.3)
	slot.add_child(sparks)
	Sfx.play(&"rare_shimmer", -2.0 if tier == UnitData.Tier.JIA else -6.0)
	var shake := create_tween()
	var base := slot.position
	for i in (10 if tier == UnitData.Tier.JIA else 6):
		shake.tween_property(slot, "rotation", 0.05 if i % 2 == 0 else -0.05, 0.05)
	shake.tween_property(slot, "rotation", 0.0, 0.05)
	await shake.finished
	slot.position = base


## 翻牌：横着收窄到 0，换成正面，再展开；稀有的翻开时亮一下。
func _flip(slot: Control, tier: int, rare: bool) -> void:
	var half := 0.06 if _skip else 0.1
	Sfx.play(&"card_flip", -2.0, 0.12)
	var t := create_tween()
	t.tween_property(slot, "scale:x", 0.0, half).set_ease(Tween.EASE_IN)
	await t.finished
	(slot.get_node("Back") as Control).visible = false
	var front := slot.get_node("Front") as Control
	front.visible = true
	if rare:
		front.modulate = Color(2.2, 2.0, 1.4)
		create_tween().tween_property(front, "modulate", Color.WHITE, 0.35)
		if tier == UnitData.Tier.JIA:
			_shake(10.0)
			Sfx.play(&"jia_gong")
	var t2 := create_tween()
	t2.tween_property(slot, "scale:x", 1.0, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await t2.finished


## 全屏登场：版画全身像滑进来，一笔朱红刷开，名字逐字写出，配身份印、勾玉和绰号。点一下继续。
func _showcase(hero: UnitData, is_new: bool) -> void:
	_in_showcase = true
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_fx.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var color: Color = UiKit.TIER_COLORS[hero.tier]

	var fig := TextureRect.new()
	fig.texture = hero.portrait if hero.portrait != null else hero.bust
	fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fig.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fig_h := size.y * 1.0
	var aspect := 0.75
	if fig.texture != null:
		aspect = float(fig.texture.get_width()) / fig.texture.get_height()
	fig.size = Vector2(fig_h * aspect, fig_h)
	layer.add_child(fig)
	var fig_to := size.x * 0.58
	fig.position = Vector2(size.x, 0)

	var stroke := TextureRect.new()
	stroke.texture = load("res://art/ui/brush_stroke.png")
	stroke.modulate = Color("a8231a")
	stroke.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stroke.stretch_mode = TextureRect.STRETCH_SCALE
	stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stroke.size = Vector2(size.x * 0.56, 170)
	stroke.position = Vector2(size.x * 0.04, size.y * 0.3)
	stroke.pivot_offset = Vector2(0, 85)
	stroke.scale = Vector2(0, 1)
	layer.add_child(stroke)
	var name := UiKit.outlined(hero.display_name, 96, PAPER)
	name.add_theme_constant_override("outline_size", 12)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.size = Vector2(stroke.size.x, 130)
	name.position = stroke.position + Vector2(0, 14)
	name.visible_ratio = 0.0
	layer.add_child(name)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.position = Vector2(size.x * 0.1, stroke.position.y + 190)
	info.modulate.a = 0.0
	layer.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	info.add_child(row)
	row.add_child(IdentitySeal.make(hero.rarity, 44))
	row.add_child(UiKit.outlined(hero.nickname, 34, color))
	row.add_child(MagatamaRow.for_tier(hero.tier, 30))
	info.add_child(UiKit.outlined(("「%s」%s" % [hero.skill.display_name, hero.skill.description]) if hero.skill != null else "", 20, PAPER))
	info.add_child(UiKit.outlined("新入伙！" if is_new else "已在麾下，化作将魂 +%d" % Gacha.DUPLICATE_SOULS, 26, UiKit.GOLD if is_new else Color("c8b8a0")))
	var hint := UiKit.outlined("点一下继续", 18, Color("c8b8a0"))
	hint.position = Vector2(size.x * 0.1, size.y - 60)
	hint.modulate.a = 0.0
	layer.add_child(hint)

	var t := create_tween().set_parallel()
	t.tween_property(dim, "color:a", 0.82, 0.2)
	t.tween_property(fig, "position:x", fig_to, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(stroke, "scale:x", 1.0, 0.3).set_delay(0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(name, "visible_ratio", 1.0, 0.4).set_delay(0.3)
	t.tween_property(info, "modulate:a", 1.0, 0.3).set_delay(0.6)
	t.tween_property(hint, "modulate:a", 1.0, 0.3).set_delay(1.0)
	await t.finished
	_flash(color)
	if hero.tier != UnitData.Tier.JIA:
		Sfx.play(&"rare_shimmer", -4.0)
	# 等玩家点一下
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	layer.add_child(tap)
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await tap.pressed
	var out := create_tween()
	out.tween_property(layer, "modulate:a", 0.0, 0.18)
	await out.finished
	layer.queue_free()
	_in_showcase = false


## 五玉金卡：整屏转成金色，背后金光放射，全身立绘从中间完整升起，名字竖写在左边，金色光点往上飘。
func _showcase_gold(hero: UnitData, is_new: bool) -> void:
	_in_showcase = true
	var gold: Color = UiKit.TIER_COLORS[UnitData.Tier.JIA]
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.modulate.a = 0.0
	_fx.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("1a1006")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := Vector2(size.x / 2, size.y * 0.46)

	# 放射的金光：一圈细长三角，慢慢转
	var rays := Node2D.new()
	rays.position = center
	layer.add_child(rays)
	var reach := size.length()
	for i in 18:
		var ray := Polygon2D.new()
		var a := TAU * i / 18.0
		var w := 0.07
		ray.polygon = PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - w) * reach, Vector2.from_angle(a + w) * reach])
		ray.vertex_colors = PackedColorArray([Color(gold, 0.38), Color(gold, 0.0), Color(gold, 0.0)])
		rays.add_child(ray)
	var spin := rays.create_tween().set_loops()
	spin.tween_property(rays, "rotation", TAU, 40.0).as_relative()
	# 中间一团暖光
	var halo := Panel.new()
	var halo_style := StyleBoxFlat.new()
	halo_style.bg_color = Color(gold, 0.0)
	halo_style.set_corner_radius_all(200)
	halo_style.shadow_color = Color(gold.lightened(0.3), 0.55)
	halo_style.shadow_size = 160
	halo.add_theme_stylebox_override("panel", halo_style)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.size = Vector2(260, 260)
	halo.position = center - halo.size / 2
	layer.add_child(halo)

	# 金色光点往上飘
	var motes := CPUParticles2D.new()
	motes.amount = 70
	motes.lifetime = 3.0
	motes.preprocess = 1.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(size.x / 2, 10)
	motes.position = Vector2(size.x / 2, size.y + 10)
	motes.direction = Vector2(0, -1)
	motes.spread = 15.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 80.0
	motes.initial_velocity_max = 200.0
	motes.scale_amount_min = 2.0
	motes.scale_amount_max = 5.0
	motes.color = gold.lightened(0.3)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0)])
	motes.color_ramp = fade
	layer.add_child(motes)

	# 全身立绘：整个人都在画面里
	var fig := TextureRect.new()
	fig.texture = hero.portrait if hero.portrait != null else hero.bust
	fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fig.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fig_h := size.y * 0.94
	var aspect := 0.75
	if fig.texture != null:
		aspect = float(fig.texture.get_width()) / fig.texture.get_height()
	fig.size = Vector2(fig_h * aspect, fig_h)
	var fig_to := Vector2((size.x - fig.size.x) / 2, size.y - fig_h)
	fig.position = fig_to + Vector2(0, 120)
	fig.modulate = Color(1.6, 1.4, 0.9, 0.0)
	layer.add_child(fig)

	# 左边竖写名字，旁边小字绰号
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", -10)
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.position = Vector2(size.x * 0.12, size.y * 0.12)
	name_col.modulate.a = 0.0
	layer.add_child(name_col)
	for ch in hero.display_name:
		var l := UiKit.outlined(ch, 120, Color("fff0c0"))
		l.add_theme_constant_override("outline_size", 14)
		l.add_theme_color_override("font_outline_color", Color("3a1a04"))
		name_col.add_child(l)
	var nick_col := VBoxContainer.new()
	nick_col.add_theme_constant_override("separation", -4)
	nick_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nick_col.position = name_col.position + Vector2(150, 30)
	nick_col.modulate.a = 0.0
	layer.add_child(nick_col)
	for ch in hero.nickname:
		nick_col.add_child(UiKit.outlined(ch, 40, gold))

	# 右边：五玉、是否新入伙、绝招
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 12)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.position = Vector2(size.x * 0.68, size.y * 0.3)
	info.custom_minimum_size.x = size.x * 0.28
	info.modulate.a = 0.0
	layer.add_child(info)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	info.add_child(top)
	top.add_child(IdentitySeal.make(hero.rarity, 48))
	top.add_child(MagatamaRow.for_tier(hero.tier, 34))
	info.add_child(UiKit.outlined("新入伙！" if is_new else "已在麾下，化作将魂 +%d" % Gacha.DUPLICATE_SOULS, 40 if is_new else 26, gold if is_new else Color("e8d8b8")))
	if hero.skill != null:
		var skill_line := UiKit.outlined("「%s」%s" % [hero.skill.display_name, hero.skill.description], 20, Color("fff0d8"))
		skill_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		skill_line.custom_minimum_size.x = size.x * 0.28
		info.add_child(skill_line)
	var hint := UiKit.outlined("点一下继续", 18, Color("e8d8b8"))
	hint.position = Vector2(size.x * 0.68, size.y - 60)
	hint.modulate.a = 0.0
	layer.add_child(hint)

	_flash(gold)
	Sfx.play(&"rare_shimmer", -1.0)
	var t := create_tween().set_parallel()
	t.tween_property(layer, "modulate:a", 1.0, 0.25)
	t.tween_property(fig, "position", fig_to, 0.6).set_delay(0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(fig, "modulate", Color.WHITE, 0.7).set_delay(0.15)
	t.tween_property(name_col, "modulate:a", 1.0, 0.4).set_delay(0.6)
	t.tween_property(nick_col, "modulate:a", 1.0, 0.4).set_delay(0.8)
	t.tween_property(info, "modulate:a", 1.0, 0.4).set_delay(0.9)
	t.tween_property(hint, "modulate:a", 1.0, 0.3).set_delay(1.3)
	await t.finished
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	layer.add_child(tap)
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await tap.pressed
	var out := create_tween()
	out.tween_property(layer, "modulate:a", 0.0, 0.2)
	await out.finished
	layer.queue_free()
	_in_showcase = false


## 正面：竖长的好汉卡（见 HeroCard），右上角写「新」或「将魂 +10」。
func _make_card(hero: UnitData, is_new: bool) -> Control:
	return HeroCard.make(hero, CARD_SIZE, 0, "新！" if is_new else "将魂 +%d" % Gacha.DUPLICATE_SOULS, UiKit.GOLD if is_new else Color("d8ccb4"))


## 手机返回键：抽卡动画放完才能返回。
func go_back() -> void:
	if not _revealing:
		back_requested.emit()
