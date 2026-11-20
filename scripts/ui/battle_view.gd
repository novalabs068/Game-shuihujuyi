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
## 我方三个站位：脚底的位置和远近（后排画小一点），沿一条斜线排开——2 号在最后、1 号居中、3 号最前；
## 敌方左右镜像。越靠下越近，画在上层
const SLOTS: Array[Vector2] = [Vector2(290, 420), Vector2(150, 340), Vector2(430, 500)]
const SLOT_DEPTH: Array[float] = [0.93, 0.85, 1.0]
## 画的层次：后排 1、中间 2、前排 3；天气 4、前景草 5、目标箭头 6，都在背景之上
const SLOT_LAYER: Array[int] = [2, 1, 3]
## 顶栏和底栏在天气、前景之上
const BAR_LAYER := 7
## 特效放大倍数（pixelfx 按 24×38 的小人画的，我们的人物大得多）
const FX_SCALE := 2.6
## 远程普攻：不冲上去，原地出手，箭或石子飞过去
const RANGED_STYLES: Array[StringName] = [&"arrow", &"throw"]
## 右下角圆钮：中心离屏幕右边、下边的距离和直径
const ATTACK_SPOT := Vector3(110, 112, 124)
const SKILL_SPOT := Vector3(252, 72, 86)
const GUARD_SPOT := Vector3(236, 206, 72)
const COMBO_SPOT := Vector3(112, 258, 64)
## 出手顺序头像的直径：当前出手的、后面排着的
const BEAD_BIG := 54.0
const BEAD_SMALL := 40.0
const INK := Color("1c1714")
## 暴击数字的朱红
const CRIT_RED := Color("ff3b24")
## 放绝招时招式名下面那一笔的颜色
const STROKE_RED := Color("a8231a")
const PAPER := Color("ecdcbc")
const ENEMY_RED := Color("b0261e")
const ALLY_BLUE := Color("4a6a9a")
const ENEMY_THINK_DELAY := 0.2

var stage: StageData
var team: Array[UnitData] = []
var hero_level := 1
## 战场背景（地区的水墨画）；为空就用深色底
var background: Texture2D
## 战场在哪儿（背景名），决定飘什么天气，见 BattleWeather
var place := ""
## 开战时我方每人剩的气血（id → 0～1，见 Vitality）；空的就是满血
var start_hp: Dictionary = {}
var model: BattleModel

signal _action_chosen(action: int)

var _cards: Dictionary[BattleUnit, UnitCard] = {}
var _target_marker: Label
var _target: BattleUnit
var _awaiting_input := false
var _auto := false
var _fast := false

var _round_label: Label
var _order_box: HBoxContainer
var _banner: Label
var _log_panel: PanelContainer
var _log_label: Label
var _log_lines := PackedStringArray()
var _auto_button: Button
var _fast_button: Button
var _circle_material: ShaderMaterial
var _actor_bust: TextureRect
var _actor_label: Label
var _target_label: Label
var _hint_label: Label
var _intent_label: Label
var _attack_button: Button
var _skill_button: Button
var _guard_button: Button
var _combo_button: Button
var _skill_sub: Label
var _combo_sub: Label


