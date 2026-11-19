class_name UnitCard
extends PanelContainer
## 战斗里一个单位的卡片：半身像、名字、血条、怒气条、状态。点击时发出 tapped。
## 敌人的卡片左右镜像，半身像也翻转成脸朝左。

signal tapped(card: UnitCard)

const CARD_SIZE := Vector2(340, 136)
const BUST_SIZE := 104
const ACTIVE_SHIFT := 36.0

var unit: BattleUnit
var home_position := Vector2.ZERO

var _name_label: Label
var _intent_label: Label
var _mark_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _status_label: Label
var _rage_bar: ProgressBar
var _active := false
var _targeted := false


func setup(p_unit: BattleUnit) -> void:
	unit = p_unit
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP

	var enemy := unit.side == BattleUnit.Side.ENEMY
	var row_main := HBoxContainer.new()
	row_main.add_theme_constant_override("separation", 10)
	add_child(row_main)
	var bust := UiKit.picture(unit.data.bust, BUST_SIZE, enemy)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	for child: Control in ([v, bust] if enemy else [bust, v]):
		row_main.add_child(child)

	var top := HBoxContainer.new()
	v.add_child(top)
	_name_label = UiKit.label("", 22)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name_label)
	_mark_label = UiKit.label("", 18, UiKit.ACCENT)
	top.add_child(_mark_label)
	_intent_label = UiKit.label("", 15, UiKit.TEXT_DIM)
	v.add_child(_intent_label)

	_hp_bar = _bar(UiKit.HP, 14)
	v.add_child(_hp_bar)
	var row := HBoxContainer.new()
	v.add_child(row)
	_hp_label = UiKit.label("", 15, UiKit.TEXT_DIM)
	_hp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_hp_label)
	_status_label = UiKit.label("", 15, UiKit.RAGE)
	row.add_child(_status_label)
	_rage_bar = _bar(UiKit.RAGE, 8)
	v.add_child(_rage_bar)

	UiKit.ignore_mouse(self)
	refresh()


func refresh() -> void:
	var dead := not unit.is_alive()
	_name_label.text = "%s  Lv%d" % [unit.display_name(), unit.level]
	_hp_bar.max_value = unit.max_hp
	_hp_bar.value = unit.hp
	_hp_label.text = "%d / %d" % [unit.hp, unit.max_hp]
	_rage_bar.max_value = BattleUnit.RAGE_MAX
	_rage_bar.value = unit.rage
	_status_label.text = " ".join(unit.status_tags())
	_mark_label.text = ""
	var border := UiKit.rarity_color(unit.data)
	var width := 2
	if _active:
		border = UiKit.ACCENT
		width = 5
	elif _targeted and not dead:
		border = UiKit.DAMAGE
		width = 5
	add_theme_stylebox_override("panel", UiKit.box(UiKit.role_color(unit.data), border, width))
	if dead:
		_intent_label.text = ""
	modulate = Color(1, 1, 1, 0.35) if dead else Color.WHITE


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


## 敌人卡片上的「下一步」，或好汉卡片上「被瞄准」的警告。danger 为 true 时用红色。
func set_intent(text: String, danger: bool) -> void:
	_intent_label.text = text
	_intent_label.add_theme_color_override("font_color", UiKit.DAMAGE if danger else UiKit.TEXT_DIM)


## 出手时朝目标冲一下：冲到最远处时返回（此时结算命中），弹回的动画继续在后台播。
func lunge(toward: Vector2) -> void:
	var start := position
	var offset := (toward - start).normalized() * 70.0
	var t := create_tween()
	t.tween_property(self, "position", start + offset, 0.09).set_ease(Tween.EASE_OUT)
	await t.finished
	create_tween().tween_property(self, "position", start, 0.14).set_ease(Tween.EASE_IN_OUT)


## 被打中时闪白。
func flash() -> void:
	self_modulate = Color(2.2, 2.2, 2.2)
	create_tween().tween_property(self, "self_modulate", Color.WHITE, 0.18)


## 在卡片上方飘一行字，例如伤害数字。
func popup(text: String, color: Color, big := false) -> void:
	var l := UiKit.label(text, 48 if big else 34, color)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.z_index = 10
	get_parent().add_child(l)
	l.position = position + Vector2(CARD_SIZE.x * 0.3, -8)
	var t := l.create_tween()
	t.tween_property(l, "position:y", l.position.y - 56, 0.9)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.4)
	t.tween_callback(l.queue_free)


func shake() -> void:
	var t := create_tween()
	for dx: float in [8.0, -8.0, 5.0, 0.0]:
		t.tween_property(self, "position:x", position.x + dx, 0.04)


func _bar(color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	var bg := UiKit.box(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 4)
	var fill := UiKit.box(color, color, 0, 4)
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
