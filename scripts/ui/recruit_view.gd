class_name RecruitView
extends Control
## 聚义厅招募：用聚义令单抽或五连（参考三国志战略版：五张竖卡排一排，不再两排挤着）。
## 演出：按下按钮先沉一下 → 画面压暗，做旧的聚义令旋转落下、悬在半空，光从蓝色一次次变色（这一抽越好悬得越久、变色越多，
## 出五玉时只变到更亮的紫，留个悬念），再「咚」地砸下（越好砸得越重）→ 锦缎卡背一张张落下 → 逐张翻开。
## 四玉翻开前颤动、卡边冒紫光、光点往卡上聚，再立体翻开、高光扫过；五玉翻开前卡飞到屏幕正中，全屏的光一涨一退，
## 先白光、再紫光，呼之欲出又迟迟不出，最后炸成金光，立体翻开后全屏登场：金边剪影→上色→勾玉逐颗点亮→名字（只有五玉有全屏）。
## 一路配手机震动（三玉轻、四玉中、五玉强，设置里能关）。翻牌时点屏幕跳过（五玉的变色和登场照放）。

signal back_requested

## 五连一排竖卡，和按钮一起放进 720 高的屏幕
const CARD_SIZE := Vector2(220, 330)
const REVEAL_DELAY := 0.12
## 五玉翻开前的全屏变色：先白光、再紫光，每次「涨上去、像要炸开、又退回来」（心跳一样），
## 最后涨到最高、突然全收回去静一下，再炸成金光。紫光比品级色更饱和，叠加在亮处也看得出颜色
const GOLD_PHASES: Array[Color] = [Color(1, 0.97, 0.9), Color("a35cff")]
## 每种光涨几次（和 GOLD_PHASES 一一对应）：白光 1 次，紫光 2 次
const GOLD_SWELLS: Array[int] = [1, 2]
## 一次涨、退各用几秒，退完停多久
const SWELL_UP := 0.5
const SWELL_DOWN := 0.3
const SWELL_REST := 0.1
## 炸开前全收回去后，静多久
const GOLD_HUSH := 0.45
## 全屏光芒的矩形是屏幕的几倍（光在矩形内切圆边上淡到 0，要比屏幕对角线大，四角才不发暗）
const FULL_RAYS := 2.8
## 卡飞到正中后放大多少
const GOLD_LIFT_SCALE := 1.45
## 卡背后的光比卡大出的边（左右、下、上；上面留得多，好放光柱）
const AURA_PAD := Vector4(150, 120, 150, 330)
const LIGHT_RAYS := preload("res://scripts/ui/shaders/light_rays.gdshader")
const CARD_AURA := preload("res://scripts/ui/shaders/card_aura.gdshader")
## 聚义令落地后的大小（图高 520，落地后约 430）
const TOKEN_SCALE := 0.82
## 聚义令落下后悬在半空多久再砸下（按这一抽最好的品级：五玉、四玉、三玉、二玉），悬着的时候光一次次变色。
## 加上落下、砸地、收走，三玉约 1.3 秒、四玉约 2 秒、五玉约 3 秒
const TOKEN_HOVER: Array[float] = [1.5, 0.75, 0.0, 0.0]
## 出五玉时，聚义令的光蓝→紫之后再变一次「更亮的紫」，不露出金色
const TOKEN_HINT_BRIGHT := Color("d0a8ff")
## 四玉翻开前光点往卡上聚、停多久
const RARE_GATHER := 0.3
## 立体翻牌（四玉、五玉）：转一圈用几秒、眼睛离卡多远（越近透视越夸张）、卡有多厚（像素）
const FLIP_TIME_YI := 0.45
const FLIP_TIME_JIA := 0.85
const FLIP_DEPTH_YI := 1800.0
const FLIP_DEPTH_JIA := 650.0
const FLIP_THICKNESS := 10.0
## 翻牌画面比卡大出的边（透视下近的一边会变大）；正面按几倍分辨率画，手机上不糊
const FLIP_MARGIN := Vector2(70, 80)
const FLIP_RES := 2
const CARD_FLIP := preload("res://scripts/ui/shaders/card_flip.gdshader")
const SILHOUETTE := preload("res://scripts/ui/shaders/silhouette.gdshader")
## 五玉登场：立绘先是金边剪影，停多久再上色、上色用多久
const SILHOUETTE_HOLD := 0.45
const SILHOUETTE_FADE := 0.6
## 勾玉一颗颗点亮的间隔
const MAGATAMA_STEP := 0.12
## 抽卡按钮按下去下沉多久、缩到多小
const PRESS_TIME := 0.15
const PRESS_SCALE := 0.93
## 聚义厅背景（供案、红烛、前排柱上两条空白红对联，见 art/prompts/recruit_hall.txt）
const HALL_TEXTURE := "res://art/ui/recruit_hall.jpg"
## 对联：写在背景画里那两条红纸上（横坐标是红纸的中线，按背景原图 1280×720 的像素算；
## 屏幕更宽时背景放大裁切，对联和聚义令跟着背景换算位置，见 _place_on_hall）
const COUPLETS := [["四海英雄同聚义", 143.0], ["八方豪杰共结盟", 1143.0]]
const COUPLET_TOP := 98.0
## 没在抽卡时，聚义令立在供案正中
const IDLE_TOKEN_RECT := Rect2(590, 176, 100, 310)

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
## 供案上立着的那块聚义令（抽卡、翻牌时收起来）
var _idle_token: Control
var _hall: TextureRect
var _couplets: Array[Label] = []
var _idle_glow: TextureRect
var _idle_pic: TextureRect


