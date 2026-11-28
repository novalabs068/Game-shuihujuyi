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
## 棋盘站位：每方 2 排 × 3 路。我方在左：前排（离敌人近）脚底 x 在 GRID_FRONT_X、后排在 GRID_BACK_X；
## 上中下三路脚底 y 在 LANE_Y，越上越远（往中间收一点、画小一点）。敌方左右镜像。
const GRID_FRONT_X := 470.0
const GRID_BACK_X := 290.0
const LANE_Y: Array[float] = [276.0, 382.0, 488.0]
## 远处的路往中间收多少（透视）
const LANE_SKEW := 36.0
## 大体型（占一路两格）画大多少
const BIG_SCALE := 1.3
## 画的层次：人物 1～3（越靠下越上层）；天气 4、前景草 5、目标箭头 6，都在背景之上
## 背景放大倍数（贴底边对齐，裁掉上面的天空，把地面抬到人脚下）
const BG_ZOOM := 1.3
## 所有站位整体往下挪这么多，踩在地面上
const FEET_DROP := 30.0
## 站位远近：脚底 y（挪之前）在这个范围里，人物从小（远处的路）画到大（近处的路）
const DEPTH_Y := Vector2(276, 488)
const DEPTH_RANGE := Vector2(0.72, 0.92)
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
const MOVE_SPOT := Vector3(358, 62, 62)
## 统领的「号令」圆钮（只有带了号令时才出现）
const COMMAND_SPOT := Vector3(470, 62, 62)
## 法术伤害的数字颜色（青）
const MAGIC_CYAN := Color("8fe3f0")
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
## 结算：背景压暗到多少；大字（繁体「胜」「败」）中心的高度和边长；后面那笔横刷的大小；「大捷」小印的边长；手卷宽度
const RESULT_DIM := 0.72
const RESULT_MARK_Y := 128.0
const RESULT_MARK_SIZE := 220.0
const RESULT_STROKE_SIZE := Vector2(620, 126)
const RESULT_SEAL_SIZE := 74.0
const RESULT_SCROLL_WIDTH := 640.0
## 手卷各部分的大小：两头锦缎包首的宽、木轴的粗细、木轴比纸上下各长出多少、轴头大小、纸上下米色窄边的高
const SCROLL_BROCADE_W := 34.0
const SCROLL_ROD_W := 24.0
const SCROLL_ROD_OVER := 6.0
const SCROLL_CAP := Vector2(32, 16)
const SCROLL_EDGE_H := 8.0
## 星印的直径；云头木牌按钮和红穗的大小
const STAR_SEAL := 40.0
const PLAQUE_SIZE := Vector2(190, 60)
const TASSEL_SIZE := Vector2(20, 55)
## 结算的颜色：输了的淡墨字、没达成的淡字、纸上下的米色窄边和它的细线、锦缎接缝的金线
const DEFEAT_INK := Color("9a8e7e")
const RESULT_FADED := Color("9a8a74")
const SCROLL_EDGE := Color("c8b48c")
const SCROLL_EDGE_LINE := Color("967850")
const RESULT_GOLD := Color("cea656")
## 结算卷轴和木牌上的毛笔字体

var stage: StageData
var team: Array[UnitData] = []
## 我方每人的等级（和 team 一一对应）
var hero_levels: Array[int] = []
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
## 绝招钮上的冷却圈，和上次轮到每个人时他还剩几回合冷却（用来播「亮回一格」的动画）
var _cooldown_ring: CooldownRing
var _ring_actor: BattleUnit
var _ring_seen: Dictionary[BattleUnit, int] = {}
## 我方的阵法和每人站的格子（GameState 里存的；空的按阵法、按职业自动摆）
var _formation: StringName = &""
var placement: Array = []
## 战场背景（按 BG_ZOOM 放大、贴底边摆）
var _scene: TextureRect
var _combo_sub: Label
var _move_button: Button
var _command_button: Button
var _command_sub: Label
## 补位：点了「补位」后在等玩家点一个空格子
var _move_mode := false
var _move_cell := Grid.NONE
var _board: BattleBoard
var _boss_bar: BossBar
## 正在播的这一招打几格、已经打到了谁（画穿透、连锁、横扫、全屏的特效用）
var _area := SkillData.Area.SINGLE
var _area_hits: Array[BattleUnit] = []


func _ready() -> void:
	_formation = GameState.current_formation()
	model = BattleModel.new(stage, team, 1, GameState.combos(), -1, _formation, placement, hero_levels)
	if team.any(func(u: UnitData) -> bool: return u.id == BattleModel.COMMANDER_ID):
		model.command = GameState.battle_command()
	Vitality.apply_start(model, start_hp)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if background != null:
		_scene = TextureRect.new()
		_scene.texture = background
		_scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_scene.stretch_mode = TextureRect.STRETCH_SCALE
		# 压暗一些，人物和数字才看得清
		_scene.modulate = Color(0.62, 0.6, 0.58)
		_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_scene)
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
	_board = BattleBoard.new()
	_board.cell_center = _cell_center
	_board.cell_tapped.connect(_on_cell_tapped)
	add_child(_board)
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var weather := BattleWeather.make(place, Vector2(1280, 720))
	if weather != null:
		weather.z_index = 4
		add_child(weather)
	_build_top_bar()
	_build_center()
	_build_bottom_bar()
	for u in model.units:
		if u.side == BattleUnit.Side.ENEMY and u.data.is_boss and _boss_bar == null:
			_boss_bar = BossBar.new()
			_boss_bar.z_index = BAR_LAYER
			add_child(_boss_bar)
			_boss_bar.setup(u)
			_boss_bar.position = Vector2((1280 - _boss_bar.size.x) / 2, 92)
			_boss_bar.scale = Vector2(0.02, 1)
			_banner.offset_top = 166
	for u in model.units:
		_add_card(u)
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


func _add_card(u: BattleUnit) -> UnitCard:
	var card := UnitCard.new()
	add_child(card)
	card.setup(u)
	card.tapped.connect(_on_card_tapped)
	_cards[u] = card
	_restack()
	return card


## 按站的格子重新定远近和层次（补位、召唤之后）。
func _restack() -> void:
	for u in _cards:
		_cards[u].set_depth(_slot_depth(u) * (BIG_SCALE if u.data.big else 1.0))
		_cards[u].z_index = _slot_layer(u)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# --- 主循环 ---

