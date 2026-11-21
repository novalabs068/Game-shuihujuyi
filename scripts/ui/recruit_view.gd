class_name RecruitView
extends Control
## 聚义厅招募：用聚义令单抽或十连。
## 演出：画面压暗，聚义令旋转砸下（光的颜色预示这一抽最好的品级）→ 卡背一张张落下 → 逐张翻开，
## 四玉、五玉翻开前颤动、升起光柱；五玉和第一次抽到的四玉翻开后全屏登场。翻牌时点屏幕跳过。

signal back_requested

## 十连两排卡片要和按钮一起放进 720 高的屏幕
const CARD_SIZE := Vector2(190, 206)
const REVEAL_DELAY := 0.12
const CARD_BACK := Color("3a1d14")
const SEAL_RED := Color("b0261e")
const PAPER := Color("ecdcbc")

var _rng := RandomNumberGenerator.new()
var _tokens_label: Label
var _pity_label: Label
var _single: Button
var _ten: Button
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
	v.add_child(UiKit.label("十连至少一个四玉或以上；%d 抽内必出五玉。重复的好汉变成将魂 +%d（升星用）。" % [Gacha.PITY_JIA, Gacha.DUPLICATE_SOULS], 16, UiKit.TEXT_DIM))
	_pity_label = UiKit.label("", 16, UiKit.TEXT_DIM)
	v.add_child(_pity_label)

	# 屏幕再矮也能滑动看到全部卡片，按钮固定在底部
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var stage := CenterContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(stage)
	_cards = GridContainer.new()
	_cards.columns = 5
	_cards.add_theme_constant_override("h_separation", 14)
	_cards.add_theme_constant_override("v_separation", 10)
	stage.add_child(_cards)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	v.add_child(buttons)
	_single = UiKit.button("单抽（1 枚）", Vector2(240, 60), 26)
	_single.pressed.connect(_recruit.bind(1))
	buttons.add_child(_single)
	_ten = UiKit.button("十连（10 枚）", Vector2(240, 60), 26)
	_ten.pressed.connect(_recruit.bind(10))
	buttons.add_child(_ten)

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
	var first := "（第一次十连必出五玉）" if not GameState.has_flag("first_ten_pull") else ""
	_pity_label.text = "距保底五玉还有 %d 抽　已招募 %d / %d 位好汉 %s" % [left, GameState.owned.size(), GameDB.heroes.size(), first]
	_single.disabled = _revealing or GameState.tokens < 1
	_ten.disabled = _revealing or GameState.tokens < 10
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
	_cards.columns = mini(count, 5)
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
		if hero.tier == UnitData.Tier.JIA or (hero.tier == UnitData.Tier.YI and is_new and not _skip):
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


## 聚义令：画面压暗，令牌旋转着放大，然后「咚」地砸下，冲出一圈光；光的颜色预示这一抽最好的品级。
func _token_strike(best: int) -> void:
	var color: Color = UiKit.TIER_COLORS[best]
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var d := 170.0
	var token := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = SEAL_RED
	style.set_corner_radius_all(int(d / 2))
	style.set_border_width_all(7)
	style.border_color = UiKit.GOLD
	style.shadow_color = Color(color, 0.8)
	style.shadow_size = 30
	token.add_theme_stylebox_override("panel", style)
	token.custom_minimum_size = Vector2(d, d)
	token.size = Vector2(d, d)
	var ch := UiKit.label("令", 104, PAPER)
	ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	token.add_child(ch)
	_fx.add_child(token)
	token.position = (size - token.size) / 2
	token.pivot_offset = token.size / 2
	token.scale = Vector2(0.2, 0.2)
	token.rotation = -TAU
	var fast := 0.5 if _skip else 1.0
	Sfx.play(&"token_whoosh")
	var t := create_tween().set_parallel()
	t.tween_property(dim, "color:a", 0.7, 0.25 * fast)
	t.tween_property(token, "scale", Vector2(1.5, 1.5), 0.55 * fast).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(token, "rotation", 0.0, 0.55 * fast).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await t.finished
	await get_tree().create_timer(0.12 * fast).timeout
	# 砸下
	var slam := create_tween()
	slam.tween_property(token, "scale", Vector2(0.9, 0.9), 0.07).set_ease(Tween.EASE_IN)
	await slam.finished
	_shockwave(token.position + token.size / 2, color)
	_flash(color)
	_shake(12.0)
	Sfx.play(&"token_slam")
	var out := create_tween().set_parallel()
	out.tween_property(token, "modulate:a", 0.0, 0.3)
	out.tween_property(token, "scale", Vector2(1.2, 1.2), 0.3)
	out.tween_property(dim, "color:a", 0.0, 0.5)
	await get_tree().create_timer(0.35 * fast).timeout
	out.finished.connect(func() -> void:
		token.queue_free()
		dim.queue_free())


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
		front.self_modulate = Color(2.2, 2.0, 1.4)
		create_tween().tween_property(front, "self_modulate", Color.WHITE, 0.35)
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


func _make_card(hero: UnitData, is_new: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	var color := UiKit.TIER_COLORS[hero.tier]
	# 甲级卡的框描一道金边，其余都是深色框
	# 五玉金边、四玉紫边，其余深色框
	var frame := UiKit.CARD_FRAME
	if hero.tier <= UnitData.Tier.YI:
		frame = UiKit.TIER_COLORS[hero.tier]
	card.add_theme_stylebox_override("panel", UiKit.card_box(frame, 4 if hero.tier <= UnitData.Tier.YI else 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(IdentitySeal.make(hero.rarity, 30))
	var tag := UiKit.label("新！" if is_new else "将魂 +%d" % Gacha.DUPLICATE_SOULS, 18, UiKit.GOLD if is_new else UiKit.TEXT_DIM)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(tag)
	var bust := UiKit.unit_picture(hero, 108)
	bust.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(bust)
	var name := UiKit.label(hero.display_name, 26, color)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)
	var marks := HBoxContainer.new()
	marks.alignment = BoxContainer.ALIGNMENT_CENTER
	marks.add_theme_constant_override("separation", 6)
	marks.add_child(MagatamaRow.for_tier(hero.tier, 21))
	marks.add_child(UiKit.role_tag(hero, 13))
	v.add_child(marks)
	var sub := UiKit.label(hero.nickname, 15, UiKit.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	UiKit.ignore_mouse(card)
	return card


## 手机返回键：抽卡动画放完才能返回。
func go_back() -> void:
	if not _revealing:
		back_requested.emit()