func _ready() -> void:
	_rng.randomize()
	var bg := ColorRect.new()
	bg.color = Color("221a14")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 聚义厅大堂（水墨淡彩）：供案、红烛、香炉都画在图里
	var hall := TextureRect.new()
	_hall = hall
	hall.texture = load(HALL_TEXTURE)
	hall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	hall.modulate = Color(0.86, 0.82, 0.78)
	hall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hall)
	hall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for c: Array in COUPLETS:
		var couplet := UiKit.brush_label(UiKit.vertical_text(c[0]), 40, Color(0.1, 0.06, 0.04, 0.85))
		couplet.add_theme_constant_override("line_spacing", -12)
		couplet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		couplet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(couplet)
		_couplets.append(couplet)

	_idle_token = Control.new()
	_idle_token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_idle_token)
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.86, 0.55, 0.55))
	grad.set_color(1, Color(1.0, 0.86, 0.55, 0.0))
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = grad
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(0.5, 0.0)
	glow.texture = glow_tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_idle_token.add_child(glow)
	_idle_glow = glow
	var idle := TextureRect.new()
	idle.texture = load("res://art/ui/juyi_token_old.png")
	idle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	idle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	idle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_idle_token.add_child(idle)
	_idle_pic = idle
	resized.connect(_place_on_hall)
	_place_on_hall()

	var title := UiKit.title_plaque("聚　义　厅", 40)
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 8

	var corner := HBoxContainer.new()
	corner.add_theme_constant_override("separation", 14)
	corner.alignment = BoxContainer.ALIGNMENT_END
	add_child(corner)
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.offset_left = -400
	corner.offset_right = -20
	corner.offset_top = 14
	var purse := PanelContainer.new()
	purse.add_theme_stylebox_override("panel", UiKit.lacquer_box())
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var purse_row := UiKit.amount_row(UiKit.token_icon(), "", 18)
	purse.add_child(purse_row)
	_tokens_label = purse_row.get_child(1) as Label
	corner.add_child(purse)
	_back = UiKit.back_button()
	_back.pressed.connect(func() -> void:
		if not _revealing:
			back_requested.emit())
	corner.add_child(_back)

	# 右下角一张招募榜文：每档几率、保底、已招多少人
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", UiKit.note_box())
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	board.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	board.grow_vertical = Control.GROW_DIRECTION_BEGIN
	board.offset_right = -16
	board.offset_bottom = -12
	var rates := VBoxContainer.new()
	rates.add_theme_constant_override("separation", 2)
	rates.custom_minimum_size.x = 200
	board.add_child(rates)
	rates.add_child(UiKit.brush_label("招募榜文", 22, UiKit.INK))
	for i in Gacha.RATES.size():
		var r := HBoxContainer.new()
		r.add_child(MagatamaRow.for_tier(i, 14))
		var pct := UiKit.label("%d%%" % Gacha.RATES[i], 15, UiKit.INK)
		pct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(pct)
		rates.add_child(r)
	var rule := UiKit.label("五连至少一个四玉；%d 抽必出五玉；重复的好汉化为将魂 +%d" % [Gacha.PITY_JIA, Gacha.DUPLICATE_SOULS], 12, UiKit.INK_DIM)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.custom_minimum_size.x = 200
	rates.add_child(rule)
	_pity_label = UiKit.label("", 13, UiKit.CINNABAR)
	_pity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pity_label.custom_minimum_size.x = 200
	rates.add_child(_pity_label)
	UiKit.ignore_mouse(board)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 74)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)

	# 五张竖卡排成一排，按钮在供案前、香炉两边
	var stage := CenterContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stage)
	_cards = GridContainer.new()
	_cards.columns = Gacha.MULTI
	_cards.add_theme_constant_override("h_separation", 22)
	stage.add_child(_cards)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 300)
	v.add_child(buttons)
	_single = UiKit.plaque_button("单　抽", Vector2(200, 62), false, 32)
	_single.tooltip_text = "用 1 枚聚义令"
	_single.pressed.connect(_recruit.bind(1))
	buttons.add_child(_single)
	_multi = UiKit.plaque_button("五　连", Vector2(220, 68), true, 34)
	_multi.tooltip_text = "用 %d 枚聚义令" % Gacha.MULTI
	_multi.pressed.connect(_recruit.bind(Gacha.MULTI))
	buttons.add_child(_multi)
	_press_feel(_single)
	_press_feel(_multi)
	var costs := HBoxContainer.new()
	costs.alignment = BoxContainer.ALIGNMENT_CENTER
	costs.add_theme_constant_override("separation", 420)
	costs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(costs)
	for n in [1, Gacha.MULTI]:
		var cost := UiKit.amount_row(UiKit.token_icon(20), "× %d" % n, 15)
		costs.add_child(cost)

	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.z_index = 20
	add_child(_fx)
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh()


