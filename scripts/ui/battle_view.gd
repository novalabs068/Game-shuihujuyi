class_name BattleView
extends Control
## 横屏战斗画面：只负责显示和接收点击，规则全在 BattleModel。
## 地区的水墨画做背景，两阵人马左右对峙；出手时有刀光、命中火花等像素特效（pixelfx）。
## 操作：点敌人换目标（默认选好），点下方行动按钮出手。

## 撤退（算没打赢）
signal exit_requested
signal retry_requested
## 结算面板上点「继续」
signal finished(won: bool)

const AUTO_ACTION := -1
## 我方三个站位（左上角坐标）：1 号在前排偏上、2 号在后排、3 号在最前排偏下；敌方左右镜像
const SLOTS: Array[Vector2] = [Vector2(196, 70), Vector2(18, 176), Vector2(330, 292)]
## 特效放大倍数（pixelfx 按 24×38 的小人画的，我们的人物大得多）
const FX_SCALE := 2.6
const BOTTOM_BAR_HEIGHT := 150.0
const ENEMY_THINK_DELAY := 0.2

var stage: StageData
var team: Array[UnitData] = []
var hero_level := 1
## 战场背景（地区的水墨画）；为空就用深色底
var background: Texture2D
var model: BattleModel

signal _action_chosen(action: int)

var _cards: Dictionary[BattleUnit, UnitCard] = {}
var _target_marker: Label
var _target: BattleUnit
var _awaiting_input := false
var _auto := false

var _round_label: Label
var _order_box: HBoxContainer
var _banner: Label
var _log_label: Label
var _log_lines := PackedStringArray()
var _actor_bust: TextureRect
var _actor_label: Label
var _hint_label: Label
var _attack_button: Button
var _skill_button: Button
var _guard_button: Button
var _combo_button: Button


func _ready() -> void:
	model = BattleModel.new(stage, team, hero_level, GameState.combos())
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if background != null:
		var scene := TextureRect.new()
		scene.texture = background
		scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		# 压暗一些，人物和数字才看得清
		scene.modulate = Color(0.62, 0.6, 0.58)
		scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(scene)
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_top_bar()
	_build_center()
	_build_bottom_bar()
	for u in model.units:
		var card := UnitCard.new()
		add_child(card)
		card.setup(u)
		card.tapped.connect(_on_card_tapped)
		_cards[u] = card
	_target = model.alive(BattleUnit.Side.ENEMY)[0]
	_target_marker = UiKit.label("▶", 40, UiKit.DAMAGE)
	_target_marker.add_theme_constant_override("outline_size", 8)
	_target_marker.add_theme_color_override("font_outline_color", Color.BLACK)
	_target_marker.z_index = 5
	_target_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_target_marker)
	var bob := _target_marker.create_tween().set_loops()
	bob.tween_property(_target_marker, "modulate:a", 0.45, 0.45)
	bob.tween_property(_target_marker, "modulate:a", 1.0, 0.45)
	resized.connect(_layout)
	_layout()
	_refresh()
	_run()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# --- 主循环 ---

func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	while model.result == BattleModel.Result.ONGOING:
		if not is_inside_tree():
			return
		await _play(model.start_next_turn())
		var actor := model.current
		if actor == null:
			continue
		var events: Array[Dictionary]
		if actor.side == BattleUnit.Side.PLAYER and not _auto:
			_awaiting_input = true
			_refresh()
			var choice: int = await _action_chosen
			_awaiting_input = false
			if choice == AUTO_ACTION:
				events = model.act_ai()
			else:
				events = model.act(choice as BattleModel.Action, _target)
		else:
			_refresh()
			await get_tree().create_timer(ENEMY_THINK_DELAY).timeout
			events = model.act_ai()
		await _play(events)
		_cards[actor].set_active(false)
	_refresh()
	_show_result()


