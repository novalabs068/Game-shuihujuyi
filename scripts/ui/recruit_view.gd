class_name RecruitView
extends Control
## 聚义厅招募：用聚义令单抽或五连（参考三国志战略版：五张竖卡排一排，不再两排挤着）。
## 演出：画面压暗，做旧的聚义令旋转砸下（光的颜色预示这一抽最好的品级，出五玉时只亮紫光，留个悬念）→
## 锦缎卡背一张张落下 → 逐张翻开。四玉翻开前颤动、卡边冒紫光；五玉翻开前卡飞到屏幕正中，全屏的光一涨一退，
## 白、蓝、紫轮着来，呼之欲出又迟迟不出，最后炸成金光，翻开后全屏登场（只有五玉有全屏）。翻牌时点屏幕跳过（五玉的变色和登场照放）。

signal back_requested

## 五连一排竖卡，和按钮一起放进 720 高的屏幕
const CARD_SIZE := Vector2(220, 330)
const REVEAL_DELAY := 0.12
## 五玉翻开前的全屏变色：白、蓝、紫三种光，每种「涨上去、像要炸开、又退回来」几次（心跳一样），
## 最后涨到最高、突然全收回去静一下，再炸成金光。蓝、紫比品级色更饱和，叠加在亮处也看得出颜色
const GOLD_PHASES: Array[Color] = [Color(1, 0.97, 0.9), Color("3d7dff"), Color("a35cff")]
const SWELLS_PER_PHASE := 2
## 一次涨、退各用几秒，退完停多久
const SWELL_UP := 0.55
const SWELL_DOWN := 0.35
const SWELL_REST := 0.1
## 炸开前全收回去后，静多久
const GOLD_HUSH := 0.5
## 卡飞到正中后放大多少
const GOLD_LIFT_SCALE := 1.45
## 卡背后的光比卡大出的边（左右、下、上；上面留得多，好放光柱）
const AURA_PAD := Vector4(150, 120, 150, 330)
const LIGHT_RAYS := preload("res://scripts/ui/shaders/light_rays.gdshader")
const CARD_AURA := preload("res://scripts/ui/shaders/card_aura.gdshader")
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
		if hero.tier == UnitData.Tier.JIA:
			await _build_up_gold(slots[i])
		elif rare and not _skip:
			await _build_up(slots[i], hero.tier)
		await _flip(slots[i], hero.tier, rare)
		if hero.tier == UnitData.Tier.JIA:
			await _showcase_gold(hero, is_new)
		elif not _skip:
			await get_tree().create_timer(REVEAL_DELAY).timeout
	_revealing = false
	_refresh()


## 一张卡：背面（靛青回纹锦缎、中间宣纸题签写繁体「聚义」、小朱印，见 tools/recruit_marks.py）盖在正面上，翻开时换过来。
func _make_slot(hero: UnitData, is_new: bool) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = CARD_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 卡比卡后的光高一层（光 z_index -1），光不会盖到隔壁的卡上
	slot.z_index = 1
	var front := _make_card(hero, is_new)
	front.visible = false
	front.name = "Front"
	slot.add_child(front)
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := TextureRect.new()
	back.name = "Back"
	back.texture = load("res://art/ui/card_back.png")
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return slot


## 聚义令：画面压暗，一块乌木铜边的竖令牌晃着从上方落下，「咚」地砸在地上，冲出一圈光；光的颜色预示这一抽最好的品级。
## 出五玉时只亮四玉的紫光，金光留到翻那张卡的时候。
func _token_strike(best: int) -> void:
	var color: Color = UiKit.TIER_COLORS[maxi(best, UnitData.Tier.YI)]
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var token := _make_token()
	# 背后的光：品级的颜色，放射的光芒
	var glow := _rays(Vector2(760, 760), color, 0.13, 0.6)
	glow.position = (token.size - glow.size) / 2 - Vector2(0, 50)
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


## 聚义令：做旧的乌木铜边令牌，繁体「聚义」刻在牌面上、描金剥落（字已经画在图上，见 tools/recruit_marks.py）。
func _make_token() -> Control:
	var tex: Texture2D = load("res://art/ui/juyi_token_old.png")
	var token := Control.new()
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token.size = tex.get_size()
	var pic := TextureRect.new()
	pic.texture = tex
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size = tex.get_size()
	token.add_child(pic)
	return token


