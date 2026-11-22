class_name UnitCard
extends Control
## 战场上的一个人：放大的像素小人站在地上（脚下有影子），脚下一块纸色腰牌（身份印、名字、血条、怒气条、状态），
## 头顶一个小圆标：敌人下一步普攻「攻」、放绝招「技」，好汉被敌人绝招瞄准时「危」。点击时发出 tapped。
## 敌人脸朝左（小人翻转）。轮到谁出手谁往前站一步、脚下亮金圈；被选中的目标脚下亮红圈。
## 动作都是程序做的：待机起伏、出手蓄力冲刺、远程拉弓、受击后仰、倒地、胜利跳一下。

signal tapped(card: UnitCard)

## 整个人（含名牌）占的大小
const CARD_SIZE := Vector2(190, 272)
const FIGURE_HEIGHT := 206.0
const ACTIVE_SHIFT := 30.0
## 脚下腰牌：纸色底、墨色字，敌人名字朱红
const PLATE_WIDTH := 126.0
const PLATE_PAPER := Color("eee4cd")
const PLATE_INK := Color("2a2420")
const PLATE_RED := Color("b0261e")
## 余血白条：掉血后停这么久再开始缩，缩这么久
const GHOST_HOLD := 0.35
const GHOST_DRAIN := 0.45
const GHOST_WHITE := Color("fffaf0")
## 血条的底槽：深墨色，红条和白条在纸色腰牌上才看得清
const HP_TRACK := Color("3a2f26")
## 头顶意图小圆标的直径
const INTENT_SIZE := 34
## 像素小人放大几倍（按整数放大，像素才不糊）；太高放不下时少放一倍
const PIXEL_SCALE := 4
## 待机时上下起伏的像素数和一个来回的秒数
const IDLE_BOB := 4.0
const IDLE_PERIOD := 1.6
## 脚底在这个人自己坐标里的位置（立绘底边中点）
const FEET := Vector2(CARD_SIZE.x / 2, FIGURE_HEIGHT)

var unit: BattleUnit
var home_position := Vector2.ZERO

var _figure: TextureRect
var _plate: PanelContainer
var _name_label: Label
var _hp_bar: ProgressBar
## 血条后面的白条：掉血时停一下再慢慢跟上，看得出刚掉了多少
var _hp_ghost: ProgressBar
var _ghost_tween: Tween
## 画面上显示的血量和是否已倒下：播到命中、倒下那一刻才变（模型里早就算完了）
var _shown_hp := 0
var _shown_dead := false
var _status_label: Label
var _rage_bar: ProgressBar
var _bubble: PanelContainer
var _bubble_label: Label
var _active := false
var _targeted := false
## 挂在身上的状态特效（眩晕的星星、减攻的黑气）
var _overlays: Dictionary[String, FxSprite] = {}
## 远近：后排的人画小一点（1 = 最前排）
var _depth := 1.0
var _idle: Tween
var _fallen := false
## 小人朝右为正方向：好汉 1、敌人 -1
var _facing := 1.0


