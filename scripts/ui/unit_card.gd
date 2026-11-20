class_name UnitCard
extends Control
## 战场上的一个人：放大的像素小人站在地上（脚下有影子），下面一块名牌（名字、血条、怒气条、状态），
## 名牌上方一个气泡写着敌人下一步要干什么（好汉被瞄准时也有）。点击时发出 tapped。
## 敌人脸朝左（小人翻转）。轮到谁出手谁往前站一步、脚下亮金圈；被选中的目标脚下亮红圈。
## 动作都是程序做的：待机起伏、出手蓄力冲刺、远程拉弓、受击后仰、倒地、胜利跳一下。

signal tapped(card: UnitCard)

## 整个人（含名牌）占的大小
const CARD_SIZE := Vector2(190, 272)
const FIGURE_HEIGHT := 206.0
const PLATE_HEIGHT := 62.0
const ACTIVE_SHIFT := 30.0
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
var _hp_label: Label
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
	_plate.position = Vector2(4, FIGURE_HEIGHT + 4)
	_plate.size = Vector2(CARD_SIZE.x - 8, PLATE_HEIGHT)
	add_child(_plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_plate.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	v.add_child(top)
	if IdentitySeal.COLORS.has(unit.data.rarity):
		top.add_child(IdentitySeal.make(unit.data.rarity, 20))
	_name_label = UiKit.label("", 18, _name_color())
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	top.add_child(_name_label)
	_hp_label = UiKit.label("", 13, UiKit.TEXT_DIM)
	top.add_child(_hp_label)
	_hp_bar = _bar(UiKit.HP, 10)
	v.add_child(_hp_bar)
	_rage_bar = _bar(UiKit.RAGE, 5)
	v.add_child(_rage_bar)
	_status_label = UiKit.label("", 13, UiKit.RAGE)
	_status_label.clip_text = true
	v.add_child(_status_label)

	_bubble = PanelContainer.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.z_index = 6
	add_child(_bubble)
	_bubble_label = UiKit.label("", 14)
	_bubble.add_child(_bubble_label)
	_bubble.visible = false
	UiKit.ignore_mouse(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	refresh()
	_start_idle()


func refresh() -> void:
	var dead := not unit.is_alive()
	_name_label.text = "%s Lv%d" % [unit.display_name(), unit.level]
	_hp_bar.max_value = unit.max_hp
	_hp_bar.value = unit.hp
	_hp_label.text = "%d" % unit.hp
	_rage_bar.max_value = BattleUnit.RAGE_MAX
	_rage_bar.value = unit.rage
	_status_label.text = " ".join(unit.status_tags())
	var border := UiKit.BOSS if unit.data.is_boss else UiKit.CARD_FRAME
	if _active:
		border = UiKit.GOLD
	elif _targeted and not dead:
		border = UiKit.DAMAGE
	_plate.add_theme_stylebox_override("panel", UiKit.box(Color(0.08, 0.07, 0.06, 0.82), border, 3 if (_active or _targeted) else 1, 6))
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


## 状态特效：该有就挂上（循环播），没有了就摘掉。
## 名字颜色：好汉按品级（甲金乙紫丙蓝丁灰），主角蓝，头目橙红，其他敌人米白。
func _name_color() -> Color:
	match unit.data.rarity:
		UnitData.Rarity.TIANGANG, UnitData.Rarity.DISHA:
			return UiKit.TIER_COLORS[unit.data.tier]
		UnitData.Rarity.PROTAGONIST:
			return UiKit.ACCENT
	return UiKit.BOSS if unit.data.is_boss else UiKit.TEXT


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


## 敌人头顶的气泡：下一步要干什么（要放技能时变红）；好汉被瞄准时也冒一个红气泡。
func set_intent(text: String, danger: bool) -> void:
	_bubble.visible = text != "" and unit.is_alive()
	if not _bubble.visible:
		return
	_bubble_label.text = text.trim_prefix("下一步：")
	_bubble.add_theme_stylebox_override("panel", UiKit.box(Color(0.55, 0.1, 0.08, 0.92) if danger else Color(0.08, 0.07, 0.06, 0.85), UiKit.DAMAGE if danger else UiKit.PANEL_LIGHT, 2, 8))
	_bubble.reset_size()
	_bubble.position = Vector2((CARD_SIZE.x - _bubble.size.x) / 2, FIGURE_HEIGHT - _bubble.size.y - 2)
	# 站在屏幕边上的人，气泡往里挪，别露出屏幕外
	var left := global_position.x + _bubble.position.x
	var right := get_viewport_rect().size.x - (left + _bubble.size.x)
	_bubble.position.x += maxf(4.0 - left, 0.0) - maxf(4.0 - right, 0.0)


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
	var bg := UiKit.box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), 0, 3)
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