## 放射的光（叠加混合，见 light_rays.gdshader）：rect_size 大小，光心在正中。
func _rays(rect_size: Vector2, color: Color, core: float, ray_strength: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color.WHITE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = rect_size
	var mat := ShaderMaterial.new()
	mat.shader = LIGHT_RAYS
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("aspect", rect_size.x / rect_size.y)
	mat.set_shader_parameter("core", core)
	mat.set_shader_parameter("ray_strength", ray_strength)
	mat.set_shader_parameter("reach", 0.5 * minf(rect_size.x, rect_size.y) / rect_size.y)
	r.material = mat
	return r


## 一圈光从 at 往外扩开：边缘柔和、中间空、叠加混合，像地上震起的一圈光浪（不是硬边的色环）。
func _shockwave(at: Vector2, color: Color) -> void:
	var band := Gradient.new()
	band.offsets = PackedFloat32Array([0.0, 0.55, 0.8, 0.9, 1.0])
	band.colors = PackedColorArray([Color(color, 0.0), Color(color, 0.08), Color(color.lightened(0.4), 0.9), Color(color, 0.35), Color(color, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = band
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var ring := TextureRect.new()
	ring.texture = tex
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ring.material = add
	# 压扁一点，像贴着地面散开
	ring.size = Vector2(200, 90)
	ring.position = at - ring.size / 2
	ring.pivot_offset = ring.size / 2
	ring.scale = Vector2(0.3, 0.3)
	_fx.add_child(ring)
	var t := create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector2(7, 7), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(ring, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
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


## 卡背后的光（叠加混合，见 card_aura.gdshader）：沿卡边像火苗一样往外冒，卡顶冲出一道光柱，再往上飘柔和的光点。
## 加在卡的最底层，翻开后还留着（淡一些）。返回光本身，光点挂在它下面（名叫 Sparks）。
func _add_aura(slot: Control, color: Color) -> ColorRect:
	var aura := ColorRect.new()
	aura.name = "Aura"
	aura.color = Color.WHITE
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aura.z_index = -1
	aura.position = Vector2(-AURA_PAD.x, -AURA_PAD.w)
	aura.size = CARD_SIZE + Vector2(AURA_PAD.x + AURA_PAD.z, AURA_PAD.y + AURA_PAD.w)
	var mat := ShaderMaterial.new()
	mat.shader = CARD_AURA
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("rect_size", aura.size)
	mat.set_shader_parameter("card_size", CARD_SIZE)
	mat.set_shader_parameter("card_center", Vector2(AURA_PAD.x, AURA_PAD.w) + CARD_SIZE / 2)
	aura.material = mat
	slot.add_child(aura)
	slot.move_child(aura, 0)
	var sparks := _soft_particles(color.lightened(0.3), 24)
	sparks.name = "Sparks"
	sparks.position = Vector2(AURA_PAD.x, AURA_PAD.w) + CARD_SIZE / 2
	sparks.emission_rect_extents = CARD_SIZE / 2
	sparks.direction = Vector2(0, -1)
	sparks.spread = 15.0
	sparks.gravity = Vector2(0, -50)
	sparks.initial_velocity_min = 40.0
	sparks.initial_velocity_max = 120.0
	sparks.lifetime = 1.4
	aura.add_child(sparks)
	return aura


## 柔和的圆形光点（叠加混合、淡入淡出），不再是方块。
func _soft_particles(color: Color, amount: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var dot := Gradient.new()
	dot.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	dot.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = dot
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	p.texture = tex
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	p.amount = amount
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.7
	p.color = color
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	return p


## 把卡后的光换成某个颜色（光点一起换），duration 秒内渐变。
func _aura_to(aura: ColorRect, color: Color, intensity: float, duration: float) -> Tween:
	var mat := aura.material as ShaderMaterial
	var t := create_tween().set_parallel()
	t.tween_method(func(c: Color) -> void: mat.set_shader_parameter("color", c), mat.get_shader_parameter("color") as Color, color, duration)
	t.tween_method(func(v: float) -> void: mat.set_shader_parameter("intensity", v), mat.get_shader_parameter("intensity") as float, intensity, duration)
	var sparks := aura.get_node("Sparks") as CPUParticles2D
	t.tween_property(sparks, "color", color.lightened(0.3), duration)
	return t


## 卡片左右颤动 count 下。
func _jitter(slot: Control, count: int, angle: float) -> void:
	var shake := create_tween()
	for i in count:
		shake.tween_property(slot, "rotation", angle if i % 2 == 0 else -angle, 0.05)
	shake.tween_property(slot, "rotation", 0.0, 0.05)
	await shake.finished


## 四玉翻开前：卡片颤动，卡边冒出紫光、顶上一道光柱。
func _build_up(slot: Control, tier: int) -> void:
	var aura := _add_aura(slot, UiKit.TIER_COLORS[tier])
	_aura_to(aura, UiKit.TIER_COLORS[tier], 1.0, 0.25)
	Sfx.play(&"rare_shimmer", -6.0)
	await _jitter(slot, 6, 0.05)


## 五玉翻开前（全屏）：整屏压暗，这张卡背飞到正中放大；全屏的光芒和卡边的光跟着心跳一涨一退，
## 每次都像要炸开又缩回去，白光、蓝光、紫光各涨几次，越涨越亮、卡抖得越凶，四周的光点往卡上聚。
## 最后一次涨到最高，突然全收回去、静一下，再一闪炸成金光。之后原位的卡带着金光，接着翻开。
func _build_up_gold(slot: Control) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.008, 0.006, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := Vector2(size.x / 2, size.y * 0.5)
	var rays := _rays(size * 1.9, GOLD_PHASES[0], 0.16, 0.85)
	rays.position = center - rays.size / 2
	var rays_mat := rays.material as ShaderMaterial
	rays_mat.set_shader_parameter("intensity", 0.0)
	layer.add_child(rays)
	# 四周的光点往中间聚
	var gather := _soft_particles(GOLD_PHASES[0], 50)
	gather.position = center
	gather.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	gather.emission_ring_radius = 560.0
	gather.emission_ring_inner_radius = 380.0
	gather.gravity = Vector2.ZERO
	gather.initial_velocity_min = 0.0
	gather.initial_velocity_max = 0.0
	gather.radial_accel_min = -820.0
	gather.radial_accel_max = -780.0
	gather.lifetime = 1.05
	gather.scale_amount_min = 0.3
	gather.scale_amount_max = 0.8
	layer.add_child(gather)
	# 卡背从原位飞到正中（原位的先藏起来）
	var lift := Control.new()
	lift.size = CARD_SIZE
	lift.pivot_offset = CARD_SIZE / 2
	lift.z_index = 2
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := TextureRect.new()
	back.texture = load("res://art/ui/card_back.png")
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lift.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(lift)
	lift.position = slot.global_position - layer.global_position
	slot.modulate.a = 0.0
	var aura := _add_aura(lift, GOLD_PHASES[0])
	var t := create_tween().set_parallel()
	t.tween_property(dim, "color:a", 0.88, 0.4)
	t.tween_property(lift, "position", center - CARD_SIZE / 2, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(lift, "scale", Vector2.ONE * GOLD_LIFT_SCALE, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await t.finished

	var level := 0.25
	for color in GOLD_PHASES:
		var shift := create_tween().set_parallel()
		shift.tween_method(_set_param.bind(rays_mat, "color"), rays_mat.get_shader_parameter("color") as Color, color, 0.2)
		shift.tween_property(gather, "color", color.lightened(0.3), 0.2)
		_aura_to(aura, color, level, 0.2)
		for n in SWELLS_PER_PHASE:
			level += 0.1
			await _swell(rays_mat, aura, lift, level + 0.55, level)
	# 最后一次涨到最高，突然全收回去，静一下……
	gather.emitting = false
	await _swell(rays_mat, aura, lift, level + 1.0, 0.0)
	var hush := create_tween().set_parallel()
	hush.tween_property(dim, "color:a", 0.95, 0.2)
	await get_tree().create_timer(GOLD_HUSH).timeout

	# ……炸成金光
	var gold: Color = UiKit.TIER_COLORS[UnitData.Tier.JIA]
	rays_mat.set_shader_parameter("color", gold)
	rays_mat.set_shader_parameter("intensity", 2.2)
	(aura.material as ShaderMaterial).set_shader_parameter("color", gold)
	(aura.material as ShaderMaterial).set_shader_parameter("intensity", 2.0)
	_flash(Color(1, 0.97, 0.85))
	_shake(16.0)
	Sfx.play(&"token_slam")
	Sfx.play(&"rare_shimmer", -1.0)
	var burst := create_tween()
	burst.tween_property(lift, "scale", Vector2.ONE * GOLD_LIFT_SCALE * 1.15, 0.12).set_ease(Tween.EASE_OUT)
	burst.tween_property(lift, "scale", Vector2.ONE * GOLD_LIFT_SCALE, 0.2)
	await get_tree().create_timer(0.5).timeout
	# 卡带着金光飞回原位、缩回原大小，压暗和全屏光芒一起退掉；然后换回原位的卡（也带金光），接着翻开
	var home := slot.global_position - layer.global_position
	var back_t := create_tween().set_parallel()
	back_t.tween_property(lift, "position", home, 0.35).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	back_t.tween_property(lift, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	back_t.tween_property(dim, "color:a", 0.0, 0.35)
	back_t.tween_property(rays, "modulate:a", 0.0, 0.35)
	_aura_to(aura, gold, 1.4, 0.35)
	await back_t.finished
	slot.modulate.a = 1.0
	var slot_aura := _add_aura(slot, gold)
	_aura_to(slot_aura, gold, 1.4, 0.01)
	layer.queue_free()


func _set_param(value: Variant, mat: ShaderMaterial, param: String) -> void:
	mat.set_shader_parameter(param, value)


## 涨一次：光芒和卡边的光越来越快地涨到 peak（卡跟着胀大、抖），像要炸开，又退回 rest。
func _swell(rays_mat: ShaderMaterial, aura: ColorRect, lift: Control, peak: float, rest: float) -> void:
	var aura_mat := aura.material as ShaderMaterial
	Sfx.play(&"skill_drum", -4.0 + peak * 2.0)
	var up := create_tween().set_parallel()
	up.tween_method(_set_param.bind(rays_mat, "intensity"), rays_mat.get_shader_parameter("intensity") as float, peak, SWELL_UP).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	up.tween_method(_set_param.bind(aura_mat, "intensity"), aura_mat.get_shader_parameter("intensity") as float, peak * 0.9, SWELL_UP).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	up.tween_property(lift, "scale", Vector2.ONE * GOLD_LIFT_SCALE * (1.0 + 0.05 * peak), SWELL_UP).set_ease(Tween.EASE_IN)
	_jitter(lift, int(SWELL_UP / 0.05), 0.012 + 0.012 * peak)
	await up.finished
	Sfx.play(&"rare_shimmer", -10.0 + peak * 2.0)
	var down := create_tween().set_parallel()
	down.tween_method(_set_param.bind(rays_mat, "intensity"), peak, rest, SWELL_DOWN).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	down.tween_method(_set_param.bind(aura_mat, "intensity"), peak * 0.9, rest, SWELL_DOWN).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	down.tween_property(lift, "scale", Vector2.ONE * GOLD_LIFT_SCALE, SWELL_DOWN).set_ease(Tween.EASE_OUT)
	await down.finished
	await get_tree().create_timer(SWELL_REST).timeout


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
	# 翻开后卡后的光收一收，留一圈淡淡的
	var aura := slot.get_node_or_null("Aura") as ColorRect
	if aura != null:
		_aura_to(aura, (aura.material as ShaderMaterial).get_shader_parameter("color"), 0.55, 0.6)


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

	# 背后的金光：白热的光核、柔和光晕、粗细不一慢慢流转的光芒（叠加混合）
	var rays := _rays(Vector2(size.x * 1.6, size.y * 1.6), gold, 0.14, 0.7)
	rays.position = center - rays.size / 2
	layer.add_child(rays)

	# 金色光点往上飘
	var motes := _soft_particles(gold.lightened(0.3), 70)
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
	motes.scale_amount_min = 0.2
	motes.scale_amount_max = 0.6
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