func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	if _boss_bar != null:
		await _boss_entrance(_boss_bar.unit)
	# 准备回合：开局效果一条一条亮出来
	if not model.opening_events.is_empty():
		_banner.text = "准备回合"
		await get_tree().create_timer(0.35).timeout
		await _play(model.opening_events)
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
				events = model.act(choice as BattleModel.Action, _target, _move_cell)
			_move_cell = Grid.NONE
			_move_mode = false
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
	for index in events.size():
		var e := events[index]
		if not is_inside_tree():
			return
		var kind: String = e["kind"]
		var unit: BattleUnit = e["unit"]
		var popup: String = e["popup"]
		var log_text: String = e["log"]
		var big: bool = e["big"]
		var source: BattleUnit = e["source"]
		if not _cards.has(unit):
			_add_card(unit)
			_layout()
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
				_area = e.get("area", SkillData.Area.SINGLE)
				_area_hits.clear()
				wait = 0.0
			"skill":
				_banner.text = ""
				_area = e.get("area", SkillData.Area.SINGLE)
				_area_hits.clear()
				if unit.data.is_boss and e.get("charged", false):
					await _boss_ultimate(unit, e.get("cells", []))
				await _skill_cutin(unit, popup)
				wait = 0.0
			"combo":
				_banner.text = ""
				_area = SkillData.Area.SINGLE
				_area_hits.clear()
				await _combo_cutin(unit, source, popup)
				wait = 0.0
			"charge":
				_banner.text = "%s 蓄力！地上的红格就是要砸的地方" % unit.display_name()
				FxSprite.spawn(self, "cursed", card.feet_point(), FX_SCALE, false, 0)
				card.popup(popup, CRIT_RED, true)
				Sfx.play(&"skill_drum", -6.0)
				_refresh()
				wait = 0.8
			"prep":
				_banner.text = "准备回合 · %s" % log_text.get_slice("：", 0)
				FxSprite.spawn(self, "blessing", card.feet_point(), FX_SCALE * 0.9, false, 0)
				card.popup(popup, UiKit.GOLD)
				wait = 0.55
			"banner":
				_banner.text = "「%s」" % popup
				if popup in ["破绽", "破阵", "士气受挫"]:
					await _big_text(popup, UiKit.GOLD if popup == "破绽" else CRIT_RED)
				else:
					card.popup(popup, UiKit.GOLD, true)
				_shake_screen(10.0)
				wait = 0.4
			"phase":
				_banner.text = "「%s」" % popup
				await _big_text(popup, CRIT_RED)
				_shake_screen(14.0)
				wait = 0.3
			"bar":
				if _boss_bar != null:
					_boss_bar.shatter()
				_shake_screen(8.0)
				Sfx.play(&"hit_crit", -2.0)
				wait = 0.15
			"damage":
				var from_left := source == null or source.side == BattleUnit.Side.PLAYER
				var fx: String = e.get("fx", "")
				var magic: bool = e.get("magic", false)
				_area_hits.append(unit)
				# 一招打几个人：只在打第一个人时冲上去 / 射过去，后面的用范围特效连起来
				var follow_up := _area_hits.size() > 1 and _area != SkillData.Area.SINGLE
				if follow_up or _area == SkillData.Area.ROW or _area == SkillData.Area.ALL:
					_area_fx(unit)
				if source != null and source != unit and not follow_up:
					var style := source.data.attack_style
					if style in RANGED_STYLES or not source.is_melee():
						await _cards[source].shoot()
						Sfx.play(&"arrow", -4.0, 0.1)
						await Projectile.fly(self, _cards[source].muzzle_point(), card.hit_point(), style if style in RANGED_STYLES else &"throw")
					else:
						await _cards[source].lunge(card.position)
					if fx == "":
						_style_hit_fx(style, card, from_left)
				# 群攻技能各有各的特效：爆炸、震地落在脚下，重劈对着胸口
				if fx in ["heavy_cleave", "sword_slash"]:
					FxSprite.spawn(self, fx, card.hit_point(), FX_SCALE * 0.8, not from_left)
				elif fx != "":
					FxSprite.spawn(self, fx, card.feet_point(), 1.1, not from_left)
					_shake_screen(6.0)
				FxSprite.spawn(self, "crit_hit" if big else "hit_spark", card.hit_point(), FX_SCALE * (0.8 if big else 1.0), not from_left)
				if magic:
					FxSprite.spawn(self, "cursed", card.hit_point(), FX_SCALE * 0.5, false, 0)
				card.show_hp(e.get("hp", unit.hp))
				card.flash()
				card.shake()
				_hit_sound(source, big)
				_ink_splash(card.hit_point(), from_left, big)
				card.popup(popup, CRIT_RED if big else (MAGIC_CYAN if magic else UiKit.DAMAGE), big)
				if _boss_bar != null and unit == _boss_bar.unit:
					_boss_bar.show_hp(e.get("hp", unit.hp))
				if big:
					_shake_screen(10.0)
					_punch_zoom(card.hit_point())
				await _hitstop(0.1 if big else 0.045)
				wait = 0.16
			"dodge":
				if source != null and source != unit and source.is_melee():
					await _cards[source].lunge(card.position)
				card.dodge()
				card.popup(popup, Color("bfe3ff"), true)
				Sfx.play(&"arrow", -8.0, 0.2)
				wait = 0.2
			"move":
				_restack()
				var to := _card_position(unit)
				var mt := create_tween()
				mt.tween_property(card, "position", to, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				await mt.finished
				card.place(to)
				FxSprite.spawn(self, "poof", card.feet_point(), FX_SCALE * 0.6)
				card.popup(popup, UiKit.GOLD)
				wait = 0.1
			"summon":
				await _summon_fx(card)
				card.popup(popup, UiKit.GOLD, true)
				wait = 0.3
			"steal":
				if source != null and _cards.has(source):
					await _steal_fx(_cards[source], card)
				card.popup(popup, UiKit.GOLD, true)
				wait = 0.25
			"heal":
				card.show_hp(e.get("hp", unit.hp))
				FxSprite.spawn(self, "heal", card.feet_point(), FX_SCALE)
				card.popup(popup, UiKit.HEAL)
			"death":
				if unit.side == BattleUnit.Side.ENEMY and model.result == BattleModel.Result.WIN and not _more_deaths(events, index):
					await _finishing_blow(card)
				card.mark_dead()
				FxSprite.spawn(self, "poof", card.hit_point() + Vector2(0, 40), FX_SCALE)
				card.popup(popup, UiKit.TEXT_DIM)
				wait = 0.25
			_:
				# 加速、增攻、护盾这类增益：脚下升起一道光
				if popup in ["加速", "增攻"] or popup.begins_with("护盾"):
					FxSprite.spawn(self, "blessing", card.feet_point(), FX_SCALE * 0.9, false, 0)
				if popup != "":
					card.popup(popup, UiKit.GOLD if popup in ["追击", "缴械", "计穷", "破绽", "尾应", "夹击", "扑空"] or popup.begins_with("韧性") else UiKit.TEXT, popup == "扑空")
					wait = 0.15
		if _boss_bar != null:
			_boss_bar.refresh()
		_refresh()
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout


## 后面还有没有别人倒下（最后一个倒下的才放慢镜头）。
func _more_deaths(events: Array[Dictionary], from: int) -> bool:
	for k in range(from + 1, events.size()):
		if events[k]["kind"] == "death" and events[k]["unit"].side == BattleUnit.Side.ENEMY:
			return true
	return false


## 范围招的特效：穿透一道墨线贯穿一路；连锁一道光弧从上一个人跳到这个人；多人一道冲击波扫过一排；
## 全范围镜头先拉远、整片敌阵上墨团炸开。
func _area_fx(unit: BattleUnit) -> void:
	var card := _cards[unit]
	match _area:
		SkillData.Area.LANE:
			if _area_hits.size() == 2:
				_streak(_cards[_area_hits[0]].hit_point(), card.hit_point(), Color(0.06, 0.04, 0.03, 0.9), 16.0)
		SkillData.Area.CHAIN:
			if _area_hits.size() >= 2:
				_streak(_cards[_area_hits[_area_hits.size() - 2]].hit_point(), card.hit_point(), Color("9fe8ff"), 6.0, true)
		SkillData.Area.ROW:
			if _area_hits.size() == 1:
				var y := card.feet_point().y
				var from_x := size.x * (0.55 if unit.side == BattleUnit.Side.ENEMY else 0.05)
				_streak(Vector2(from_x, y), Vector2(from_x + size.x * 0.4, y - 60), Color(0.95, 0.85, 0.6, 0.85), 26.0)
				_shake_screen(8.0)
		SkillData.Area.ALL:
			if _area_hits.size() == 1:
				var center := Vector2(size.x * (0.72 if unit.side == BattleUnit.Side.ENEMY else 0.28), size.y * 0.55)
				pivot_offset = center
				var t := create_tween()
				t.tween_property(self, "scale", Vector2(0.94, 0.94), 0.12).set_ease(Tween.EASE_OUT)
				t.tween_property(self, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_IN_OUT)
				FxSprite.spawn(self, "explosion", center + Vector2(0, 40), 2.2)
				_ink_splash(center, unit.side == BattleUnit.Side.ENEMY, true)
				_shake_screen(16.0)


## 一道笔触：从 a 拉到 b，停一下淡掉。jagged 为 true 画成折线（连锁的光弧）。
func _streak(a: Vector2, b: Vector2, color: Color, width: float, jagged := false) -> void:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.z_index = 14
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	if jagged:
		var steps := 6
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			if k > 0 and k < steps:
				p += Vector2(randf_range(-14, 14), randf_range(-14, 14))
			line.add_point(p)
	else:
		line.add_point(a)
		line.add_point(b)
	add_child(line)
	line.modulate.a = 0.0
	var t := line.create_tween()
	t.tween_property(line, "modulate:a", 1.0, 0.05)
	t.tween_interval(0.18)
	t.tween_property(line, "modulate:a", 0.0, 0.3)
	t.tween_callback(line.queue_free)


## 召唤：格子上亮起一圈金色符阵，召唤物从烟里显出来。
func _summon_fx(card: UnitCard) -> void:
	var ring := Line2D.new()
	ring.width = 5.0
	ring.default_color = Color("f0c060")
	ring.z_index = 0
	for k in 33:
		var ang := TAU * k / 32
		ring.add_point(card.feet_point() + Vector2(cos(ang) * 70, sin(ang) * 22))
	add_child(ring)
	card.modulate.a = 0.0
	FxSprite.spawn(self, "poof", card.feet_point() + Vector2(0, -40), FX_SCALE)
	Sfx.play(&"skill_draw", -6.0)
	var t := create_tween()
	t.tween_property(card, "modulate:a", 1.0, 0.35)
	t.parallel().tween_property(ring, "rotation", 0.3, 0.6)
	t.tween_property(ring, "modulate:a", 0.0, 0.3)
	t.tween_callback(ring.queue_free)
	await t.finished


## 偷取：一团金光从被偷的人头上飞进出手的人手里。
func _steal_fx(thief: UnitCard, target: UnitCard) -> void:
	var orb := ColorRect.new()
	orb.color = Color("f0c060")
	orb.size = Vector2(18, 18)
	orb.pivot_offset = orb.size / 2
	orb.rotation = PI / 4
	orb.z_index = 15
	orb.position = target.hit_point() - orb.size / 2
	add_child(orb)
	var mid := (target.hit_point() + thief.hit_point()) / 2 + Vector2(0, -120)
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		var p := target.hit_point().lerp(mid, k).lerp(mid.lerp(thief.hit_point(), k), k)
		orb.position = p - orb.size / 2, 0.0, 1.0, 0.4)
	t.tween_callback(orb.queue_free)
	await t.finished