## 对联、供案上的聚义令按背景画换算到屏幕上（背景铺满屏幕时会按宽窄放大裁切）。
func _place_on_hall() -> void:
	var t := UiKit.cover_transform(size, _hall.texture.get_size())
	var s: float = t[0]
	var offset: Vector2 = t[1]
	for i in _couplets.size():
		var l := _couplets[i]
		l.add_theme_font_size_override("font_size", int(40 * s))
		l.add_theme_constant_override("line_spacing", -int(12 * s))
		l.size = Vector2(48, 420) * s
		l.position = offset + Vector2(COUPLETS[i][1] - 24, COUPLET_TOP) * s
	_idle_pic.position = offset + IDLE_TOKEN_RECT.position * s
	_idle_pic.size = IDLE_TOKEN_RECT.size * s
	_idle_glow.size = Vector2(360, 380) * s
	_idle_glow.position = offset + (IDLE_TOKEN_RECT.get_center() - Vector2(180, 190)) * s


## 抽卡按钮的按压手感：按下时 0.15 秒沉下去、缩一点、变暗（像按进去），松开时弹回来。
func _press_feel(b: Button) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size / 2)
	b.button_down.connect(func() -> void:
		var t := b.create_tween().set_parallel()
		t.tween_property(b, "scale", Vector2.ONE * PRESS_SCALE, PRESS_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(b, "modulate", Color(0.8, 0.74, 0.68), PRESS_TIME))
	b.button_up.connect(func() -> void:
		var t := b.create_tween().set_parallel()
		t.tween_property(b, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(b, "modulate", Color.WHITE, 0.2))


## 翻牌时点屏幕：剩下的直接翻开。
func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and _revealing and not _in_showcase:
		_skip = true


func _refresh() -> void:
	_tokens_label.text = "聚义令 %d" % GameState.tokens
	_idle_token.visible = not _revealing and _cards.get_child_count() == 0
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


## 聚义令：画面压暗，一块乌木铜边的竖令牌晃着从上方落下，悬在半空，「咚」地砸在地上，冲出一圈光。
## 光先是蓝色，这一抽越好、悬得越久，中途一次次变色、每变一次闪一下、叮一声（一声比一声高）：
## 三玉直接砸下；四玉 蓝→紫；五玉 蓝→紫→更亮的紫（金光留到翻那张卡的时候），砸得也更重（全屏一闪、震得更久、手机强震）。
func _token_strike(best: int) -> void:
	var shown := maxi(best, UnitData.Tier.YI)
	var hints: Array[Color] = []
	if best <= UnitData.Tier.YI:
		hints.append(UiKit.TIER_COLORS[UnitData.Tier.YI])
	if best == UnitData.Tier.JIA:
		hints.append(TOKEN_HINT_BRIGHT)
	var color: Color = UiKit.TIER_COLORS[maxi(shown, UnitData.Tier.BING)] if hints.is_empty() else UiKit.TIER_COLORS[UnitData.Tier.BING]
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
	var glow_mat := glow.material as ShaderMaterial
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
	# 悬着：轻轻上下浮、摆正，光一次次变色
	var hover := TOKEN_HOVER[best] * fast
	if hover > 0.0:
		var bob := token.create_tween().set_loops()
		bob.tween_property(token, "position:y", land.y - 72, 0.35).set_trans(Tween.TRANS_SINE)
		bob.tween_property(token, "position:y", land.y - 60, 0.35).set_trans(Tween.TRANS_SINE)
		create_tween().tween_property(token, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
		var step := hover / (hints.size() + 1)
		for i in hints.size():
			await get_tree().create_timer(step).timeout
			_token_hint(token, glow_mat, hints[i], i)
		await get_tree().create_timer(step).timeout
		bob.kill()
		color = hints[-1]
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
	# 砸地的轻重：三玉只散一圈小光浪；四玉光浪 + 轻震 0.25 秒；五玉两圈光浪 + 全屏一闪 + 震 0.5 秒
	match best:
		UnitData.Tier.JIA:
			_shockwave(foot, color, 9.0)
			get_tree().create_timer(0.12).timeout.connect(_shockwave.bind(foot, color, 6.0))
			_flash(color)
			_shake(16.0, 0.5)
			Haptics.pulse(Haptics.Level.STRONG)
			Sfx.play(&"token_slam", 2.0)
		UnitData.Tier.YI:
			_shockwave(foot, color, 7.0)
			_shake(8.0, 0.25)
			Haptics.pulse(Haptics.Level.MEDIUM)
			Sfx.play(&"token_slam")
		_:
			_shockwave(foot, color, 4.0)
			Haptics.pulse(Haptics.Level.LIGHT)
			Sfx.play(&"token_slam", -5.0)
	await get_tree().create_timer(0.45 * fast).timeout
	var out := create_tween().set_parallel()
	out.tween_property(token, "modulate:a", 0.0, 0.3)
	out.tween_property(token, "position:y", land.y - 20, 0.3)
	out.tween_property(dim, "color:a", 0.0, 0.5)
	await get_tree().create_timer(0.25 * fast).timeout
	out.finished.connect(func() -> void:
		token.queue_free()
		dim.queue_free())


## 聚义令的光变一次色：光芒一下子胀亮再落回、令牌一闪，叮一声；第 n 次变色音调升高一级（像上升的音阶）。
func _token_hint(token: Control, glow_mat: ShaderMaterial, color: Color, n: int) -> void:
	glow_mat.set_shader_parameter("color", color)
	var pop := create_tween()
	pop.tween_method(_set_param.bind(glow_mat, "intensity"), 2.2 + n * 0.6, 1.0 + n * 0.3, 0.45).set_ease(Tween.EASE_OUT)
	token.modulate = Color(1.8, 1.6, 2.0)
	create_tween().tween_property(token, "modulate", Color.WHITE, 0.3)
	Sfx.play(&"rare_shimmer", -4.0 + n * 2.0, 0.0, 1.0 + n * 0.26)
	Sfx.play(&"skill_drum", -8.0 + n * 2.0)
	Haptics.pulse(Haptics.Level.LIGHT)


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
func _shockwave(at: Vector2, color: Color, reach := 7.0) -> void:
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
	t.tween_property(ring, "scale", Vector2.ONE * reach, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
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


## 震屏：strength 像素，duration 秒内越震越轻。
func _shake(strength: float, duration := 0.2) -> void:
	var t := create_tween()
	var steps := maxi(3, int(duration / 0.03))
	for i in steps:
		var k := strength * (1.0 - float(i) / steps)
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


## 四玉翻开前：卡片颤动，卡边冒出紫光、顶上一道光柱；再停 0.3 秒，四周的光点往卡上聚。
func _build_up(slot: Control, tier: int) -> void:
	var color: Color = UiKit.TIER_COLORS[tier]
	var aura := _add_aura(slot, color)
	_aura_to(aura, color, 1.0, 0.25)
	Sfx.play(&"rare_shimmer", -6.0)
	Sfx.play(&"skill_drum", -8.0)
	await _jitter(slot, 6, 0.05)
	var gather := _soft_particles(color.lightened(0.4), 26)
	gather.position = Vector2(AURA_PAD.x, AURA_PAD.w) + CARD_SIZE / 2
	gather.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	gather.emission_ring_radius = 260.0
	gather.emission_ring_inner_radius = 190.0
	gather.gravity = Vector2.ZERO
	gather.initial_velocity_min = 0.0
	gather.initial_velocity_max = 0.0
	gather.radial_accel_min = -700.0
	gather.radial_accel_max = -620.0
	gather.lifetime = 0.6
	gather.one_shot = true
	gather.explosiveness = 0.6
	aura.add_child(gather)
	gather.finished.connect(gather.queue_free)
	_aura_to(aura, color, 1.3, RARE_GATHER)
	await get_tree().create_timer(RARE_GATHER).timeout


## 五玉翻开前（全屏）：整屏压暗，这张卡背飞到正中放大；全屏的光芒和卡边的光跟着心跳一涨一退，
## 每次都像要炸开又缩回去，先白光、再紫光，越涨越亮、卡抖得越凶，四周的光点往卡上聚。
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
	var rays := _rays(size * FULL_RAYS, GOLD_PHASES[0], 0.16 / FULL_RAYS * 1.9, 0.85)
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
	for k in GOLD_PHASES.size():
		var color := GOLD_PHASES[k]
		var shift := create_tween().set_parallel()
		shift.tween_method(_set_param.bind(rays_mat, "color"), rays_mat.get_shader_parameter("color") as Color, color, 0.2)
		shift.tween_property(gather, "color", color.lightened(0.3), 0.2)
		_aura_to(aura, color, level, 0.2)
		for n in GOLD_SWELLS[k]:
			level += 0.15
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
	_shake(16.0, 0.4)
	_rumble()
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
	get_tree().create_timer(SWELL_UP * 0.85).timeout.connect(Haptics.pulse.bind(Haptics.Level.LIGHT if peak < 1.2 else Haptics.Level.MEDIUM))
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


## 强震之后再跟两下，像余震（五玉炸开、翻开时用）。
func _rumble() -> void:
	Haptics.pulse(Haptics.Level.STRONG)
	for k in 2:
		get_tree().create_timer(0.22 * (k + 1)).timeout.connect(Haptics.pulse.bind(Haptics.Level.MEDIUM))


## 翻牌。四玉、五玉（没跳过时）立体翻：见 _flip_3d；其余横着收窄到 0、换成正面、再展开。
func _flip(slot: Control, tier: int, rare: bool) -> void:
	if tier == UnitData.Tier.JIA or (rare and not _skip):
		await _flip_3d(slot, tier)
	else:
		await _flip_flat(slot, tier, rare)
	# 翻开后卡后的光收一收，留一圈淡淡的
	var aura := slot.get_node_or_null("Aura") as ColorRect
	if aura != null:
		_aura_to(aura, (aura.material as ShaderMaterial).get_shader_parameter("color"), 0.55, 0.6)


func _flip_flat(slot: Control, tier: int, rare: bool) -> void:
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
		Haptics.pulse(Haptics.Level.MEDIUM)
	var t2 := create_tween()
	t2.tween_property(slot, "scale:x", 1.0, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await t2.finished


## 立体翻牌（card_flip.gdshader）：卡像一块有厚度的板绕竖轴转过来，转到侧面露出金色的卡边，翻开后一道高光从卡面扫过。
## 四玉转得快、透视轻；五玉转得慢、透视重，转到正面那一下金光炸开、震屏、手机强震。
## 正面（好汉卡）临时挪进一个 SubViewport 画成图给 shader 用，翻完放回原处。
func _flip_3d(slot: Control, tier: int) -> void:
	var gold := tier == UnitData.Tier.JIA
	var front := slot.get_node("Front") as Control
	var back := slot.get_node("Back") as TextureRect
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.size = Vector2i(CARD_SIZE) * FLIP_RES
	vp.size_2d_override = Vector2i(CARD_SIZE)
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# SubViewport 里不继承外面的主题（字体），手动套上
	var holder := Control.new()
	holder.theme = _outer_theme()
	holder.size = CARD_SIZE
	vp.add_child(holder)
	slot.add_child(vp)
	var front_index := front.get_index()
	slot.remove_child(front)
	holder.add_child(front)
	front.visible = true
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var view := ColorRect.new()
	view.color = Color.WHITE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.position = -FLIP_MARGIN
	view.size = CARD_SIZE + FLIP_MARGIN * 2
	var mat := ShaderMaterial.new()
	mat.shader = CARD_FLIP
	mat.set_shader_parameter("front_tex", vp.get_texture())
	mat.set_shader_parameter("back_tex", back.texture)
	mat.set_shader_parameter("rect_size", view.size)
	mat.set_shader_parameter("card_size", CARD_SIZE)
	mat.set_shader_parameter("depth", FLIP_DEPTH_JIA if gold else FLIP_DEPTH_YI)
	mat.set_shader_parameter("thickness", FLIP_THICKNESS)
	mat.set_shader_parameter("edge_color", Color("c89838") if gold else Color("8a6cc0"))
	view.material = mat
	slot.add_child(view)
	back.visible = false

	var turn := FLIP_TIME_JIA if gold else FLIP_TIME_YI
	Sfx.play(&"card_flip", -2.0, 0.05, 0.85 if gold else 1.0)
	var t := create_tween()
	t.tween_method(_set_param.bind(mat, "angle"), 0.0, PI * 0.5, turn * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	await t.finished
	# 转到侧面：正面亮起来
	view.modulate = Color(2.2, 2.0, 1.4)
	create_tween().tween_property(view, "modulate", Color.WHITE, 0.4)
	if gold:
		_flash(UiKit.TIER_COLORS[UnitData.Tier.JIA])
		_shake(12.0, 0.35)
		_rumble()
		Sfx.play(&"jia_gong")
	else:
		Haptics.pulse(Haptics.Level.MEDIUM)
		Sfx.play(&"rare_shimmer", -6.0, 0.0, 1.3)
	var t2 := create_tween()
	t2.tween_method(_set_param.bind(mat, "angle"), PI * 0.5, PI, turn * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await t2.finished
	var sweep := create_tween()
	sweep.tween_method(_set_param.bind(mat, "sweep"), -0.3, 1.3, 0.45).set_ease(Tween.EASE_IN_OUT)
	await sweep.finished
	# 放回原处
	holder.remove_child(front)
	slot.add_child(front)
	slot.move_child(front, front_index)
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.queue_free()
	vp.queue_free()


## 往上找套着主题的那一层（main.gd 在最外层套了 UiKit.make_theme()）。
func _outer_theme() -> Theme:
	var n: Node = self
	while n != null:
		var c := n as Control
		if c != null and c.theme != null:
			return c.theme
		n = n.get_parent()
	return null


## 五玉金卡：整屏转成金色，背后金光放射、慢慢转，全身立绘从中间升起——先是一道金边的剪影，0.45 秒后再慢慢上色；
## 接着勾玉一颗颗点亮（每颗 0.12 秒、一声比一声高），名字最后出现。之后是余韵：光点慢慢飘，立绘轻轻「呼吸」，背景慢慢推近。
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
	# 背景：聚义厅大堂染成暗金色，慢慢推近
	var hall_path := StoryScript.background_path("juyiting")
	var hall: TextureRect = null
	if hall_path != "":
		hall = TextureRect.new()
		hall.texture = load(hall_path)
		hall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		hall.modulate = Color(0.42, 0.3, 0.14)
		hall.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hall.size = size
		hall.pivot_offset = size / 2
		layer.add_child(hall)

	# 背后的金光：白热的光核、柔和光晕、粗细不一慢慢流转的光芒（叠加混合）
	var rays := _rays(size * FULL_RAYS, gold, 0.14 / FULL_RAYS * 1.6, 0.7)
	rays.position = center - rays.size / 2
	rays.pivot_offset = rays.size / 2
	(rays.material as ShaderMaterial).set_shader_parameter("spin", 0.06)
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
	fig.pivot_offset = Vector2(fig.size.x / 2, fig.size.y)
	fig.modulate.a = 0.0
	var sil := ShaderMaterial.new()
	sil.shader = SILHOUETTE
	sil.set_shader_parameter("rim_color", gold.lightened(0.25))
	if fig.texture != null:
		# 金边在屏幕上大约 7 像素宽
		sil.set_shader_parameter("rim_width", 7.0 * fig.texture.get_height() / fig_h)
	fig.material = sil
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
	var stones := MagatamaRow.for_tier(hero.tier, 34)
	top.add_child(stones)
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
	# 立绘升起（剪影）→ 停 0.45 秒 → 上色
	var rise := 0.6
	var color_at := 0.15 + rise + SILHOUETTE_HOLD
	var t := create_tween().set_parallel()
	t.tween_property(layer, "modulate:a", 1.0, 0.25)
	t.tween_property(fig, "position", fig_to, rise).set_delay(0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(fig, "modulate:a", 1.0, 0.35).set_delay(0.15)
	t.tween_method(_set_param.bind(sil, "reveal"), 0.0, 1.0, SILHOUETTE_FADE).set_delay(color_at)
	t.tween_property(info, "modulate:a", 1.0, 0.4).set_delay(color_at + 0.2)
	t.tween_callback(Sfx.play.bind(&"rare_shimmer", -4.0, 0.0, 1.2)).set_delay(color_at)
	# 余韵：背景、光芒慢慢推近
	var push := layer.create_tween().set_parallel()
	push.tween_property(rays, "scale", Vector2.ONE * 1.12, 12.0).set_trans(Tween.TRANS_SINE)
	if hall != null:
		push.tween_property(hall, "scale", Vector2.ONE * 1.1, 12.0).set_trans(Tween.TRANS_SINE)
	await t.finished
	# 勾玉一颗颗点亮，叮叮叮一声比一声高
	for k in stones.count:
		stones.filled = k + 1
		stones.queue_redraw()
		Sfx.play(&"ui_click", -2.0, 0.0, 1.0 + k * 0.15)
		await get_tree().create_timer(MAGATAMA_STEP).timeout
	# 名字最后出现
	var t2 := create_tween().set_parallel()
	t2.tween_property(name_col, "modulate:a", 1.0, 0.4)
	t2.tween_property(nick_col, "modulate:a", 1.0, 0.4).set_delay(0.2)
	t2.tween_property(hint, "modulate:a", 1.0, 0.3).set_delay(0.5)
	Sfx.play(&"jia_gong", -8.0)
	# 立绘轻轻「呼吸」
	var breathe := fig.create_tween().set_loops()
	breathe.tween_property(fig, "scale", Vector2(1.012, 1.018), 1.6).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(fig, "scale", Vector2.ONE, 1.6).set_trans(Tween.TRANS_SINE)
	await t2.finished
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