func setup(p_unit: BattleUnit) -> void:
	unit = p_unit
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var enemy := unit.side == BattleUnit.Side.ENEMY

	_figure = TextureRect.new()
	_figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_figure.flip_h = enemy
	_facing = -1.0 if enemy else 1.0
	_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_figure)
	var sprite := unit.data.battle_sprite if unit.data.battle_sprite != null else unit.data.map_sprite
	if sprite != null:
		# 像素小人按整数倍放大，底边中点对齐脚底
		_figure.texture = sprite
		_figure.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 高清战斗小人是按 2 倍高度切的，所以少放大一半；大家像素粗细一样，高矮就和原图一样（野兽矮一截）
		var k := PIXEL_SCALE / 2 if unit.data.battle_sprite != null else PIXEL_SCALE
		while k > 1 and sprite.get_height() * k > FIGURE_HEIGHT + 24:
			k -= 1
		_figure.size = Vector2(sprite.get_width(), sprite.get_height()) * k
	else:
		# 还没有像素小人的：用版画立绘，按比例缩进框里
		var art := unit.data.portrait if unit.data.portrait != null else unit.data.bust
		_figure.texture = art
		var aspect := float(art.get_width()) / art.get_height() if art != null else 1.0
		var h := minf(FIGURE_HEIGHT, CARD_SIZE.x / aspect)
		_figure.size = Vector2(h * aspect, h)
	_figure.position = Vector2((CARD_SIZE.x - _figure.size.x) / 2, FIGURE_HEIGHT - _figure.size.y)
	_figure.pivot_offset = Vector2(_figure.size.x / 2, _figure.size.y)

	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.position = Vector2((CARD_SIZE.x - PLATE_WIDTH) / 2, FIGURE_HEIGHT + 4)
	_plate.size = Vector2(PLATE_WIDTH, 0)
	_plate.custom_minimum_size.x = PLATE_WIDTH
	add_child(_plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_plate.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	v.add_child(top)
	if IdentitySeal.COLORS.has(unit.data.rarity):
		top.add_child(IdentitySeal.make(unit.data.rarity, 18))
	# 职业小标：敌我都显示，看一眼就知道谁克谁
	top.add_child(UiKit.role_tag(unit.data, 12))
	_name_label = UiKit.label("", 16, _name_color())
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	top.add_child(_name_label)
	# 血条：白色的「余血」条垫在下面，红条叠在上面（红条底色透明）
	var hp_row := Control.new()
	hp_row.custom_minimum_size.y = 5
	v.add_child(hp_row)
	_hp_ghost = _bar(GHOST_WHITE, 5)
	var track := UiKit.box(HP_TRACK, Color(0, 0, 0, 0), 0, 1)
	track.set_content_margin_all(0)
	_hp_ghost.add_theme_stylebox_override("background", track)
	hp_row.add_child(_hp_ghost)
	_hp_ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_bar = _bar(PLATE_RED, 5)
	_hp_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	hp_row.add_child(_hp_bar)
	_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shown_hp = unit.hp
	_shown_dead = not unit.is_alive()
	_hp_ghost.max_value = unit.max_hp
	_hp_ghost.value = unit.hp
	_rage_bar = _bar(UiKit.RAGE, 3)
	v.add_child(_rage_bar)
	_status_label = UiKit.label("", 12, PLATE_RED)
	_status_label.clip_text = true
	v.add_child(_status_label)

	# 头顶的意图小圆标
	_bubble = PanelContainer.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.z_index = 6
	_bubble.custom_minimum_size = Vector2(INTENT_SIZE, INTENT_SIZE)
	add_child(_bubble)
	_bubble_label = UiKit.label("", 17, PLATE_PAPER)
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble.add_child(_bubble_label)
	_bubble.visible = false
	UiKit.ignore_mouse(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	refresh()
	_start_idle()


## 命中、回血播到这一刻：红条立刻变，白条（掉血时）停一下再跟上。
func show_hp(hp: int) -> void:
	var before := _shown_hp
	_shown_hp = hp
	_hp_ghost.max_value = unit.max_hp
	if _ghost_tween != null and _ghost_tween.is_valid():
		_ghost_tween.kill()
	if hp < before:
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(GHOST_HOLD)
		_ghost_tween.tween_property(_hp_ghost, "value", float(hp), GHOST_DRAIN).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	else:
		_hp_ghost.value = hp
	refresh()


## 倒下播到这一刻。
func mark_dead() -> void:
	_shown_dead = true
	refresh()


func refresh() -> void:
	var dead := _shown_dead
	_name_label.text = unit.display_name()
	_hp_bar.max_value = unit.max_hp
	_hp_bar.value = _shown_hp
	_rage_bar.max_value = BattleUnit.RAGE_MAX
	_rage_bar.value = unit.rage
	_status_label.text = " ".join(unit.status_tags())
	_status_label.visible = _status_label.text != ""
	var border := PLATE_INK
	if _active:
		border = UiKit.GOLD
	elif _targeted and not dead:
		border = PLATE_RED
	var plate_style := UiKit.box(PLATE_PAPER, border, 3 if (_active or _targeted) else 2, 3)
	plate_style.content_margin_left = 6
	plate_style.content_margin_right = 6
	plate_style.content_margin_top = 2
	plate_style.content_margin_bottom = 4
	_plate.add_theme_stylebox_override("panel", plate_style)
	_plate.reset_size()
	if dead:
		_bubble.visible = false
		modulate = Color(0.55, 0.55, 0.55, 0.45)
		if not _fallen:
			_fall()
	else:
		modulate = Color.WHITE
	_sync_overlay("stunned", not dead and unit.stun_turns > 0, Vector2(FEET.x, 40), 2.2)
	var weakened := unit.buffs.any(func(b: BattleUnit.Buff) -> bool: return b.atk_bonus < 0.0 or b.spd_bonus < 0.0)
	_sync_overlay("cursed", not dead and weakened, FEET, 2.4)
	_sync_overlay("burning", not dead and unit.burn_turns > 0, FEET + Vector2(0, -10), 1.6)
	queue_redraw()


## 名字颜色（腰牌是纸色底）：我方墨色，敌人朱红。
func _name_color() -> Color:
	return PLATE_INK if unit.side == BattleUnit.Side.PLAYER else PLATE_RED


## 状态特效：该有就挂上（循环播），没有了就摘掉。

func _sync_overlay(name: String, on: bool, at: Vector2, k: float) -> void:
	if on and not _overlays.has(name):
		_overlays[name] = FxSprite.spawn(self, name, at, k, false, 1)
	elif not on and _overlays.has(name):
		_overlays[name].stop()
		_overlays.erase(name)


func _draw() -> void:
	# 脚下一团晕开的墨影；轮到出手亮金圈，被选中亮红圈
	var ring := Color(0, 0, 0, 0)
	if _active:
		ring = Color(UiKit.GOLD, 0.55)
	elif _targeted and unit.is_alive():
		ring = Color(UiKit.DAMAGE, 0.55)
	draw_set_transform(FEET + Vector2(0, -6), 0.0, Vector2(_depth, 0.28 * _depth))
	for i in 5:
		draw_circle(Vector2.ZERO, 82.0 - i * 13.0, Color(0.05, 0.04, 0.03, 0.09 + i * 0.03))
	if ring.a > 0.0:
		draw_arc(Vector2.ZERO, 76, 0, TAU, 48, ring, 12.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 远近：后排的人按 k 缩小（以脚底为中心），影子跟着缩。
func set_depth(k: float) -> void:
	_depth = k
	_figure.scale = Vector2(k, k)
	queue_redraw()


func set_active(on: bool) -> void:
	_active = on
	var shift := ACTIVE_SHIFT if unit.side == BattleUnit.Side.PLAYER else -ACTIVE_SHIFT
	create_tween().tween_property(self, "position", home_position + Vector2(shift if on else 0.0, 0), 0.15)
	refresh()


func set_targeted(on: bool) -> void:
	_targeted = on
	refresh()


func place(pos: Vector2) -> void:
	home_position = pos
	var shift := ACTIVE_SHIFT if unit.side == BattleUnit.Side.PLAYER else -ACTIVE_SHIFT
	position = home_position + Vector2(shift if _active else 0.0, 0)


## 头顶的小圆标：一个字（攻、技、晕、危），danger 时朱红底；空字就藏起来。
func set_intent(mark: String, danger: bool) -> void:
	_bubble.visible = mark != "" and unit.is_alive()
	if not _bubble.visible:
		return
	_bubble_label.text = mark
	var style := UiKit.box(PLATE_RED if danger else Color(0.13, 0.1, 0.09, 0.92), PLATE_PAPER, 2, INTENT_SIZE / 2)
	style.set_content_margin_all(0)
	_bubble.add_theme_stylebox_override("panel", style)
	_bubble.size = Vector2(INTENT_SIZE, INTENT_SIZE)
	_bubble.position = Vector2((CARD_SIZE.x - INTENT_SIZE) / 2, FIGURE_HEIGHT - _figure.size.y * _depth - INTENT_SIZE - 6)


## 命中点：胸口（特效、飘字都对着这里）。
func hit_point() -> Vector2:
	return position + Vector2(CARD_SIZE.x / 2, FIGURE_HEIGHT - _figure.size.y * _depth * 0.45)


func feet_point() -> Vector2:
	return position + FEET


## 出手时朝目标冲一下：先往后一缩蓄力，再前倾冲过去；冲到最远处时返回（此时结算命中），弹回的动画继续在后台播。
func lunge(toward: Vector2) -> void:
	_pause_idle()
	var start := position
	var dir := (toward - start).normalized()
	var t := create_tween()
	t.tween_property(self, "position", start - dir * 14.0, 0.07).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_figure, "rotation", -0.18 * _facing, 0.07)
	t.tween_property(self, "position", start + dir * 90.0, 0.09).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.parallel().tween_property(_figure, "rotation", 0.22 * _facing, 0.09)
	await t.finished
	var back := create_tween()
	back.tween_property(self, "position", start, 0.16).set_ease(Tween.EASE_IN_OUT)
	back.parallel().tween_property(_figure, "rotation", 0.0, 0.16)
	back.tween_callback(_start_idle)


## 远程出手（拉弓、甩暗器）：原地往后一仰再弹回，箭和石子由 BattleView 飞过去。
func shoot() -> void:
	_pause_idle()
	var t := create_tween()
	t.tween_property(_figure, "rotation", -0.15 * _facing, 0.08)
	t.parallel().tween_property(_figure, "position:x", _figure.position.x - 8.0 * _facing, 0.08)
	await t.finished
	var back := create_tween()
	back.tween_property(_figure, "rotation", 0.08 * _facing, 0.06)
	back.parallel().tween_property(_figure, "position:x", _figure.position.x + 8.0 * _facing, 0.06)
	back.tween_property(_figure, "rotation", 0.0, 0.12)
	back.tween_callback(_start_idle)


## 箭和石子从哪里飞出去：身前、胸口高度。
func muzzle_point() -> Vector2:
	return position + Vector2(CARD_SIZE.x / 2 + 40.0 * _facing, FIGURE_HEIGHT - _figure.size.y * _depth * 0.5)


## 被打中时闪白，往后一仰。
func flash() -> void:
	_figure.self_modulate = Color(3, 3, 3)
	create_tween().tween_property(_figure, "self_modulate", Color.WHITE, 0.2)
	if _fallen:
		return
	_pause_idle()
	var t := create_tween()
	t.tween_property(_figure, "rotation", -0.2 * _facing, 0.05)
	t.parallel().tween_property(_figure, "position:x", _figure.position.x - 12.0 * _facing, 0.05)
	t.tween_property(_figure, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_figure, "position:x", _figure.position.x, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(_start_idle)


## 打赢了：活着的人原地跳两下。
func cheer() -> void:
	if _fallen:
		return
	_pause_idle()
	var base_y := _figure.position.y
	var t := create_tween()
	for i in 2:
		t.tween_property(_figure, "position:y", base_y - 28.0, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(_figure, "position:y", base_y, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(_start_idle)


## 倒地：往后侧倒下。
func _fall() -> void:
	_fallen = true
	_pause_idle()
	var t := create_tween()
	t.tween_property(_figure, "rotation", -1.45 * _facing, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## 待机：身体轻轻上下起伏，每个人起伏的时机错开一点。
func _start_idle() -> void:
	if _fallen or _figure == null:
		return
	_pause_idle()
	var base_y := FIGURE_HEIGHT - _figure.size.y
	_figure.position.y = base_y
	_idle = create_tween().set_loops()
	_idle.tween_interval(randf() * 0.3)
	_idle.tween_property(_figure, "position:y", base_y - IDLE_BOB, IDLE_PERIOD / 2).set_trans(Tween.TRANS_SINE)
	_idle.tween_property(_figure, "position:y", base_y, IDLE_PERIOD / 2).set_trans(Tween.TRANS_SINE)


func _pause_idle() -> void:
	if _idle != null and _idle.is_valid():
		_idle.kill()
	_idle = null
	if _figure != null:
		_figure.position.y = FIGURE_HEIGHT - _figure.size.y


## 在头顶飘一行字，例如伤害数字。暴击的字更大、先放大再落下。
func popup(text: String, color: Color, big := false) -> void:
	var l := UiKit.label(text, 52 if big else 36, color)
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.z_index = 20
	get_parent().add_child(l)
	l.reset_size()
	l.pivot_offset = l.size / 2
	l.position = position + Vector2((CARD_SIZE.x - l.size.x) / 2 + randf_range(-16, 16), FIGURE_HEIGHT - _figure.size.y * _depth - 10.0)
	var t := l.create_tween()
	if big:
		l.scale = Vector2(1.8, 1.8)
		t.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "position:y", l.position.y - 60, 0.8)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.35)
	t.tween_callback(l.queue_free)


func shake() -> void:
	var t := create_tween()
	for dx: float in [8.0, -8.0, 5.0, 0.0]:
		t.tween_property(self, "position:x", position.x + dx, 0.04)


func _bar(color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	var bg := UiKit.box(Color(0.55, 0.48, 0.38, 0.6), Color(0, 0, 0, 0), 0, 1)
	var fill := UiKit.box(color, color, 0, 3)
	bg.set_content_margin_all(0)
	fill.set_content_margin_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(self)
		accept_event()