## 最后一击：时间放慢、镜头推近，四周压暗一下。
func _finishing_blow(card: UnitCard) -> void:
	var vignette := ColorRect.new()
	vignette.color = Color(0, 0, 0, 0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.z_index = 25
	add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pivot_offset = card.hit_point()
	var t := create_tween().set_parallel()
	t.tween_property(self, "scale", Vector2(1.12, 1.12), 0.25).set_ease(Tween.EASE_OUT)
	t.tween_property(vignette, "color:a", 0.35, 0.25)
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.55, true, false, true).timeout
	if not is_inside_tree():
		return
	Engine.time_scale = 2.0 if _fast else 1.0
	var back := create_tween().set_parallel()
	back.tween_property(self, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_IN_OUT)
	back.tween_property(vignette, "color:a", 0.0, 0.3)
	back.chain().tween_callback(vignette.queue_free)


## 屏幕正中砸下两个大字（破绽、破阵、第二阶段……），带金色裂纹。
func _big_text(text: String, color: Color) -> void:
	var l := UiKit.outlined(text, 96, color)
	l.add_theme_constant_override("outline_size", 14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 32
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(size.x, 130)
	l.position = Vector2(0, size.y * 0.3)
	l.pivot_offset = l.size / 2
	l.scale = Vector2(2.0, 2.0)
	l.modulate.a = 0.0
	add_child(l)
	var cracks := Line2D.new()
	cracks.width = 3.0
	cracks.default_color = Color(color, 0.9)
	cracks.z_index = 31
	var c := Vector2(size.x / 2, size.y * 0.3 + 65)
	for k in 7:
		cracks.add_point(c)
		var ang := TAU * k / 7 + randf_range(-0.2, 0.2)
		cracks.add_point(c + Vector2(cos(ang), sin(ang) * 0.5) * randf_range(140, 260))
	cracks.modulate.a = 0.0
	add_child(cracks)
	var t := create_tween().set_parallel()
	t.tween_property(l, "scale", Vector2.ONE, 0.16).set_ease(Tween.EASE_IN)
	t.tween_property(l, "modulate:a", 1.0, 0.1)
	t.tween_property(cracks, "modulate:a", 1.0, 0.1).set_delay(0.14)
	await t.finished
	Sfx.play(&"hit_crit", 0.0)
	await get_tree().create_timer(0.45).timeout
	var out := create_tween().set_parallel()
	out.tween_property(l, "modulate:a", 0.0, 0.25)
	out.tween_property(cracks, "modulate:a", 0.0, 0.25)
	await out.finished
	l.queue_free()
	cracks.queue_free()


## 头目登场：黑屏，竖排大字写名号，盖一方朱印；然后血条从中间往两边展开。
func _boss_entrance(boss: BattleUnit) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = 35
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.0)
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fig := _portrait(boss, size.y * 0.9, true)
	fig.position = Vector2(size.x * 0.52, size.y * 0.1)
	fig.modulate.a = 0.0
	layer.add_child(fig)
	var name_text := "\n".join(Array(boss.display_name().split("")))
	var title := UiKit.outlined(name_text, 64, Color("f4e8cc"))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_constant_override("line_spacing", -10)
	title.position = Vector2(size.x * 0.3, size.y * 0.08)
	title.visible_ratio = 0.0
	layer.add_child(title)
	var seal := PanelContainer.new()
	seal.add_theme_stylebox_override("panel", UiKit.box(ENEMY_RED, PAPER, 3, 6))
	var mark := UiKit.label("头目", 30, PAPER)
	seal.add_child(mark)
	seal.position = Vector2(size.x * 0.3 - 90, size.y * 0.6)
	seal.modulate.a = 0.0
	layer.add_child(seal)
	Sfx.play(&"skill_drum", 0.0)
	var t := create_tween().set_parallel()
	t.tween_property(dim, "color:a", 0.82, 0.25)
	t.tween_property(fig, "modulate:a", 1.0, 0.35)
	t.tween_property(title, "visible_ratio", 1.0, 0.5).set_delay(0.15)
	await t.finished
	seal.pivot_offset = seal.size / 2
	seal.scale = Vector2(2.0, 2.0)
	var st := create_tween().set_parallel()
	st.tween_property(seal, "modulate:a", 1.0, 0.08)
	st.tween_property(seal, "scale", Vector2.ONE, 0.14).set_ease(Tween.EASE_IN)
	await st.finished
	_shake_screen(12.0)
	await get_tree().create_timer(0.7).timeout
	var out := create_tween()
	out.tween_property(layer, "modulate:a", 0.0, 0.25)
	await out.finished
	layer.queue_free()
	if _boss_bar != null:
		_boss_bar.pivot_offset = Vector2(_boss_bar.size.x / 2, 0)
		_boss_bar.scale = Vector2(0.02, 1)
		create_tween().tween_property(_boss_bar, "scale:x", 1.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## 头目放蓄满的大招：画面压暗只剩红格在闪，一声吼震屏；然后接绝招切入。
func _boss_ultimate(boss: BattleUnit, cells: Array) -> void:
	var m := {}
	for c: Vector2i in cells:
		m[_board.key(BattleUnit.Side.PLAYER, c)] = ["danger"]
	_board.set_marks(m)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.0, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 8
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.z_index = 9
	var t := create_tween()
	t.tween_property(dim, "color:a", 0.6, 0.2)
	await t.finished
	_cards[boss].popup("吼——", CRIT_RED, true)
	Sfx.play(&"skill_drum", 2.0)
	_shake_screen(16.0)
	await get_tree().create_timer(0.45).timeout
	var out := create_tween()
	out.tween_property(dim, "color:a", 0.0, 0.15)
	await out.finished
	dim.queue_free()
	_board.z_index = 0


## 放技能：一条色带从出手者那一侧滑进来，带着半身像和技能名。
## 放绝招：画面压暗，版画全身像从出手那一侧滑进来，一笔浓墨刷开，招式名一个字一个字写出来。
func _skill_cutin(unit: BattleUnit, skill_name: String) -> void:
	var from_left := unit.side == BattleUnit.Side.PLAYER
	Sfx.play(&"skill_drum", -2.0)
	Sfx.play(&"skill_draw", -1.0)
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
	# 结义同心：统领不在阵上，左边换成主角的立绘
	if a == b and GameState.protagonist() != null:
		a = BattleUnit.new(GameState.protagonist(), BattleUnit.Side.PLAYER, -1, 1)
	Sfx.play(&"skill_drum")
	Sfx.play(&"skill_draw")
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
## 命中声：斧棒拳脚是闷击，其余是刀光；暴击更响。
## 命中声按兵器分：刀剑枪矛「砍」、斧棒禅杖「砸」、拳脚爪牙「打」；暴击是金铁交鸣。
func _hit_sound(source: BattleUnit, big: bool) -> void:
	if big:
		Sfx.play(&"hit_crit", 1.0, 0.08)
		return
	var style := source.data.attack_style if source != null else &""
	var sound := &"hit_slash"
	if style == &"heavy":
		sound = &"hit_blunt"
	elif style in [&"fist", &"claw"]:
		sound = &"hit_fist"
	Sfx.play(sound, -3.0, 0.12)


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

## 统领发号令：不占出手，播完效果接着等玩家选行动。
func _on_command() -> void:
	if not _awaiting_input or not model.can_command():
		return
	_awaiting_input = false
	_move_mode = false
	_refresh()
	await _play(model.use_command())
	_awaiting_input = true
	_refresh()

func _choose(action: int) -> void:
	if _awaiting_input:
		_move_mode = false
		_action_chosen.emit(action)


## 「补位」：再点一下取消；点了之后在我方空格子里挑一格。
func _toggle_move() -> void:
	if not _awaiting_input or model.current == null:
		return
	_move_mode = not _move_mode
	_hint_label.text = "点一个发青光的空格子挪过去（这一回合防御）；再点「补位」取消" if _move_mode else ""
	_refresh()


func _on_cell_tapped(side: BattleUnit.Side, c: Vector2i) -> void:
	if not _move_mode or side != BattleUnit.Side.PLAYER or model.current == null:
		return
	if model.can_move_to(model.current, c):
		_move_cell = c
		_move_mode = false
		_action_chosen.emit(BattleModel.Action.MOVE)


func _on_card_tapped(card: UnitCard) -> void:
	var u := card.unit
	if not u.is_alive():
		return
	if u.side == BattleUnit.Side.ENEMY:
		var actor := model.current
		if _awaiting_input and actor != null and actor.side == BattleUnit.Side.PLAYER and not model.can_reach(actor, u):
			_hint_label.text = "%s被前排挡着，%s近战够不着（刺客、远程才打得到，或者先打开这一路）" % [u.display_name(), actor.display_name()]
			card.popup("挡", UiKit.TEXT_DIM)
			return
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
		_target_label.text = ("→ %s%s" % [_target.display_name(), Roles.matchup_text(actor.data.role, _target.data.role)]) if player and _target != null else "出手…"
		var skill := actor.data.skill
		_hint_label.text = ""
		if skill != null:
			_hint_label.text = "「%s」%s" % [skill.display_name, skill.description]
			if player and actor.silence_turns > 0:
				_hint_label.text = "计穷：还有 %d 回合放不了绝招和组合技" % actor.silence_turns
			elif player and not actor.skill_ready():
				_hint_label.text = "「%s」冷却中，还要 %d 回合。普攻、防御能攒怒气" % [skill.display_name, actor.skill_cooldown]
			if player and not actor.can_attack():
				_hint_label.text += "　被缴械：不能普攻"
	else:
		_actor_label.text = ""
		_target_label.text = ""
		_hint_label.text = ""
	# 选中的敌人下一步要干什么
	_intent_label.text = ""
	if player and _target != null:
		_intent_label.text = "%s %s" % [_target.display_name(), _intent_text(_target)]

	_refresh_board(actor, input and player)

	# 右下：圆钮
	for b: Button in [_attack_button, _skill_button, _guard_button, _combo_button, _move_button]:
		b.disabled = not input
	_move_button.disabled = not input or not player or actor.data.big or model.free_cells(actor.side).is_empty()
	_set_lit(_move_button, _move_mode)
	var skill_name := actor.data.skill.display_name if player and actor.data.skill != null else ""
	_skill_button.text = skill_name.left(1) if skill_name != "" else "技"
	_skill_sub.text = skill_name if skill_name != "" else "绝招"
	if player and actor.data.skill != null and not actor.skill_ready():
		_skill_button.disabled = true
		_skill_sub.text = "计穷 %d" % actor.silence_turns if actor.silence_turns > 0 else "冷却 %d" % actor.skill_cooldown
	if player and not actor.can_attack():
		_attack_button.disabled = true
	_update_cooldown_ring(actor if player else null)
	var combo := model.available_combo(actor) if player else null
	_combo_button.disabled = not input or combo == null
	_combo_sub.text = combo.display_name if combo != null else "组合技"
	_set_lit(_combo_button, combo != null and input)
	if _command_button != null:
		var ready := input and player and model.can_command()
		_command_button.disabled = not ready
		_set_lit(_command_button, ready)
		_command_sub.text = "号令·%s" % Commands.display_name(model.command) if not model.command_used else "号令已用"


## 地面格子上色：头目要砸的红格；轮到玩家时，普攻会打到的格子金色、绝招的范围朱红描边；补位时能去的空格青色。
## 近战够不着的敌人压暗。
func _refresh_board(actor: BattleUnit, my_turn: bool) -> void:
	var marks := {}
	var add := func(side: BattleUnit.Side, c: Vector2i, mark: String) -> void:
		var k := _board.key(side, c)
		if not marks.has(k):
			marks[k] = []
		if not mark in marks[k]:
			marks[k].append(mark)
	for e in model.alive(BattleUnit.Side.ENEMY):
		if e.charging:
			for c in e.charge_cells:
				add.call(BattleUnit.Side.PLAYER, c, "danger")
	if my_turn and _move_mode:
		for c in model.free_cells(actor.side):
			add.call(BattleUnit.Side.PLAYER, c, "move")
	elif my_turn and _target != null and _target.is_alive():
		var primary := model._pick_foe(actor, _target)
		for h in model.area_targets(actor, primary, actor.data.basic_area):
			for c in h[0].cells():
				add.call(BattleUnit.Side.ENEMY, c, "gold")
		var sk := actor.data.skill
		if sk != null and actor.skill_ready() and (sk.needs_enemy_target() or sk.effect in SkillData.ALL_EFFECTS):
			var hits := model.area_targets(actor, primary, sk.area) if sk.needs_enemy_target() else model.foes_of(actor).map(func(f: BattleUnit) -> Array: return [f, 1.0])
			for h in hits:
				for c in h[0].cells():
					add.call(BattleUnit.Side.ENEMY, c, "skill")
	_board.set_marks(marks)
	for u in _cards:
		if u.side == BattleUnit.Side.ENEMY:
			_cards[u].set_reachable(not my_turn or not u.is_alive() or model.can_reach(actor, u))


## 一格在屏幕上的中心（脚底）：我方按 _cell_spot，敌方左右镜像。
func _cell_center(side: BattleUnit.Side, c: Vector2i) -> Vector2:
	var p := _cell_spot(c) + Vector2(0, FEET_DROP - 8)
	if side == BattleUnit.Side.ENEMY:
		p.x = size.x - p.x
	return p


## 头顶小圆标的字：敌人普攻「攻」、要放绝招「技」、眩晕「晕」；好汉被敌人绝招瞄准「危」。
func _intent_mark(u: BattleUnit) -> String:
	if not u.is_alive():
		return ""
	if u.side == BattleUnit.Side.ENEMY:
		if u.stun_turns > 0:
			return "晕"
		if model.intent_target_of(u) == null:
			return ""
		if u.charging:
			return "蓄"
		return "技" if u.intent_skill and u.data.skill != null else "攻"
	return "危" if model.is_threatened(u) else ""


func _intent_text(u: BattleUnit) -> String:
	if not u.is_alive():
		return ""
	if u.side == BattleUnit.Side.ENEMY:
		if u.stun_turns > 0:
			return "眩晕中，下一步动不了"
		if u.silence_turns > 0 and u.intent_skill:
			return "计穷，绝招放不出来"
		var t := model.intent_target_of(u)
		if t == null:
			return ""
		if u.charging:
			return "蓄力中！下一步「%s」砸地上的红格，伤害 ×%.1f：挪出红格、防御，或者打空它的韧性" % [u.data.skill.display_name, BattleModel.CHARGE_BONUS]
		if u.intent_skill and u.data.skill != null and u.data.is_boss:
			return "下一步：蓄力，准备「%s」" % u.data.skill.display_name
		if u.intent_skill and u.data.skill != null:
			return "下一步：「%s」→ %s" % [u.data.skill.display_name, t.display_name()]
		return "下一步：普攻 → %s" % t.display_name()
	for e in model.alive(BattleUnit.Side.ENEMY):
		if model.releases_skill_next(e) and model.intent_target_of(e) == u:
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
	var color := Color("ffd98a") if current else (UiKit.GILT if u.side == BattleUnit.Side.PLAYER else ENEMY_RED)
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


## 冷却圈：每回合亮回一格。轮到一个新的人时，从少一格的样子长到现在的样子；刚好转满就闪一下。
func _update_cooldown_ring(actor: BattleUnit) -> void:
	if actor == null or actor.data.skill == null:
		_cooldown_ring.recovered = 1.0
		_ring_actor = null
		return
	var total := maxi(actor.skill_cooldown_total, actor.skill_cooldown)
	var remaining := actor.skill_cooldown
	var target := 1.0 if remaining <= 0 or total <= 0 else float(total - remaining) / total
	_cooldown_ring.segments = maxi(total, 1)
	if actor == _ring_actor:
		_cooldown_ring.recovered = target
		return
	_ring_actor = actor
	var was: int = _ring_seen.get(actor, 0)
	_ring_seen[actor] = remaining
	# 和上次轮到时不一样（冷却减了一格，或者中间放过绝招）：从少一格的样子长过来
	if was != remaining and total > 0:
		_cooldown_ring.recovered = maxf(target - 1.0 / total, 0.0)
		var t := _cooldown_ring.create_tween()
		t.tween_property(_cooldown_ring, "recovered", target, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		if remaining <= 0:
			_skill_button.pivot_offset = _skill_button.size / 2
			t.tween_property(_skill_button, "scale", Vector2(1.15, 1.15), 0.1)
			t.tween_property(_skill_button, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_cooldown_ring.recovered = target


## 这个人脚底站在哪（我方坐标，敌方在 _layout 里左右镜像）：按格子算，越远的路往中间收；大体型站在前后两格中间。
func _slot_feet(u: BattleUnit) -> Vector2:
	return _slot_spot(u) + Vector2(0, FEET_DROP)


func _slot_spot(u: BattleUnit) -> Vector2:
	return _cell_spot(Vector2i(maxi(u.row, 0), u.lane), u.data.big)


## 一格的脚底位置（我方坐标）。
func _cell_spot(c: Vector2i, big := false) -> Vector2:
	var x := GRID_FRONT_X if c.x == 0 else GRID_BACK_X
	if big:
		x = (GRID_FRONT_X + GRID_BACK_X) / 2
	return Vector2(x + (1 - c.y) * LANE_SKEW, LANE_Y[c.y])


## 远近按脚底的高低算：越靠下越近、画得越大。
func _slot_depth(u: BattleUnit) -> float:
	var t := clampf(inverse_lerp(DEPTH_Y.x, DEPTH_Y.y, _slot_spot(u).y), 0.0, 1.0)
	return lerpf(DEPTH_RANGE.x, DEPTH_RANGE.y, t)


## 越靠下的画在越上层（1～3，三路各一层）。
func _slot_layer(u: BattleUnit) -> int:
	return 1 + u.lane


## 卡片左上角该在哪（敌方左右镜像）。
func _card_position(u: BattleUnit) -> Vector2:
	var feet := _slot_feet(u)
	var p := Vector2(feet.x - UnitCard.CARD_SIZE.x / 2, feet.y - UnitCard.FEET.y)
	if u.side == BattleUnit.Side.ENEMY:
		p.x = size.x - p.x - UnitCard.CARD_SIZE.x
	return p


func _layout() -> void:
	# 背景放大、贴底边：水墨画的空地都在下面三成，抬上来铺到人脚下，人就不会站到树上、房上
	if _scene != null and _scene.texture != null:
		var tex := _scene.texture.get_size()
		var k := maxf(size.x / tex.x, size.y / tex.y) * BG_ZOOM
		_scene.size = tex * k
		_scene.position = Vector2((size.x - _scene.size.x) / 2, size.y - _scene.size.y)
	for u in _cards:
		_cards[u].place(_card_position(u))


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

	# 回合数写在一块黑漆小匾上
	var round_plaque := PanelContainer.new()
	round_plaque.add_theme_stylebox_override("panel", UiKit.lacquer_box())
	round_plaque.z_index = BAR_LAYER
	round_plaque.position = Vector2(18, 16)
	round_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(round_plaque)
	_round_label = UiKit.brush_label("", 28, Color("f1d99c"))
	round_plaque.add_child(_round_label)

	# 出手顺序串在一根木杆上
	var line := ColorRect.new()
	line.color = Color("6a4429")
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.z_index = BAR_LAYER
	line.position = Vector2(196, 42)
	line.size = Vector2(700, 6)
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
	style.border_color = Color("ffd98a") if on else UiKit.GILT
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
	# 左下角版式不变，名字换成毛笔字（提示还是正文的宋体）
	_actor_label = UiKit.outlined("", 40, PAPER)
	_actor_label.add_theme_font_override("font", UiKit.brush_font())
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
	_move_button = _corner_button("位", MOVE_SPOT, Color("2f5a54"), PAPER, 28)
	_corner_caption(MOVE_SPOT).text = "补位"
	_move_button.pressed.connect(_toggle_move)
	_skill_sub = _corner_caption(SKILL_SPOT)
	_cooldown_ring = CooldownRing.new()
	_skill_button.add_child(_cooldown_ring)
	_cooldown_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_corner_caption(GUARD_SPOT).text = "防御"
	_combo_sub = _corner_caption(COMBO_SPOT)
	_attack_button.pressed.connect(_choose.bind(BattleModel.Action.ATTACK))
	_skill_button.pressed.connect(_choose.bind(BattleModel.Action.SKILL))
	_guard_button.pressed.connect(_choose.bind(BattleModel.Action.GUARD))
	_combo_button.pressed.connect(_choose.bind(BattleModel.Action.COMBO))
	if model.command != &"":
		var cname := Commands.display_name(model.command)
		_command_button = _corner_button(cname.left(1), COMMAND_SPOT, Color("8f2a1c"), PAPER, 28)
		_command_sub = _corner_caption(COMMAND_SPOT)
		_command_sub.text = "号令·%s" % cname
		_command_button.tooltip_text = Commands.describe(model.command)
		_command_button.pressed.connect(_on_command)


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

## 战斗统计：每人、每回合的输出、承伤、治疗等。
func _open_stats() -> void:
	var panel := BattleStatsPanel.new()
	panel.model = model
	panel.z_index = 60
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(panel.queue_free)


## 结算（宋朝风味，图都由 tools/result_marks.py 生成）：
## 赢了，一笔朱红横刷扫过去，繁体「胜」字毛笔大字砸下来，右下角盖一方「大捷」小印；
## 输了，淡墨的繁体「败」字慢慢晕开。下面展开一卷宣纸手卷（靛青锦边、木轴），
## 三星条件达成的用朱笔画个圈，再写奖励；最下面一排木牌按钮，「继续」是朱漆的。
func _show_result() -> void:
	var won := model.result == BattleModel.Result.WIN
	_banner.text = ""
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.0)
	dim.z_index = 40
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	create_tween().tween_property(dim, "color:a", RESULT_DIM, 0.25)

	var mark_center := Vector2(size.x / 2, RESULT_MARK_Y)
	if won:
		await _victory_mark(mark_center)
	else:
		await _defeat_mark(mark_center)
	_result_scroll(won, mark_center.y + RESULT_MARK_SIZE / 2 + 22)


## 赢：朱红横刷从左往右扫开 →「胜」字从大到小砸下来、震屏 → 小印「咚」地盖上。
func _victory_mark(center: Vector2) -> void:
	var stroke := TextureRect.new()
	stroke.texture = load("res://art/ui/result_stroke.png")
	stroke.modulate = STROKE_RED
	stroke.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stroke.stretch_mode = TextureRect.STRETCH_SCALE
	stroke.size = RESULT_STROKE_SIZE
	stroke.position = center - RESULT_STROKE_SIZE / 2 + Vector2(0, 14)
	stroke.pivot_offset = Vector2(0, RESULT_STROKE_SIZE.y / 2)
	stroke.scale = Vector2(0, 1)
	stroke.z_index = 41
	stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stroke)
	Sfx.play(&"skill_draw")
	var st := create_tween()
	st.tween_property(stroke, "scale:x", 1.0, 0.26).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await st.finished

	var mark := _result_picture("res://art/ui/result_win.png", Vector2.ONE * RESULT_MARK_SIZE, PAPER)
	mark.position = center - mark.size / 2
	add_child(mark)
	mark.scale = Vector2(1.9, 1.9)
	mark.modulate.a = 0.0
	var mt := create_tween().set_parallel()
	mt.tween_property(mark, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	mt.tween_property(mark, "modulate:a", 1.0, 0.1)
	await mt.finished
	_shake_screen(14.0)
	Sfx.play(&"victory")

	var seal := _result_picture("res://art/ui/result_seal.png", Vector2.ONE * RESULT_SEAL_SIZE, Color.WHITE)
	seal.position = center + Vector2(RESULT_MARK_SIZE * 0.34, RESULT_MARK_SIZE * 0.2)
	seal.rotation = 0.1
	add_child(seal)
	seal.scale = Vector2(1.7, 1.7)
	seal.modulate.a = 0.0
	var sl := create_tween().set_parallel()
	sl.tween_property(seal, "scale", Vector2.ONE, 0.12).set_delay(0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	sl.tween_property(seal, "modulate:a", 1.0, 0.08).set_delay(0.12)
	await sl.finished
	Sfx.play(&"token_slam", -6.0)


## 输：淡墨「败」字从小慢慢晕开。
func _defeat_mark(center: Vector2) -> void:
	var mark := _result_picture("res://art/ui/result_lose.png", Vector2.ONE * RESULT_MARK_SIZE, DEFEAT_INK)
	mark.position = center - mark.size / 2
	add_child(mark)
	mark.scale = Vector2(0.82, 0.82)
	mark.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(mark, "scale", Vector2.ONE, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(mark, "modulate:a", 1.0, 0.6)
	await t.finished


## 结算用的一张图（白色的图在这里染色），中心为轴，便于缩放、旋转。
func _result_picture(path: String, picture_size: Vector2, color: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = load(path)
	r.modulate = color
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size = picture_size
	r.pivot_offset = picture_size / 2
	r.z_index = 41
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 手卷：宣纸心子、上下米色窄边，两头靛青锦缎包首，再外面是木轴和玉色轴头（图见 tools/result_marks.py）。
## 两根木轴从中间往两边滚开，纸跟着露出来；下面一排云头木牌按钮淡入，「继续」下面的红穗轻轻摆。
func _result_scroll(won: bool, top: float) -> void:
	var holder := Control.new()
	holder.z_index = 41
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	add_child(holder)
	# 纸和锦缎放在一个裁切框里，框从中间往两边变宽，就像纸被展开
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(clip)
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(inner)

	var scroll := PanelContainer.new()
	var paper := StyleBoxTexture.new()
	paper.texture = load("res://art/ui/result_paper.png")
	paper.content_margin_left = 40
	paper.content_margin_right = 40
	paper.content_margin_top = 22
	paper.content_margin_bottom = 26
	scroll.add_theme_stylebox_override("panel", paper)
	scroll.custom_minimum_size = Vector2(RESULT_SCROLL_WIDTH, 0)
	scroll.position = Vector2(SCROLL_BROCADE_W, 0)
	inner.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	scroll.add_child(v)

	# 三颗星：三方小圆印，拿到的朱红实心，没拿到的只剩淡淡一个圈
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.add_theme_constant_override("separation", 16)
	v.add_child(star_row)
	for i in 3:
		star_row.add_child(_star_seal(i < model.stars()))

	# 三星条件：一列左对齐，整列居中；达成的前面朱笔画圈
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	list.add_theme_constant_override("separation", 0)
	v.add_child(list)
	var conditions := model.star_conditions()
	var texts := ["获胜", "无人倒下", "%d 回合内获胜（用了 %d 回合）" % [model.round_limit(), model.round_number()]]
	for i in texts.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_check_mark(conditions[i]))
		row.add_child(_brush_label(texts[i], 28, INK if conditions[i] else RESULT_FADED))
		list.add_child(row)
	if won:
		var r := Encounters.rewards(model)
		var gain := _brush_label("所得　经验 +%d　银两 +%d" % [r["exp"], r["silver"]], 28, ENEMY_RED)
		gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(gain)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 26)
	buttons.z_index = 41
	add_child(buttons)
	var stats_button := _plaque_button("战斗统计", false)
	stats_button.pressed.connect(_open_stats)
	buttons.add_child(stats_button)
	var retry := _plaque_button("再打一次", false)
	retry.pressed.connect(func() -> void: retry_requested.emit())
	buttons.add_child(retry)
	var back := _plaque_button("继续", true)
	back.pressed.connect(func() -> void: finished.emit(won))
	buttons.add_child(back)
	buttons.modulate.a = 0.0

	# 内容撑开纸的高度后，再加上下窄边、两头锦缎和木轴
	await get_tree().process_frame
	var paper_h := scroll.size.y
	var paper_w := scroll.size.x
	for at_top in [true, false]:
		var edge := ColorRect.new()
		edge.color = SCROLL_EDGE
		edge.size = Vector2(paper_w, SCROLL_EDGE_H)
		edge.position = Vector2(SCROLL_BROCADE_W, 0.0 if at_top else paper_h - SCROLL_EDGE_H)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(edge)
		var line := ColorRect.new()
		line.color = SCROLL_EDGE_LINE
		line.size = Vector2(paper_w, 1)
		line.position = Vector2(SCROLL_BROCADE_W, SCROLL_EDGE_H if at_top else paper_h - SCROLL_EDGE_H - 1)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(line)
	for left in [true, false]:
		var brocade := TextureRect.new()
		brocade.texture = load("res://art/ui/result_brocade.png")
		brocade.stretch_mode = TextureRect.STRETCH_TILE
		brocade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		brocade.size = Vector2(SCROLL_BROCADE_W, paper_h)
		brocade.position = Vector2(0.0 if left else SCROLL_BROCADE_W + paper_w, 0)
		brocade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(brocade)
		# 锦缎和纸接缝处一道金线
		var seam := ColorRect.new()
		seam.color = RESULT_GOLD
		seam.size = Vector2(2, paper_h)
		seam.position = Vector2(SCROLL_BROCADE_W - 2 if left else SCROLL_BROCADE_W + paper_w, 0)
		seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(seam)
	var spread := paper_w + 2 * SCROLL_BROCADE_W
	var rods: Array[Control] = [_scroll_rod(paper_h), _scroll_rod(paper_h)]
	for rod in rods:
		holder.add_child(rod)
	clip.size = Vector2(spread, paper_h)
	holder.position = Vector2((size.x - spread) / 2, top)
	holder.modulate.a = 1.0
	buttons.position = Vector2((size.x - buttons.size.x) / 2, top + paper_h + SCROLL_CAP.y + 24)

	# 展开：t 从 0 到 1，纸从中间往两边露出来，两根木轴贴着纸边往外滚
	var unroll := func(t: float) -> void:
		var w := spread * t
		clip.position.x = (spread - w) / 2
		clip.size.x = w
		inner.position.x = -clip.position.x
		rods[0].position.x = clip.position.x - SCROLL_ROD_W
		rods[1].position.x = clip.position.x + w
	unroll.call(0.0)
	Sfx.play(&"card_flip", -4.0)
	var t := create_tween()
	t.tween_method(unroll, 0.0, 1.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(buttons, "modulate:a", 1.0, 0.2)


## 一根木轴：竖着的木头圆柱比纸上下各长出一点，两头套玉色轴头。返回的节点左上角对齐纸的上边、木轴的左边。
func _scroll_rod(paper_h: float) -> Control:
	var rod := Control.new()
	rod.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wood := TextureRect.new()
	wood.texture = load("res://art/ui/result_rod.png")
	wood.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wood.stretch_mode = TextureRect.STRETCH_SCALE
	wood.size = Vector2(SCROLL_ROD_W, paper_h + 2 * SCROLL_ROD_OVER)
	wood.position = Vector2(0, -SCROLL_ROD_OVER)
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rod.add_child(wood)
	for y in [-SCROLL_ROD_OVER - SCROLL_CAP.y, paper_h + SCROLL_ROD_OVER]:
		var cap := TextureRect.new()
		cap.texture = load("res://art/ui/result_cap.png")
		cap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cap.stretch_mode = TextureRect.STRETCH_SCALE
		cap.size = SCROLL_CAP
		cap.position = Vector2((SCROLL_ROD_W - SCROLL_CAP.x) / 2, y)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rod.add_child(cap)
	return rod


## 一颗星：小圆印。拿到的朱红底、宣纸色星；没拿到的只有淡淡的圈和星。
func _star_seal(got: bool) -> PanelContainer:
	var seal := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ENEMY_RED if got else Color(0, 0, 0, 0)
	style.border_color = ENEMY_RED if got else RESULT_FADED
	style.set_border_width_all(0 if got else 2)
	style.set_corner_radius_all(int(STAR_SEAL / 2))
	seal.add_theme_stylebox_override("panel", style)
	seal.custom_minimum_size = Vector2(STAR_SEAL, STAR_SEAL)
	var star := UiKit.label("★", 22, PAPER if got else RESULT_FADED)
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(star)
	return seal


## 毛笔字（马善政毛笔楷书，见 UiKit.brush_font）；数字落到思源宋体。

static func _brush() -> Font:
	return UiKit.brush_font()


func _brush_label(text: String, font_size: int, color: Color) -> Label:
	var l := UiKit.label(text, font_size, color)
	l.add_theme_font_override("font", _brush())
	return l


## 条件前的小记号：达成的是一个朱笔圈（不封口，像手画的），没达成的是一个淡墨点。
func _check_mark(done: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(28, 36)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var o := c.size / 2
		if done:
			c.draw_arc(o, 11.0, -2.2, -2.2 + TAU * 0.93, 28, ENEMY_RED, 3.5, true)
		else:
			c.draw_circle(o, 3.0, RESULT_FADED))
	return c


## 云头木牌按钮：两头像如意云头，金边木纹，毛笔字；主按钮（继续）是朱漆的，下面垂一缕红穗轻轻摆。
func _plaque_button(text: String, primary: bool) -> Button:
	var b := UiKit.button(text, PLAQUE_SIZE, 28)
	var texture: Texture2D = load("res://art/ui/result_plaque_red.png" if primary else "res://art/ui/result_plaque.png")
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxTexture.new()
		style.texture = texture
		match state:
			"hover":
				style.modulate_color = Color(1.15, 1.12, 1.08)
			"pressed":
				style.modulate_color = Color(0.78, 0.74, 0.7)
			"focus":
				style.modulate_color = Color(1, 1, 1, 0)
		b.add_theme_stylebox_override(state, style)
	b.add_theme_font_override("font", _brush())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, PAPER)
	if primary:
		var tassel := TextureRect.new()
		tassel.texture = load("res://art/ui/result_tassel.png")
		tassel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tassel.stretch_mode = TextureRect.STRETCH_SCALE
		tassel.size = TASSEL_SIZE
		tassel.position = Vector2((PLAQUE_SIZE.x - TASSEL_SIZE.x) / 2, PLAQUE_SIZE.y - 6)
		tassel.pivot_offset = Vector2(TASSEL_SIZE.x / 2, 0)
		tassel.show_behind_parent = true
		tassel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tassel)
		var sway := tassel.create_tween().set_loops()
		sway.tween_property(tassel, "rotation", 0.09, 1.1).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sway.tween_property(tassel, "rotation", -0.09, 1.1).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	return b