func _ready() -> void:
	model = BattleModel.new(stage, team, hero_level, GameState.combos())
	Vitality.apply_start(model, start_hp)
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
	# 下半部压暗：远处亮、脚下暗，人站得住
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.03, 0.02, 0.02, 0.55)])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(0, 1)
	shade.texture = grad_tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var weather := BattleWeather.make(place, Vector2(1280, 720))
	if weather != null:
		weather.z_index = 4
		add_child(weather)
	_build_top_bar()
	_build_center()
	_build_bottom_bar()
	for u in model.units:
		var card := UnitCard.new()
		add_child(card)
		card.setup(u)
		card.tapped.connect(_on_card_tapped)
		card.set_depth(SLOT_DEPTH[u.slot])
		# 前排盖住后排
		card.z_index = SLOT_LAYER[u.slot]
		_cards[u] = card
	# 最前面一层虚化的草，底栏上方
	var fore := TextureRect.new()
	fore.texture = load("res://art/ui/battle_foreground.png")
	fore.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fore.modulate = Color(1, 1, 1, 0.85)
	fore.z_index = 5
	add_child(fore)
	fore.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	fore.offset_top = -230
	fore.offset_bottom = 0
	fore.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_target = model.alive(BattleUnit.Side.ENEMY)[0]
	_target_marker = UiKit.label("▶", 40, UiKit.DAMAGE)
	_target_marker.add_theme_constant_override("outline_size", 8)
	_target_marker.add_theme_color_override("font_outline_color", Color.BLACK)
	_target_marker.z_index = 6
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
	if model.result == BattleModel.Result.WIN:
		for card: UnitCard in _cards.values():
			if card.unit.side == BattleUnit.Side.PLAYER:
				card.cheer()
		await get_tree().create_timer(0.7).timeout
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
					var style := source.data.attack_style
					if style in RANGED_STYLES:
						await _cards[source].shoot()
						await Projectile.fly(self, _cards[source].muzzle_point(), card.hit_point(), style)
					else:
						await _cards[source].lunge(card.position)
					if fx == "":
						_style_hit_fx(style, card, from_left)
				# 群攻技能各有各的特效：爆炸、震地落在脚下，重劈对着胸口
				if fx == "heavy_cleave":
					FxSprite.spawn(self, fx, card.hit_point(), FX_SCALE * 0.8, not from_left)
				elif fx != "":
					FxSprite.spawn(self, fx, card.feet_point(), 1.1, not from_left)
					_shake_screen(6.0)
				FxSprite.spawn(self, "crit_hit" if big else "hit_spark", card.hit_point(), FX_SCALE * (0.8 if big else 1.0), not from_left)
				card.flash()
				card.shake()
				_ink_splash(card.hit_point(), from_left, big)
				card.popup(popup, CRIT_RED if big else UiKit.DAMAGE, big)
				if big:
					_shake_screen(10.0)
					_punch_zoom(card.hit_point())
				await _hitstop(0.1 if big else 0.045)
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
## 放绝招：画面压暗，版画全身像从出手那一侧滑进来，一笔浓墨刷开，招式名一个字一个字写出来。
func _skill_cutin(unit: BattleUnit, skill_name: String) -> void:
	var from_left := unit.side == BattleUnit.Side.PLAYER
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 30
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.0)
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var fig_h := size.y * 0.96
	var fig := _portrait(unit, fig_h, not from_left)
	layer.add_child(fig)
	var fig_to := size.x * 0.03 if from_left else size.x * 0.97 - fig.size.x
	fig.position = Vector2(-fig.size.x if from_left else size.x, size.y - fig_h)

	var stroke := _brush_stroke(Vector2(size.x * 0.62, 150), not from_left)
	stroke.position = Vector2(size.x * (0.34 if from_left else 0.04), size.y * 0.42)
	layer.add_child(stroke)
	var title := UiKit.outlined(skill_name, 76, Color("f4e8cc"))
	title.add_theme_constant_override("outline_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = stroke.size
	title.position = stroke.position + Vector2(0, (stroke.size.y - 110) / 2)
	title.visible_ratio = 0.0
	layer.add_child(title)

	var t := create_tween().set_parallel()
	t.tween_property(dim, "color:a", 0.6, 0.12)
	t.tween_property(fig, "position:x", fig_to, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(stroke, "scale:x", 1.0, 0.22).set_delay(0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(title, "visible_ratio", 1.0, 0.3).set_delay(0.16)
	await t.finished
	await get_tree().create_timer(0.38).timeout
	var out := create_tween()
	out.tween_property(layer, "modulate:a", 0.0, 0.14)
	await out.finished
	layer.queue_free()


## 一笔横向的朱红笔触（art/ui/brush_stroke.png 是白的，这里染色），从起笔那头往外刷开：scale.x 从 0 到 1。
func _brush_stroke(stroke_size: Vector2, flip: bool, color := STROKE_RED) -> TextureRect:
	var stroke := TextureRect.new()
	stroke.texture = load("res://art/ui/brush_stroke.png")
	stroke.modulate = color
	stroke.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stroke.stretch_mode = TextureRect.STRETCH_SCALE
	stroke.flip_h = flip
	stroke.size = stroke_size
	stroke.pivot_offset = Vector2(stroke_size.x if flip else 0.0, stroke_size.y / 2)
	stroke.scale = Vector2(0, 1)
	stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return stroke


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
	var band := _brush_stroke(Vector2(size.x * 0.8, 170), false)
	band.position = Vector2(size.x * 0.1, size.y * 0.5 - 85)
	layer.add_child(band)

	var fig_h := size.y * 0.92
	var left := _portrait(a, fig_h, false)
	var right := _portrait(b, fig_h, true)
	layer.add_child(left)
	layer.add_child(right)
	left.position = Vector2(-left.size.x, size.y - fig_h)
	right.position = Vector2(size.x, size.y - fig_h)

	var title := UiKit.outlined("「%s」" % combo_name, 68, Color("f4e8cc"))
	title.add_theme_constant_override("outline_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(size.x, 90)
	title.position = Vector2(0, size.y * 0.5 - 45)
	title.visible_ratio = 0.0
	layer.add_child(title)

	var t := create_tween().set_parallel()
	t.tween_property(dim, "color:a", 0.72, 0.18)
	t.tween_property(left, "position:x", size.x * 0.02, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(right, "position:x", size.x * 0.98 - right.size.x, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(band, "scale:x", 1.0, 0.24).set_delay(0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(title, "visible_ratio", 1.0, 0.32).set_delay(0.2)
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
	if rect.texture == null:
		# 没有版画立绘的（少数敌人）：用放大的像素小人
		rect.texture = unit.data.battle_sprite if unit.data.battle_sprite != null else unit.data.map_sprite
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.flip_h = flip
	var aspect := 0.75
	if rect.texture != null:
		aspect = float(rect.texture.get_width()) / rect.texture.get_height()
	rect.size = Vector2(height * aspect, height)
	return rect


## 普攻按兵器出不同的命中特效：刀光、枪芒、重劈、拳劲、爪痕；远程的只有命中火花。
func _style_hit_fx(style: StringName, card: UnitCard, from_left: bool) -> void:
	match style:
		&"thrust":
			FxSprite.spawn(self, "thrust", card.hit_point(), FX_SCALE * 0.9, not from_left)
		&"heavy":
			FxSprite.spawn(self, "heavy_cleave", card.hit_point(), FX_SCALE * 0.7, not from_left)
			_shake_screen(5.0)
		&"fist":
			FxSprite.spawn(self, "blunt_hit", card.hit_point(), FX_SCALE * 0.9, not from_left)
		&"claw":
			FxSprite.spawn(self, "claw_swipe", card.hit_point(), FX_SCALE, not from_left)
		&"arrow", &"throw":
			pass
		_:
			FxSprite.spawn(self, "sword_slash", card.hit_point(), FX_SCALE, not from_left)


## 命中顿帧：时间几乎停一下再走（按真实时间算，2 倍速下也一样长）。
func _hitstop(seconds: float) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	# 顿帧期间战斗结束退出了，就别再动全局速度（_exit_tree 已经复原）
	if is_inside_tree():
		Engine.time_scale = 2.0 if _fast else 1.0


## 命中处溅开一把墨点，往挨打的方向飞。
func _ink_splash(at: Vector2, from_left: bool, big: bool) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.z_index = 14
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 22 if big else 12
	p.lifetime = 0.55
	p.direction = Vector2(1 if from_left else -1, -0.4)
	p.spread = 55.0
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 420.0 if big else 320.0
	p.gravity = Vector2(0, 900)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0 if big else 5.0
	p.color = Color(0.08, 0.06, 0.05, 0.9)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## 暴击：镜头往命中处轻轻推一下再回来。
func _punch_zoom(at: Vector2) -> void:
	pivot_offset = at
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.04, 1.04), 0.06).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2.ONE, 0.22).set_ease(Tween.EASE_IN_OUT)


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
		_hint_label.text = "%s「%s」%s" % [u.display_name(), u.data.skill.display_name, u.data.skill.description]


func _on_auto_toggled(on: bool) -> void:
	_auto = on
	_set_lit(_auto_button, on)
	if on:
		_choose(AUTO_ACTION)


# --- 刷新 ---

func _refresh() -> void:
	if _target == null or not _target.is_alive():
		var enemies := model.alive(BattleUnit.Side.ENEMY)
		_target = enemies[0] if not enemies.is_empty() else null
	for u in _cards:
		_cards[u].set_targeted(u == _target)
		_cards[u].set_intent(_intent_mark(u), _intent_danger(u))
	_target_marker.visible = false
	_round_label.text = "第%s回合" % UiKit.cn_number(model.round_number())

	var actor := model.current
	var input := _awaiting_input and actor != null
	var player := actor != null and actor.side == BattleUnit.Side.PLAYER
	# 左下：当前出手的人探出来
	_actor_bust.visible = actor != null
	if actor != null:
		var art := actor.data.bust
		var pixel := art == null
		if pixel:
			art = actor.data.battle_sprite if actor.data.battle_sprite != null else actor.data.map_sprite
		_actor_bust.texture = art
		_actor_bust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel else CanvasItem.TEXTURE_FILTER_PARENT_NODE
		_actor_label.text = actor.display_name()
		_actor_label.add_theme_color_override("font_color", PAPER if player else Color("f0907c"))
		_target_label.text = ("→ %s" % _target.display_name()) if player and _target != null else "出手…"
		var skill := actor.data.skill
		_hint_label.text = ""
		if skill != null:
			_hint_label.text = "「%s」%s" % [skill.display_name, skill.description]
			if player and not actor.skill_ready():
				_hint_label.text = "「%s」冷却中，还要 %d 回合。普攻、防御能攒怒气" % [skill.display_name, actor.skill_cooldown]
	else:
		_actor_label.text = ""
		_target_label.text = ""
		_hint_label.text = ""
	# 选中的敌人下一步要干什么
	_intent_label.text = ""
	if player and _target != null:
		_intent_label.text = "%s %s" % [_target.display_name(), _intent_text(_target)]

	# 右下：圆钮
	for b: Button in [_attack_button, _skill_button, _guard_button, _combo_button]:
		b.disabled = not input
	var skill_name := actor.data.skill.display_name if player and actor.data.skill != null else ""
	_skill_button.text = skill_name.left(1) if skill_name != "" else "技"
	_skill_sub.text = skill_name if skill_name != "" else "绝招"
	if player and actor.data.skill != null and not actor.skill_ready():
		_skill_button.disabled = true
		_skill_sub.text = "冷却 %d" % actor.skill_cooldown
	var combo := model.available_combo(actor) if player else null
	_combo_button.disabled = not input or combo == null
	_combo_sub.text = combo.display_name if combo != null else "组合技"
	_set_lit(_combo_button, combo != null and input)


## 头顶小圆标的字：敌人普攻「攻」、要放绝招「技」、眩晕「晕」；好汉被敌人绝招瞄准「危」。
func _intent_mark(u: BattleUnit) -> String:
	if not u.is_alive():
		return ""
	if u.side == BattleUnit.Side.ENEMY:
		if u.stun_turns > 0:
			return "晕"
		if model.intent_target_of(u) == null:
			return ""
		return "技" if u.intent_skill and u.data.skill != null else "攻"
	return "危" if model.is_threatened(u) else ""


func _intent_text(u: BattleUnit) -> String:
	if not u.is_alive():
		return ""
	if u.side == BattleUnit.Side.ENEMY:
		if u.stun_turns > 0:
			return "眩晕中，下一步动不了"
		var t := model.intent_target_of(u)
		if t == null:
			return ""
		if u.intent_skill and u.data.skill != null:
			return "下一步：「%s」→ %s" % [u.data.skill.display_name, t.display_name()]
		return "下一步：普攻 → %s" % t.display_name()
	for e in model.alive(BattleUnit.Side.ENEMY):
		if e.intent_skill and e.stun_turns == 0 and model.intent_target_of(e) == u:
			return "被%s的「%s」瞄准" % [e.display_name(), e.data.skill.display_name]
	return ""


func _intent_danger(u: BattleUnit) -> bool:
	if u.side == BattleUnit.Side.PLAYER:
		return model.is_threatened(u)
	return u.intent_skill and u.stun_turns == 0


## 出手顺序：一串圆头像，当前出手的最大、金圈；好汉蓝圈，敌人红圈。
func _update_turn_order() -> void:
	for child in _order_box.get_children():
		child.queue_free()
	var first := true
	for u in model.turn_order_preview():
		_order_box.add_child(_bead(u, first))
		first = false


func _bead(u: BattleUnit, current: bool) -> Control:
	var d := BEAD_BIG if current else BEAD_SMALL
	var ring := PanelContainer.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color := UiKit.GOLD if current else (ALLY_BLUE if u.side == BattleUnit.Side.PLAYER else ENEMY_RED)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(d / 2) + 3)
	style.set_content_margin_all(3)
	ring.add_theme_stylebox_override("panel", style)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var face := TextureRect.new()
	var art := u.data.face if u.data.face != null else u.data.bust
	if art == null:
		art = u.data.battle_sprite if u.data.battle_sprite != null else u.data.map_sprite
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.texture = art
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.custom_minimum_size = Vector2(d, d)
	face.flip_h = u.side == BattleUnit.Side.ENEMY
	face.material = _circle_material
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_child(face)
	return ring


func _add_log(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 10:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)


func _layout() -> void:
	for u in _cards:
		var card := _cards[u]
		var feet := SLOTS[u.slot]
		var p := Vector2(feet.x - UnitCard.CARD_SIZE.x / 2, feet.y - UnitCard.FEET.y)
		if u.side == BattleUnit.Side.PLAYER:
			card.place(p)
		else:
			card.place(Vector2(size.x - p.x - UnitCard.CARD_SIZE.x, p.y))


# --- 搭界面 ---

## 顶上：左「第几回合」，中间一串出手顺序头像串在一道墨线上，右边「自」「速」「记」「退」四个圆钮。
func _build_top_bar() -> void:
	_circle_material = ShaderMaterial.new()
	_circle_material.shader = load("res://scripts/ui/shaders/circle_mask.gdshader")
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(0.04, 0.03, 0.02, 0.62), Color(0.04, 0.03, 0.02, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.z_index = BAR_LAYER
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shade.offset_bottom = 96

	_round_label = UiKit.outlined("", 28, PAPER)
	_round_label.z_index = BAR_LAYER
	_round_label.position = Vector2(24, 16)
	add_child(_round_label)

	var line := ColorRect.new()
	line.color = Color(INK, 0.9)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.z_index = BAR_LAYER
	line.position = Vector2(196, 42)
	line.size = Vector2(700, 4)
	add_child(line)
	_order_box = HBoxContainer.new()
	_order_box.add_theme_constant_override("separation", 22)
	_order_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_order_box.z_index = BAR_LAYER
	_order_box.position = Vector2(206, 44 - BEAD_BIG / 2 - 3)
	_order_box.custom_minimum_size.y = BEAD_BIG + 6
	add_child(_order_box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.z_index = BAR_LAYER
	add_child(buttons)
	buttons.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	buttons.offset_left = -230
	buttons.offset_right = -18
	buttons.offset_top = 18
	_auto_button = _small_round("自")
	_auto_button.pressed.connect(func() -> void: _on_auto_toggled(not _auto))
	buttons.add_child(_auto_button)
	_fast_button = _small_round("速")
	_fast_button.pressed.connect(func() -> void: _set_fast(not _fast))
	buttons.add_child(_fast_button)
	var log_button := _small_round("记")
	log_button.pressed.connect(func() -> void: _log_panel.visible = not _log_panel.visible)
	buttons.add_child(log_button)
	var quit_button := _small_round("退")
	quit_button.pressed.connect(func() -> void: exit_requested.emit())
	buttons.add_child(quit_button)
	# 记住上一次选的速度
	_set_fast(Prefs.get_value("battle", "fast", false))

	# 「记」：最近的战斗记录，平时收着
	_log_panel = PanelContainer.new()
	_log_panel.add_theme_stylebox_override("panel", UiKit.box(Color(INK, 0.88), PAPER, 1, 6))
	_log_panel.z_index = BAR_LAYER
	_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_panel.visible = false
	add_child(_log_panel)
	_log_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_log_panel.offset_left = -420
	_log_panel.offset_right = -18
	_log_panel.offset_top = 76
	_log_label = UiKit.label("", 16, PAPER)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.custom_minimum_size.x = 380
	_log_panel.add_child(_log_label)


func _small_round(text: String) -> Button:
	return UiKit.round_button(text, 46, Color(INK, 0.85), PAPER, 22)


func _set_fast(on: bool) -> void:
	_fast = on
	Engine.time_scale = 2.0 if on else 1.0
	Prefs.set_value("battle", "fast", on)
	_set_lit(_fast_button, on)


## 开着的开关、能放的组合技：圆钮描金边。
func _set_lit(b: Button, on: bool) -> void:
	if b == null:
		return
	var style := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
	style.border_color = UiKit.GOLD if on else PAPER
	style.set_border_width_all(4 if on else 3)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)


func _build_center() -> void:
	_banner = UiKit.outlined("", 30, UiKit.GOLD)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.z_index = BAR_LAYER
	add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -300
	_banner.offset_right = 300
	_banner.offset_top = 100


## 底下不要整条栏：左下当前出手的人（版画半身像探出来 + 说明），右下一组圆钮。
func _build_bottom_bar() -> void:
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(0.04, 0.03, 0.02, 0.72), Color(0.04, 0.03, 0.02, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.25, 1.0)
	tex.fill_to = Vector2(0.95, 0.2)
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = BAR_LAYER
	add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	glow.offset_top = -280
	glow.offset_right = 760

	_actor_bust = TextureRect.new()
	_actor_bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_actor_bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var fade := ShaderMaterial.new()
	fade.shader = load("res://scripts/ui/shaders/fade_right.gdshader")
	_actor_bust.material = fade
	_actor_bust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actor_bust.z_index = BAR_LAYER
	add_child(_actor_bust)
	_actor_bust.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_actor_bust.offset_left = -12
	_actor_bust.offset_top = -214
	_actor_bust.offset_right = 206
	_actor_bust.offset_bottom = 4

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.z_index = BAR_LAYER
	add_child(info)
	info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	info.offset_left = 196
	info.offset_right = 720
	info.offset_top = -132
	info.offset_bottom = -14
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 14)
	info.add_child(name_row)
	_actor_label = UiKit.outlined("", 34, PAPER)
	name_row.add_child(_actor_label)
	_target_label = UiKit.outlined("", 19, Color("d6c4a0"))
	_target_label.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(_target_label)
	_hint_label = UiKit.outlined("", 19, UiKit.GOLD)
	_hint_label.clip_text = true
	_hint_label.custom_minimum_size.x = 500
	info.add_child(_hint_label)
	_intent_label = UiKit.outlined("", 16, Color("e8a090"))
	_intent_label.clip_text = true
	info.add_child(_intent_label)

	_attack_button = _corner_button("攻", ATTACK_SPOT, Color(INK, 0.92), PAPER, 56)
	_skill_button = _corner_button("技", SKILL_SPOT, ENEMY_RED, PAPER, 38)
	_guard_button = _corner_button("守", GUARD_SPOT, Color(INK, 0.9), PAPER, 32)
	_combo_button = _corner_button("合", COMBO_SPOT, Color(INK, 0.9), PAPER, 28)
	_skill_sub = _corner_caption(SKILL_SPOT)
	_corner_caption(GUARD_SPOT).text = "防御"
	_combo_sub = _corner_caption(COMBO_SPOT)
	_attack_button.pressed.connect(_choose.bind(BattleModel.Action.ATTACK))
	_skill_button.pressed.connect(_choose.bind(BattleModel.Action.SKILL))
	_guard_button.pressed.connect(_choose.bind(BattleModel.Action.GUARD))
	_combo_button.pressed.connect(_choose.bind(BattleModel.Action.COMBO))


## 右下角的圆钮：spot 是（中心离右边、离下边、直径）。
func _corner_button(text: String, spot: Vector3, fill: Color, text_color: Color, font_size: int) -> Button:
	var b := UiKit.round_button(text, spot.z, fill, text_color, font_size)
	b.z_index = BAR_LAYER
	add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	b.offset_left = -spot.x - spot.z / 2
	b.offset_right = -spot.x + spot.z / 2
	b.offset_top = -spot.y - spot.z / 2
	b.offset_bottom = -spot.y + spot.z / 2
	return b


## 圆钮下面的一行小字。
func _corner_caption(spot: Vector3) -> Label:
	var l := UiKit.outlined("", 15, PAPER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = BAR_LAYER
	add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	l.offset_left = -spot.x - 70
	l.offset_right = -spot.x + 70
	l.offset_top = -spot.y + spot.z / 2 + 2
	l.offset_bottom = -spot.y + spot.z / 2 + 24
	return l


# --- 结算 ---

## 结算：赢了「咚」地盖下一枚朱红「胜」字大印，输了一团墨晕开一个「败」字；下面展开一卷宣纸写三星条件和奖励。
func _show_result() -> void:
	var won := model.result == BattleModel.Result.WIN
	_banner.text = ""
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.0)
	dim.z_index = 40
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	create_tween().tween_property(dim, "color:a", 0.62, 0.2)

	# 大印
	var seal_size := 168.0
	var seal := PanelContainer.new()
	var seal_style := StyleBoxFlat.new()
	seal_style.bg_color = ENEMY_RED if won else INK
	seal_style.set_corner_radius_all(10 if won else int(seal_size / 2))
	seal_style.set_border_width_all(5)
	seal_style.border_color = PAPER if won else Color("5a1a14")
	seal.add_theme_stylebox_override("panel", seal_style)
	seal.custom_minimum_size = Vector2(seal_size, seal_size)
	seal.size = Vector2(seal_size, seal_size)
	seal.z_index = 41
	var mark := UiKit.label("胜" if won else "败", 118, PAPER if won else Color("c8b8a0"))
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(mark)
	add_child(seal)
	seal.position = Vector2((size.x - seal_size) / 2, size.y * 0.06)
	seal.pivot_offset = seal.size / 2
	seal.rotation = -0.08 if won else 0.0
	seal.modulate.a = 0.0
	var st := create_tween().set_parallel()
	if won:
		seal.scale = Vector2(2.4, 2.4)
		st.tween_property(seal, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		st.tween_property(seal, "modulate:a", 1.0, 0.12)
	else:
		# 墨慢慢晕开
		seal.scale = Vector2(0.4, 0.4)
		st.tween_property(seal, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		st.tween_property(seal, "modulate:a", 1.0, 0.5)
	await st.finished
	if won:
		_shake_screen(14.0)

	# 宣纸卷：从中间往两边展开
	var scroll := PanelContainer.new()
	var paper := UiKit.box(Color("ece0c4"), INK, 2, 4)
	paper.content_margin_left = 48
	paper.content_margin_right = 48
	paper.content_margin_top = 18
	paper.content_margin_bottom = 20
	scroll.add_theme_stylebox_override("panel", paper)
	scroll.custom_minimum_size = Vector2(560, 0)
	# 宣纸和两头的木轴放在一个普通节点里一起展开（木轴不能放进容器，会被拉伸）
	var holder := Control.new()
	holder.z_index = 41
	add_child(holder)
	holder.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	var stars := UiKit.label("★".repeat(model.stars()) + "☆".repeat(3 - model.stars()), 44, ENEMY_RED)
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stars)
	var conditions := model.star_conditions()
	var texts := ["获胜", "无人倒下", "%d 回合内获胜（用了 %d 回合）" % [stage.star_round_limit, model.round_number()]]
	for i in texts.size():
		v.add_child(UiKit.label(("● " if conditions[i] else "○ ") + texts[i], 20, INK if conditions[i] else Color("8a7a66")))
	if won:
		var r := Encounters.rewards(model)
		var gain := UiKit.label("获得：经验 +%d　银两 +%d" % [r["exp"], r["silver"]], 22, ENEMY_RED)
		gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(gain)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	v.add_child(buttons)
	var retry := UiKit.button("再打一次", Vector2(180, 60))
	retry.pressed.connect(func() -> void: retry_requested.emit())
	buttons.add_child(retry)
	var back := UiKit.button("继续", Vector2(180, 60))
	back.pressed.connect(func() -> void: finished.emit(won))
	buttons.add_child(back)
	# 内容撑开尺寸后再摆位置、加两头的木轴
	await get_tree().process_frame
	holder.position = Vector2((size.x - scroll.size.x) / 2, seal.position.y + seal_size + 26)
	for left in [true, false]:
		var rod := ColorRect.new()
		rod.color = Color("5c3a22")
		rod.size = Vector2(16, scroll.size.y + 24)
		rod.position = Vector2(-16 if left else scroll.size.x, -12)
		holder.add_child(rod)
	holder.pivot_offset = Vector2(scroll.size.x / 2, 0)
	holder.scale = Vector2(0.02, 1)
	create_tween().tween_property(holder, "scale:x", 1.0, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
