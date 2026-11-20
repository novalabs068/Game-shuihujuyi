class_name UnitCard
extends Control
## 战场上的一个人：版画立绘站在地上（脚下有影子），下面一块名牌（名字、血条、怒气条、状态），
## 名牌上方一个气泡写着敌人下一步要干什么（好汉被瞄准时也有）。点击时发出 tapped。
## 敌人脸朝左（立绘翻转）。轮到谁出手谁往前站一步、脚下亮金圈；被选中的目标脚下亮红圈。

signal tapped(card: UnitCard)

## 整个人（含名牌）占的大小
const CARD_SIZE := Vector2(190, 272)
const FIGURE_HEIGHT := 206.0
const PLATE_HEIGHT := 62.0
const ACTIVE_SHIFT := 30.0
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
	_figure.size = Vector2(CARD_SIZE.x, FIGURE_HEIGHT)
	_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := unit.data.portrait if unit.data.portrait != null else unit.data.bust
	if art == null:
		# 还没有版画立绘的：用像素小人放大
		art = unit.data.map_sprite
		_figure.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_figure.texture = art
	add_child(_figure)
	# 立绘底边对齐脚底：图比框矮时往下挪
	if art != null:
		var aspect := float(art.get_width()) / art.get_height()
		var h := minf(FIGURE_HEIGHT, CARD_SIZE.x / aspect)
		_figure.size.y = h
		_figure.position.y = FIGURE_HEIGHT - h

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
	else:
		modulate = Color.WHITE
	_sync_overlay("stunned", not dead and unit.stun_turns > 0, Vector2(FEET.x, 40), 2.2)
	var weakened := unit.buffs.any(func(b: BattleUnit.Buff) -> bool: return b.atk_bonus < 0.0 or b.spd_bonus < 0.0)
	_sync_overlay("cursed", not dead and weakened, FEET, 2.4)
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
	# 脚下的影子；轮到出手亮金圈，被选中亮红圈
	var ring := Color(0, 0, 0, 0.35)
	var width := 0.0
	if _active:
		ring = Color(UiKit.GOLD, 0.55)
		width = 4.0
	elif _targeted and unit.is_alive():
		ring = Color(UiKit.DAMAGE, 0.55)
		width = 4.0
	draw_set_transform(FEET + Vector2(0, -6), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, 70, Color(0, 0, 0, 0.35))
	if width > 0.0:
		draw_arc(Vector2.ZERO, 76, 0, TAU, 48, ring, width * 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


## 命中点：胸口（特效、飘字都对着这里）。
func hit_point() -> Vector2:
	return position + Vector2(CARD_SIZE.x / 2, FIGURE_HEIGHT * 0.55)


func feet_point() -> Vector2:
	return position + FEET


## 出手时朝目标冲一下：冲到最远处时返回（此时结算命中），弹回的动画继续在后台播。
func lunge(toward: Vector2) -> void:
	var start := position
	var offset := (toward - start).normalized() * 90.0
	var t := create_tween()
	t.tween_property(self, "position", start + offset, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await t.finished
	create_tween().tween_property(self, "position", start, 0.16).set_ease(Tween.EASE_IN_OUT)


## 被打中时立绘闪白，往后一仰。
func flash() -> void:
	_figure.self_modulate = Color(3, 3, 3)
	create_tween().tween_property(_figure, "self_modulate", Color.WHITE, 0.2)
	var back := 12.0 if unit.side == BattleUnit.Side.ENEMY else -12.0
	var t := create_tween()
	t.tween_property(_figure, "position:x", back, 0.05)
	t.tween_property(_figure, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 在头顶飘一行字，例如伤害数字。暴击的字更大、先放大再落下。
func popup(text: String, color: Color, big := false) -> void:
	var l := UiKit.label(text, 52 if big else 36, color)
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.z_index = 20
	get_parent().add_child(l)
	l.reset_size()
	l.pivot_offset = l.size / 2
	l.position = position + Vector2((CARD_SIZE.x - l.size.x) / 2 + randf_range(-16, 16), FIGURE_HEIGHT * 0.25)
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