func _play(events: Array[Dictionary]) -> void:
	for e in events:
		if not is_inside_tree():
			return
		var kind: String = e["kind"]
		var unit: BattleUnit = e["unit"]
		var popup: String = e["popup"]
		var log_text: String = e["log"]
		var big: bool = e["big"]
		var source: BattleUnit = e["source"]
		var card := _cards[unit]
		if log_text != "":
			_add_log(log_text)
		var wait := 0.08
		match kind:
			"turn":
				_banner.text = ""
				card.set_active(true)
				_update_turn_order()
			"action":
				_banner.text = "%s · %s" % [unit.display_name(), popup]
				wait = 0.0
			"skill":
				_banner.text = ""
				await _skill_cutin(unit, popup)
				wait = 0.0
			"combo":
				_banner.text = ""
				await _combo_cutin(unit, source, popup)
				wait = 0.0
			"banner":
				_banner.text = "「%s」" % popup
				card.popup(popup, UiKit.GOLD, true)
				_shake_screen(10.0)
				wait = 0.6
			"damage":
				var from_left := source == null or source.side == BattleUnit.Side.PLAYER
				var fx: String = e.get("fx", "")
				if source != null and source != unit:
					await _cards[source].lunge(card.position)
					if fx == "":
						FxSprite.spawn(self, "sword_slash", card.hit_point(), FX_SCALE, not from_left)
				# 群攻技能各有各的特效：爆炸、震地落在脚下，重劈对着胸口
				if fx == "heavy_cleave":
					FxSprite.spawn(self, fx, card.hit_point(), FX_SCALE * 0.8, not from_left)
				elif fx != "":
					FxSprite.spawn(self, fx, card.feet_point(), 1.1, not from_left)
					_shake_screen(6.0)
				FxSprite.spawn(self, "crit_hit" if big else "hit_spark", card.hit_point(), FX_SCALE * (0.8 if big else 1.0), not from_left)
				card.flash()
				card.shake()
				card.popup(popup, UiKit.DAMAGE, big)
				if big:
					_shake_screen(10.0)
				wait = 0.16
			"heal":
				FxSprite.spawn(self, "heal", card.feet_point(), FX_SCALE)
				card.popup(popup, UiKit.HEAL)
			"death":
				FxSprite.spawn(self, "poof", card.hit_point() + Vector2(0, 40), FX_SCALE)
				card.popup(popup, UiKit.TEXT_DIM)
				wait = 0.25
			_:
				# 加速、增攻、护盾这类增益：脚下升起一道光
				if popup in ["加速", "增攻"] or popup.begins_with("护盾"):
					FxSprite.spawn(self, "blessing", card.feet_point(), FX_SCALE * 0.9, false, 0)
				if popup != "":
					card.popup(popup, UiKit.TEXT)
					wait = 0.15
		_refresh()
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout


## 放技能：一条色带从出手者那一侧滑进来，带着半身像和技能名。
func _skill_cutin(unit: BattleUnit, skill_name: String) -> void:
	var from_left := unit.side == BattleUnit.Side.PLAYER
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.78), UiKit.ACCENT if from_left else UiKit.DAMAGE, 3, 0))
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.z_index = 20
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	band.add_child(row)
	var bust := UiKit.unit_picture(unit.data, 150, not from_left)
	var title := UiKit.label(skill_name, 52, UiKit.GOLD)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	for child: Control in ([bust, title] if from_left else [title, bust]):
		row.add_child(child)
	add_child(band)
	band.size = Vector2(size.x, 170)
	var y := size.y * 0.32
	band.position = Vector2(-size.x if from_left else size.x, y)
	var t := create_tween()
	t.tween_property(band, "position:x", 0.0, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_interval(0.38)
	t.tween_property(band, "modulate:a", 0.0, 0.12)
	await t.finished
	band.queue_free()


## 组合技：画面变暗，两人的立绘从左右冲进来，中间打出组合技名。
func _combo_cutin(a: BattleUnit, b: BattleUnit, combo_name: String) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 30
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var band := ColorRect.new()
	band.color = Color(0.62, 0.12, 0.09, 0.92)
	band.size = Vector2(size.x, 130)
	band.position = Vector2(0, size.y * 0.5 - 65)
	band.scale = Vector2(0, 1)
	layer.add_child(band)

	var fig_h := size.y * 0.92
	var left := _portrait(a, fig_h, false)
	var right := _portrait(b, fig_h, true)
	layer.add_child(left)
	layer.add_child(right)
	left.position = Vector2(-left.size.x, size.y - fig_h)
	right.position = Vector2(size.x, size.y - fig_h)

	var title := UiKit.label("「%s」" % combo_name, 64, UiKit.GOLD)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(size.x, 90)
	title.position = Vector2(0, size.y * 0.5 - 45)
	title.pivot_offset = title.size / 2
	title.scale = Vector2(2.2, 2.2)
	title.modulate.a = 0.0
	layer.add_child(title)

	var t := create_tween().set_parallel()
	t.tween_property(dim, "color:a", 0.72, 0.18)
	t.tween_property(left, "position:x", size.x * 0.02, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(right, "position:x", size.x * 0.98 - right.size.x, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(band, "scale:x", 1.0, 0.2).set_delay(0.12)
	t.tween_property(title, "scale", Vector2.ONE, 0.18).set_delay(0.24).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_property(title, "modulate:a", 1.0, 0.12).set_delay(0.24)
	await t.finished
	_shake_screen(14.0)
	await get_tree().create_timer(0.75).timeout
	var out := create_tween()
	out.tween_property(layer, "modulate:a", 0.0, 0.18)
	await out.finished
	layer.queue_free()


func _portrait(unit: BattleUnit, height: float, flip: bool) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = unit.data.portrait
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.flip_h = flip
	var aspect := 0.75
	if unit.data.portrait != null:
		aspect = float(unit.data.portrait.get_width()) / unit.data.portrait.get_height()
	rect.size = Vector2(height * aspect, height)
	return rect


func _shake_screen(strength: float) -> void:
	var t := create_tween()
	for i in 6:
		var k := strength * (1.0 - i / 6.0)
		t.tween_property(self, "position", Vector2(randf_range(-k, k), randf_range(-k, k)), 0.03)
	t.tween_property(self, "position", Vector2.ZERO, 0.03)


# --- 输入 ---

func _choose(action: int) -> void:
	if _awaiting_input:
		_action_chosen.emit(action)


func _on_card_tapped(card: UnitCard) -> void:
	var u := card.unit
	if not u.is_alive():
		return
	if u.side == BattleUnit.Side.ENEMY:
		_target = u
		_refresh()
	elif u.data.skill != null:
		_hint_label.text = "%s「%s」：%s" % [u.display_name(), u.data.skill.display_name, u.data.skill.description]


func _on_auto_toggled(on: bool) -> void:
	_auto = on
	if on:
		_choose(AUTO_ACTION)


# --- 刷新 ---

func _refresh() -> void:
	if _target == null or not _target.is_alive():
		var enemies := model.alive(BattleUnit.Side.ENEMY)
		_target = enemies[0] if not enemies.is_empty() else null
	for u in _cards:
		_cards[u].set_targeted(u == _target)
		_cards[u].set_intent(_intent_text(u), _intent_danger(u))
	_target_marker.visible = _target != null
	if _target != null:
		var tc := _cards[_target]
		# 敌人都在右边，箭头放在卡片左侧、指向它
		_target_marker.position = tc.home_position + Vector2(-34, UnitCard.FIGURE_HEIGHT * 0.45)
	_round_label.text = "第 %d 回合" % model.round_number()

	var actor := model.current
	var input := _awaiting_input and actor != null
	_actor_bust.texture = null
	if actor != null:
		_actor_bust.texture = actor.data.bust if actor.data.bust != null else actor.data.map_sprite
		_actor_bust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if actor.data.bust == null else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	_actor_bust.flip_h = actor != null and actor.side == BattleUnit.Side.ENEMY
	for b in [_attack_button, _skill_button, _guard_button, _combo_button]:
		(b as Button).disabled = not input
	if actor == null or actor.side != BattleUnit.Side.PLAYER:
		_actor_label.text = "%s 出手…" % actor.display_name() if actor != null else ""
		_hint_label.text = ("「%s」%s" % [actor.data.skill.display_name, actor.data.skill.description]) if actor != null and actor.data.skill != null else ""
		_skill_button.text = "技能"
		_combo_button.text = "组合技"
		return

	_actor_label.text = "轮到：%s　→ 目标：%s" % [actor.display_name(), _target.display_name() if _target != null else "无"]
	var skill := actor.data.skill
	if not input:
		_hint_label.text = "「%s」%s" % [skill.display_name, skill.description]
	if actor.skill_ready():
		_skill_button.text = "技能\n%s" % skill.display_name
		if input:
			_hint_label.text = "点敌人可换目标。「%s」%s" % [skill.display_name, skill.description]
	else:
		_skill_button.text = "技能\n冷却 %d" % actor.skill_cooldown
		_skill_button.disabled = true
		if input:
			_hint_label.text = "普攻 +%d 怒气；防御减伤一半，+%d 怒气。被敌人技能瞄准时记得防御。" % [BattleModel.RAGE_ON_ATTACK, BattleModel.RAGE_ON_GUARD]
	var combo := model.available_combo(actor)
	_combo_button.disabled = not input or combo == null
	_combo_button.text = "组合技\n%s" % combo.display_name if combo != null else "组合技"
	var lit := combo != null and input
	_combo_button.add_theme_stylebox_override("normal", UiKit.box(UiKit.ACCENT.darkened(0.2), UiKit.GOLD, 4) if lit else UiKit.box(UiKit.PANEL_LIGHT, UiKit.SILVER, 2))


func _intent_text(u: BattleUnit) -> String:
	if not u.is_alive():
		return ""
	if u.side == BattleUnit.Side.ENEMY:
		if u.stun_turns > 0:
			return "下一步：眩晕中，动不了"
		var t := model.intent_target_of(u)
		if t == null:
			return ""
		if u.intent_skill and u.data.skill != null:
			return "下一步：%s → %s！" % [u.data.skill.display_name, t.display_name()]
		return "下一步：普攻 → %s" % t.display_name()
	for e in model.alive(BattleUnit.Side.ENEMY):
		if e.intent_skill and e.stun_turns == 0 and model.intent_target_of(e) == u:
			return "被%s的「%s」瞄准！" % [e.display_name(), e.data.skill.display_name]
	return ""


func _intent_danger(u: BattleUnit) -> bool:
	if u.side == BattleUnit.Side.PLAYER:
		return model.is_threatened(u)
	return u.intent_skill and u.stun_turns == 0


func _update_turn_order() -> void:
	for child in _order_box.get_children():
		child.queue_free()
	var first := true
	for u in model.turn_order_preview():
		var chip := PanelContainer.new()
		var color := UiKit.ACCENT.darkened(0.35) if u.side == BattleUnit.Side.PLAYER else UiKit.ENEMY.darkened(0.2)
		chip.add_theme_stylebox_override("panel", UiKit.box(color, UiKit.TEXT if first else color, 3 if first else 1, 6))
		var chip_row := HBoxContainer.new()
		chip_row.add_theme_constant_override("separation", 4)
		chip.add_child(chip_row)
		chip_row.add_child(UiKit.unit_picture(u.data, 40 if first else 32, u.side == BattleUnit.Side.ENEMY, true))
		chip_row.add_child(UiKit.label(u.display_name(), 18 if first else 15))
		_order_box.add_child(chip)
		first = false


func _add_log(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 5:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)


func _layout() -> void:
	for u in _cards:
		var card := _cards[u]
		var p := SLOTS[u.slot]
		if u.side == BattleUnit.Side.PLAYER:
			card.place(p)
		else:
			card.place(Vector2(size.x - p.x - UnitCard.CARD_SIZE.x, p.y))


# --- 搭界面 ---

func _build_top_bar() -> void:
	var back := ColorRect.new()
	back.color = Color(0.06, 0.05, 0.05, 0.7)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	back.offset_bottom = 66
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_right = -24
	bar.offset_top = 14
	bar.offset_bottom = 62

	_round_label = UiKit.label("", 22, UiKit.TEXT_DIM)
	_round_label.custom_minimum_size.x = 130
	bar.add_child(_round_label)
	var order_title := UiKit.label("出手顺序", 17, UiKit.TEXT_DIM)
	bar.add_child(order_title)
	_order_box = HBoxContainer.new()
	_order_box.add_theme_constant_override("separation", 6)
	_order_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_order_box)

	var auto := CheckButton.new()
	auto.text = "自动"
	auto.toggled.connect(_on_auto_toggled)
	bar.add_child(auto)
	var fast := CheckButton.new()
	fast.text = "2倍速"
	fast.toggled.connect(func(on: bool) -> void: Engine.time_scale = 2.0 if on else 1.0)
	bar.add_child(fast)
	var quit_button := UiKit.button("撤退", Vector2(90, 44), 20)
	quit_button.pressed.connect(func() -> void: exit_requested.emit())
	bar.add_child(quit_button)


func _build_center() -> void:
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 12)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -180
	center.offset_right = 180
	center.offset_top = -230
	center.offset_bottom = 60
	center.alignment = BoxContainer.ALIGNMENT_CENTER

	_banner = UiKit.label("", 30, UiKit.GOLD)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	center.add_child(_banner)
	_log_label = UiKit.label("", 16, UiKit.TEXT_DIM)
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_log_label)


