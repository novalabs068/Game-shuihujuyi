class_name DialogueBox
extends PanelContainer
## 对话框：说话人的版画半身像、名字、逐字打出的台词。点一下打完这句，再点翻到下一句。

signal _advanced

const CHARS_PER_SECOND := 40.0

var _bust: TextureRect
var _name_label: Label
var _text_label: Label
var _typing: Tween


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiKit.box(Color(0.1, 0.09, 0.08, 0.94), UiKit.GOLD, 2, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	_bust = UiKit.picture(null, 150)
	row.add_child(_bust)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	_name_label = UiKit.label("", 26, UiKit.GOLD)
	v.add_child(_name_label)
	_text_label = UiKit.label("", 24)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_text_label)
	var more := UiKit.label("点击继续 ▼", 16, UiKit.TEXT_DIM)
	more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(more)
	UiKit.ignore_mouse(self)


## 逐句播放。每行「说话人：台词」，没有冒号的是旁白。speakers 把说话人名字对到 UnitData（用来显示半身像），
## 「我」对应主角，显示时换成主角的名字；台词里的 {name} 换成主角的名字。
func run(lines: PackedStringArray, speakers: Dictionary) -> void:
	visible = true
	var me: UnitData = speakers.get("我")
	for raw in lines:
		var line := raw.replace("{name}", me.display_name if me != null else "")
		var speaker := ""
		var text := line
		var colon := line.find("：")
		if colon > 0 and colon <= 6:
			speaker = line.substr(0, colon)
			text = line.substr(colon + 1)
		var unit: UnitData = speakers.get(speaker)
		_bust.texture = unit.bust if unit != null else null
		_bust.visible = unit != null
		_name_label.text = unit.display_name if speaker == "我" and unit != null else speaker
		_text_label.text = text
		_text_label.visible_ratio = 0.0
		_typing = create_tween()
		_typing.tween_property(_text_label, "visible_ratio", 1.0, text.length() / CHARS_PER_SECOND)
		await _advanced
	visible = false


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if _typing != null and _typing.is_running():
		_typing.kill()
		_text_label.visible_ratio = 1.0
	else:
		_advanced.emit()
