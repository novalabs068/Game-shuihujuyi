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
	UiKit.backdrop(self)
	# 设计稿大小的居中画框（宽屏时整块居中）；「归」贴屏幕右上角，不放进来
	var frame := UiKit.design_frame(self)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.position = Vector2(28, 16)
	frame.add_child(head)
	head.add_child(UiKit.page_title("投身江湖", "", 46))
	var hint := UiKit.label("选一条出身，职业定下就不再改", 15, Color("cdb68a"))
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hint)
	var back := UiKit.back_button()
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -74
	back.offset_right = -20
	back.offset_top = 14
	back.pressed.connect(func() -> void: back_requested.emit())

	# 左边：五支职业木签，选中的变朱漆、往上抬一截
	var roles := HBoxContainer.new()
	roles.add_theme_constant_override("separation", 14)
	roles.alignment = BoxContainer.ALIGNMENT_END
	roles.position = Vector2(30, 120)
	roles.custom_minimum_size = Vector2(0, 280)
	frame.add_child(roles)
	for o in GameDB.origin_list():
		var b := UiKit.slip_button(o.display_name, 84, 30)
		b.custom_minimum_size.y = maxf(b.custom_minimum_size.y + 48, 230)
		b.set_meta("base_height", b.custom_minimum_size.y)
		b.size_flags_vertical = Control.SIZE_SHRINK_END
		var l: Label = b.get_meta("label")
		l.offset_top = 76
		var badge := UiKit.brush_label(UiKit.ROLE_TAGS[o.unit.role], 24, Color("e9c979"))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var ring := StyleBoxFlat.new()
		ring.bg_color = UiKit.INK
		ring.border_color = UiKit.GILT
		ring.set_border_width_all(2)
		ring.set_corner_radius_all(21)
		badge.add_theme_stylebox_override("normal", ring)
		badge.custom_minimum_size = Vector2(42, 42)
		badge.position = Vector2(21, 26)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(badge)
		b.pressed.connect(_choose.bind(o))
		roles.add_child(b)
		_role_buttons[o] = b

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.position = Vector2(30, 430)
	info.custom_minimum_size.x = 500
	info.size.x = 500
	frame.add_child(info)
	_origin_title = UiKit.brush_label("", 30, Color("e9c979"))
	info.add_child(_origin_title)
	_origin_desc = _wrap(UiKit.label("", 16, UiKit.TEXT))
	info.add_child(_origin_desc)
	_role_desc = _wrap(UiKit.label("", 14, UiKit.TEXT_DIM))
	info.add_child(_role_desc)

	# 中间：立绘
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.position = Vector2(530, 90)
	_portrait.size = Vector2(PORTRAIT_SIZE * 0.78, PORTRAIT_SIZE + 70)
	frame.add_child(_portrait)

	# 右边：宣纸页上起名、选男女、看开局武学，最后「踏入江湖」
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", UiKit.panel_box())
	page.position = Vector2(916, 110)
	page.size = Vector2(344, 530)
	frame.add_child(page)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	page.add_child(v)
	v.add_child(UiKit.brush_label("姓名", 24, UiKit.INDIGO))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = DEFAULT_NAME
	_name_edit.max_length = MAX_NAME_LENGTH
	_name_edit.custom_minimum_size = Vector2(220, 58)
	_name_edit.add_theme_font_override("font", UiKit.brush_font())
	_name_edit.add_theme_font_size_override("font_size", 36)
	_name_edit.add_theme_color_override("font_placeholder_color", Color(UiKit.INK, 0.45))
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0, 0, 0, 0)
	line.border_color = UiKit.INK
	line.border_width_bottom = 2
	line.set_content_margin_all(4)
	_name_edit.add_theme_stylebox_override("normal", line)
	_name_edit.add_theme_stylebox_override("focus", line)
	v.add_child(_name_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var gender_head := UiKit.brush_label("性别", 24, UiKit.INDIGO)
	gender_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gender_head)
	for g: StringName in GameState.GENDERS:
		var b := UiKit.seal_button("男" if g == GameState.GENDER_MALE else "女", 58, 30)
		b.pressed.connect(_choose_gender.bind(g))
		row.add_child(b)
		_gender_buttons[g] = b
	var martial := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UiKit.CINNABAR, 0.07)
	box.border_color = Color(UiKit.CINNABAR, 0.35)
	box.set_border_width_all(1)
	box.set_content_margin_all(10)
	martial.add_theme_stylebox_override("panel", box)
	v.add_child(martial)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 4)
	martial.add_child(mv)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	mv.add_child(mrow)
	mrow.add_child(UiKit.seal_label("开局武学", 15))
	_martial_title = UiKit.label("", 17, UiKit.INK)
	mrow.add_child(_martial_title)
	_martial_desc = _wrap(UiKit.label("", 14, UiKit.INK))
	mv.add_child(_martial_desc)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	var start := UiKit.plaque_button("踏入江湖", Vector2(220, 64), true, 32)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(_on_start)
	v.add_child(start)

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
	for other in _role_buttons:
		UiKit.set_slip_lit(_role_buttons[other], other == o)
	_origin_desc.text = o.description
	_role_desc.text = "%s：%s。职业开局定下就不再变；学到别的职业的武学也能主修，但威力只有七成。" % [UiKit.ROLE_NAMES[o.unit.role], Roles.summary(o.unit.role)]
	var skill := o.martial.skill if o.martial != null else o.unit.skill
	_martial_title.text = "「%s」" % (o.martial.display_name if o.martial != null else skill.display_name)
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


## 选中的职业木签往上抬一截；选中的男女是朱印，另一个褪成淡墨。
func _highlight(b: Button, on: bool) -> void:
	if b.has_meta("base_height"):
		b.custom_minimum_size.y = (b.get_meta("base_height") as float) + (16.0 if on else 0.0)
	else:
		b.modulate = Color.WHITE if on else Color(0.55, 0.5, 0.45, 0.6)


func _on_start() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name == "":
		player_name = DEFAULT_NAME
	created.emit(player_name, _chosen, _gender)
