class_name RecruitView
extends Control
## 聚义厅招募：用聚义令单抽或十连，卡片一张张翻开。

signal back_requested

## 十连两排卡片要和按钮一起放进 720 高的屏幕
const CARD_SIZE := Vector2(190, 206)
const REVEAL_DELAY := 0.18

var _rng := RandomNumberGenerator.new()
var _tokens_label: Label
var _pity_label: Label
var _single: Button
var _ten: Button
var _back: Button
var _cards: GridContainer
var _revealing := false


func _ready() -> void:
	_rng.randomize()
	var bg := ColorRect.new()
	bg.color = Color("221a14")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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

	var rates := PackedStringArray()
	for i in Gacha.RATES.size():
		rates.append("%s %d%%" % [UiKit.TIER_NAMES[i], Gacha.RATES[i]])
	v.add_child(UiKit.label("概率：%s。十连至少一个乙或以上；%d 抽内必出甲。重复的好汉变成将魂 +%d（升星用）。" % ["、".join(rates), Gacha.PITY_JIA, Gacha.DUPLICATE_SOULS], 16, UiKit.TEXT_DIM))
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
	_refresh()


func _refresh() -> void:
	_tokens_label.text = "聚义令 %d" % GameState.tokens
	var left := Gacha.PITY_JIA - GameState.pulls_since_jia
	var first := "（第一次十连必出甲）" if not GameState.has_flag("first_ten_pull") else ""
	_pity_label.text = "距保底甲还有 %d 抽　已招募 %d / %d 位好汉 %s" % [left, GameState.owned.size(), GameDB.heroes.size(), first]
	_single.disabled = _revealing or GameState.tokens < 1
	_ten.disabled = _revealing or GameState.tokens < 10
	_back.disabled = _revealing


func _recruit(count: int) -> void:
	var results := GameState.recruit(count, _rng)
	if results.is_empty():
		return
	_revealing = true
	_refresh()
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	_cards.columns = mini(count, 5)
	for r in results:
		var card := _make_card(r["hero"], r["is_new"])
		_cards.add_child(card)
		card.pivot_offset = CARD_SIZE / 2
		card.scale = Vector2(0.2, 0.2)
		card.modulate.a = 0.0
		var t := create_tween().set_parallel()
		t.tween_property(card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(card, "modulate:a", 1.0, 0.15)
		var hero: UnitData = r["hero"]
		if hero.tier == UnitData.Tier.JIA:
			_celebrate(card)
			await get_tree().create_timer(0.5).timeout
		else:
			await get_tree().create_timer(REVEAL_DELAY).timeout
	_revealing = false
	_refresh()


func _make_card(hero: UnitData, is_new: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	var color := UiKit.TIER_COLORS[hero.tier]
	card.add_theme_stylebox_override("panel", UiKit.box(UiKit.role_color(hero), color, 5 if hero.tier <= UnitData.Tier.YI else 3, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var tier := UiKit.label(UiKit.TIER_NAMES[hero.tier], 30, color)
	tier.add_theme_constant_override("outline_size", 6)
	tier.add_theme_color_override("font_outline_color", Color.BLACK)
	head.add_child(tier)
	var tag := UiKit.label("新！" if is_new else "将魂 +%d" % Gacha.DUPLICATE_SOULS, 18, UiKit.GOLD if is_new else UiKit.TEXT_DIM)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(tag)
	var bust := UiKit.unit_picture(hero, 108)
	bust.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(bust)
	var name := UiKit.label(hero.display_name, 26)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)
	var sub := UiKit.label("%s · %s" % [hero.nickname, UiKit.RARITY_NAMES[hero.rarity]], 15, UiKit.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	UiKit.ignore_mouse(card)
	return card


## 抽到甲：卡片金光闪动，画面一震。
func _celebrate(card: Control) -> void:
	var glow := card.create_tween().set_loops(3)
	glow.tween_property(card, "self_modulate", Color(1.8, 1.6, 0.9), 0.12)
	glow.tween_property(card, "self_modulate", Color.WHITE, 0.12)
	var shake := create_tween()
	for i in 6:
		var k := 10.0 * (1.0 - i / 6.0)
		shake.tween_property(self, "position", Vector2(randf_range(-k, k), randf_range(-k, k)), 0.03)
	shake.tween_property(self, "position", Vector2.ZERO, 0.03)