func _build_bottom_bar() -> void:
	var panel := PanelContainer.new()
	# 半透明的墨色底、上沿一道金线，透出后面的战场
	var panel_style := UiKit.box(Color(0.07, 0.06, 0.05, 0.86), UiKit.GOLD, 0, 0)
	panel_style.border_width_top = 2
	panel_style.content_margin_left = 24
	panel_style.content_margin_right = 24
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -BOTTOM_BAR_HEIGHT

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	_actor_bust = UiKit.picture(null, 128)
	row.add_child(_actor_bust)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	_actor_label = UiKit.label("", 24)
	_actor_label.clip_text = true
	info.add_child(_actor_label)
	_hint_label = UiKit.label("", 17, UiKit.TEXT_DIM)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size.x = 200
	info.add_child(_hint_label)

	var button_size := Vector2(140, 120)
	_attack_button = UiKit.button("普攻", button_size, 26)
	_skill_button = UiKit.button("技能", button_size, 22)
	_guard_button = UiKit.button("防御", button_size, 26)
	_combo_button = UiKit.button("组合技", Vector2(170, 120), 22)
	_attack_button.pressed.connect(_choose.bind(BattleModel.Action.ATTACK))
	_skill_button.pressed.connect(_choose.bind(BattleModel.Action.SKILL))
	_guard_button.pressed.connect(_choose.bind(BattleModel.Action.GUARD))
	_combo_button.pressed.connect(_choose.bind(BattleModel.Action.COMBO))
	for b in [_attack_button, _skill_button, _guard_button, _combo_button]:
		row.add_child(b)


