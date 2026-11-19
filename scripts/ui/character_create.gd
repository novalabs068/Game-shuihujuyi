class_name CharacterCreate
extends Control
## 创建角色：起名字、选出身。

signal created(player_name: String, origin: OriginData)
signal back_requested

const MAX_NAME_LENGTH := 6
const DEFAULT_NAME := "无名"
const CARD_SIZE := Vector2(420, 380)

var _name_edit: LineEdit
var _cards: Dictionary[OriginData, PanelContainer] = {}
var _chosen: OriginData
var _start: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	margin.add_child(v)

	v.add_child(UiKit.label("创建角色", 34))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 14)
	v.add_child(name_row)
	name_row.add_child(UiKit.label("姓名", 24))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = DEFAULT_NAME
	_name_edit.max_length = MAX_NAME_LENGTH
	_name_edit.custom_minimum_size = Vector2(260, 52)
	_name_edit.add_theme_font_size_override("font_size", 26)
	name_row.add_child(_name_edit)
	name_row.add_child(UiKit.label("最多 %d 个字" % MAX_NAME_LENGTH, 18, UiKit.TEXT_DIM))

	v.add_child(UiKit.label("出身", 24))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	for o in GameDB.origin_list():
		row.add_child(_make_card(o))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(bottom)
	var back := UiKit.button("返回", Vector2(160, 64), 24)
	back.pressed.connect(func() -> void: back_requested.emit())
	bottom.add_child(back)
	_start = UiKit.button("踏入江湖", Vector2(220, 64), 28)
	_start.pressed.connect(_on_start)
	bottom.add_child(_start)

	var origins := GameDB.origin_list()
	if not origins.is_empty():
		_choose(origins[0])


func _make_card(o: OriginData) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)
	var portrait := TextureRect.new()
	portrait.texture = o.unit.portrait
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(170, 0)
	h.add_child(portrait)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UiKit.label(o.display_name, 32, UiKit.GOLD))
	var desc := UiKit.label(o.description, 18, UiKit.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var skill := o.unit.skill
	v.add_child(UiKit.label("绝招「%s」" % skill.display_name, 20, UiKit.GOLD))
	var skill_desc := UiKit.label(skill.description, 16, UiKit.TEXT_DIM)
	skill_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(skill_desc)
	var loc: LocationData = GameDB.maps[GameState.DEFAULT_MAP].location(o.start_location)
	v.add_child(UiKit.label("开局：%s" % (loc.display_name if loc != null else "?"), 18, UiKit.TEXT_DIM))

	UiKit.ignore_mouse(card)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_choose(o))
	_cards[o] = card
	return card


func _choose(o: OriginData) -> void:
	_chosen = o
	for other in _cards:
		var picked := other == o
		_cards[other].add_theme_stylebox_override("panel", UiKit.box(UiKit.role_color(other.unit), UiKit.ACCENT if picked else UiKit.PANEL_LIGHT, 5 if picked else 2))


func _on_start() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name == "":
		player_name = DEFAULT_NAME
	created.emit(player_name, _chosen)
