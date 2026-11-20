class_name EventPanel
extends Control
## 奇遇、支线的选择面板：标题、描述、几个选项；选了之后显示结果。盖在当前画面上。

signal _picked(index: int)
signal _closed

var _title: Label
var _body: Label
var _choices: VBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.12, 0.11, 0.1, 0.97), UiKit.GOLD, 2, 12))
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	_title = UiKit.label("", 30, UiKit.GOLD)
	v.add_child(_title)
	_body = UiKit.label("", 22)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 680
	v.add_child(_body)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 10)
	v.add_child(_choices)


## 显示事件，等玩家选。返回选中的选项。
func ask(event: EventData) -> EventChoice:
	visible = true
	_title.text = event.title
	_body.text = event.text.replace("{name}", GameState.player_name)
	_clear_choices()
	for i in event.choices.size():
		var c := event.choices[i]
		var label := c.label
		if c.cost_silver > 0:
			label += "（花 %d 两）" % c.cost_silver
		if c.martial != null and c.martial.id in GameState.martials:
			label += "（已学会）"
		var b := UiKit.button(label, Vector2(680, 56), 22)
		b.disabled = not Rewards.affordable(c)
		b.pressed.connect(func() -> void: _picked.emit(i))
		_choices.add_child(b)
	var index: int = await _picked
	return event.choices[index]


## 显示选择的结果和获得的东西，点「继续」后关闭。
func show_result(text: String, gained: String) -> void:
	visible = true
	_body.text = text.replace("{name}", GameState.player_name) + ("\n\n" + gained if gained != "" else "")
	_clear_choices()
	var ok := UiKit.button("继续", Vector2(680, 56), 22)
	ok.pressed.connect(func() -> void: _closed.emit())
	_choices.add_child(ok)
	await _closed
	visible = false


func close() -> void:
	visible = false


func _clear_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