# --- 结算 ---

func _show_result() -> void:
	var won := model.result == BattleModel.Result.WIN
	_banner.text = ""
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.GOLD if won else UiKit.ENEMY, 3, 16))
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var title := UiKit.label("胜利！" if won else "战败……", 40, UiKit.GOLD if won else UiKit.DAMAGE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var conditions := model.star_conditions()
	var stars := UiKit.label("★".repeat(model.stars()) + "☆".repeat(3 - model.stars()), 44, UiKit.GOLD)
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stars)
	var texts := ["获胜", "无人倒下", "%d 回合内获胜（用了 %d 回合）" % [stage.star_round_limit, model.round_number()]]
	for i in texts.size():
		v.add_child(UiKit.label(("● " if conditions[i] else "○ ") + texts[i], 20, UiKit.TEXT if conditions[i] else UiKit.TEXT_DIM))
	if won:
		var r := Encounters.rewards(model)
		var gain := UiKit.label("获得：经验 +%d　银两 +%d" % [r["exp"], r["silver"]], 22, UiKit.GOLD)
		gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(gain)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	v.add_child(buttons)
	var retry := UiKit.button("再打一次", Vector2(180, 64))
	retry.pressed.connect(func() -> void: retry_requested.emit())
	buttons.add_child(retry)
	var back := UiKit.button("继续", Vector2(180, 64))
	back.pressed.connect(func() -> void: finished.emit(won))
	buttons.add_child(back)
	# 面板要等内容撑开尺寸后再居中
	await get_tree().process_frame
	panel.position = (size - panel.size) / 2
