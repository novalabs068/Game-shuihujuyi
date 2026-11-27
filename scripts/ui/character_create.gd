class_name CharacterCreate
extends Control
## 创建角色：选职业（每个职业一个出身）、选男女、起名字。
## 左边选，右边是选中的出身和性别的立绘。职业开局定下就不再变；男女只换立绘和称呼，属性一样。

signal created(player_name: String, origin: OriginData, gender: StringName)
signal back_requested

const MAX_NAME_LENGTH := 6
const DEFAULT_NAME := "无名"
const ROLE_BUTTON_SIZE := Vector2(132, 82)
const GENDER_BUTTON_SIZE := Vector2(110, 52)
const PORTRAIT_SIZE := 560

var _name_edit: LineEdit
var _role_buttons: Dictionary[OriginData, Button] = {}
var _gender_buttons: Dictionary[StringName, Button] = {}
var _chosen: OriginData
var _gender: StringName = GameState.GENDER_MALE
var _portrait: TextureRect
var _origin_title: Label
var _origin_desc: Label
var _martial_title: Label
var _martial_desc: Label
var _role_desc: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	margin.add_child(body)

	# 左边：职业、性别、名字、出身说明、按钮
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(v)
	v.add_child(UiKit.label("创建角色", 32))

	v.add_child(UiKit.label("职业", 20, UiKit.TEXT_DIM))
	var roles := HBoxContainer.new()
	roles.add_theme_constant_override("separation", 10)
	v.add_child(roles)
	for o in GameDB.origin_list():
		var b := UiKit.button("%s\n%s" % [UiKit.ROLE_NAMES[o.unit.role], o.display_name], ROLE_BUTTON_SIZE, 20)
		b.pressed.connect(_choose.bind(o))
		roles.add_child(b)
		_role_buttons[o] = b

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(UiKit.label("性别", 20, UiKit.TEXT_DIM))
	for g: StringName in GameState.GENDERS:
		var b := UiKit.button("男" if g == GameState.GENDER_MALE else "女", GENDER_BUTTON_SIZE, 22)
		b.pressed.connect(_choose_gender.bind(g))
		row.add_child(b)
		_gender_buttons[g] = b
	var gap := Control.new()
	gap.custom_minimum_size.x = 24
	row.add_child(gap)
	row.add_child(UiKit.label("姓名", 20, UiKit.TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = DEFAULT_NAME
	_name_edit.max_length = MAX_NAME_LENGTH
	_name_edit.custom_minimum_size = Vector2(220, 52)
	_name_edit.add_theme_font_size_override("font_size", 24)
	row.add_child(_name_edit)

	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.PANEL_LIGHT, 1, 6))
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(info)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 6)
	info.add_child(iv)
	_origin_title = UiKit.label("", 26, UiKit.GOLD)
	iv.add_child(_origin_title)
	_origin_desc = _wrap(UiKit.label("", 18))
	iv.add_child(_origin_desc)
	_role_desc = _wrap(UiKit.label("", 16, UiKit.TEXT_DIM))
	iv.add_child(_role_desc)
	_martial_title = UiKit.label("", 20, UiKit.GOLD)
	iv.add_child(_martial_title)
	_martial_desc = _wrap(UiKit.label("", 16, UiKit.TEXT_DIM))
	iv.add_child(_martial_desc)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(bottom)
	var back := UiKit.button("返回", Vector2(150, 60), 24)
	back.pressed.connect(func() -> void: back_requested.emit())
	bottom.add_child(back)
	var start := UiKit.button("踏入江湖", Vector2(220, 60), 28)
	start.pressed.connect(_on_start)
	bottom.add_child(start)

	# 右边：立绘
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE * 0.78, PORTRAIT_SIZE)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_END
	body.add_child(_portrait)

	var origins := GameDB.origin_list()
	if not origins.is_empty():
		_choose(origins[0])
	_choose_gender(GameState.GENDER_MALE)


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _choose(o: OriginData) -> void:
	_chosen = o
	for other in _role_buttons:
		_highlight(_role_buttons[other], other == o)
	var loc: LocationData = GameDB.maps[GameState.DEFAULT_MAP].location(o.start_location)
	_origin_title.text = "%s · %s　开局：%s" % [UiKit.ROLE_NAMES[o.unit.role], o.display_name, loc.display_name if loc != null else "?"]
	_origin_desc.text = o.description
	_role_desc.text = "%s：%s。职业开局定下就不再变；学到别的职业的武学也能主修，但威力只有七成。" % [UiKit.ROLE_NAMES[o.unit.role], Roles.summary(o.unit.role)]
	var skill := o.martial.skill if o.martial != null else o.unit.skill
	_martial_title.text = "开局武学「%s」" % (o.martial.display_name if o.martial != null else skill.display_name)
	_martial_desc.text = skill.description
	_refresh_portrait()


func _choose_gender(g: StringName) -> void:
	_gender = g
	for other in _gender_buttons:
		_highlight(_gender_buttons[other], other == g)
	_refresh_portrait()


func _refresh_portrait() -> void:
	if _chosen == null or _portrait == null:
		return
	var female := _gender == GameState.GENDER_FEMALE and _chosen.portrait_female != null
	_portrait.texture = _chosen.portrait_female if female else _chosen.unit.portrait


## 选中的按钮描金边。
func _highlight(b: Button, on: bool) -> void:
	b.modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)
	if on:
		b.add_theme_stylebox_override("normal", UiKit.box(UiKit.PANEL_LIGHT, UiKit.GOLD, 3, 6))
	else:
		b.remove_theme_stylebox_override("normal")


func _on_start() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name == "":
		player_name = DEFAULT_NAME
	created.emit(player_name, _chosen, _gender)
